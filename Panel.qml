import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "peripherals"

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  // Keyboard cursor section: "profiles", then the peripheral "compact" switch
  // and "devices" rows below it.
  property string focusSection: "profiles"
  property int deviceIndex: 0
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  // ---------- Peripherals (adapted from hl.peripheral_battery) ----------
  // The service entry point is one shell-managed instance shared by every
  // monitor's panel. Clones keep the built-in id, which the shell resolves to
  // this plugin.
  readonly property var peripheralService: root.bar && root.bar.shell
    ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property var peripherals: peripheralService ? peripheralService.devices : []
  readonly property bool hasPeripherals: peripherals.length > 0

  readonly property int lowThreshold: setting("lowThreshold", 20)
  // Must stay below lowThreshold or the warning tier disappears.
  readonly property int criticalThreshold: Math.min(setting("criticalThreshold", 10), lowThreshold - 1)
  readonly property bool notifyOnLow: setting("notifyOnLow", true)
  readonly property int notifyRepeatMinutes: setting("notifyRepeatMinutes", 0)
  readonly property var deviceTypes: listSetting("deviceTypes", ["mouse", "keyboard", "headset", "gamepad"])
  // compact: show up to 3 devices in the bar, pinned ones first.
  readonly property bool compactMode: setting("compact", false) === true
  readonly property var pinnedNames: listSetting("pinned", [])

  // shell.json lists arrive as a list type that fails Array.isArray and lacks
  // array methods, so copy anything list-like into a plain array.
  function listSetting(name, fallback) {
    var raw = settings ? settings[name] : null
    if (!raw || typeof raw === "string" || typeof raw.length !== "number") return fallback
    return Array.prototype.slice.call(raw)
  }
  readonly property int compactLimit: 3

  function syncPeripheralSettings() {
    if (!peripheralService) return
    peripheralService.lowThreshold = lowThreshold
    peripheralService.criticalThreshold = criticalThreshold
    peripheralService.notifyOnLow = notifyOnLow
    peripheralService.notifyRepeatMinutes = notifyRepeatMinutes
    peripheralService.deviceTypes = deviceTypes
  }
  onPeripheralServiceChanged: syncPeripheralSettings()
  onLowThresholdChanged: syncPeripheralSettings()
  onCriticalThresholdChanged: syncPeripheralSettings()
  onNotifyOnLowChanged: syncPeripheralSettings()
  onNotifyRepeatMinutesChanged: syncPeripheralSettings()
  onDeviceTypesChanged: syncPeripheralSettings()
  Component.onCompleted: syncPeripheralSettings()

  function deviceName(device) { return device.model || device.type }

  // The device lowest on charge: drives the bar label's tint and tooltip.
  readonly property var neediestPeripheral: {
    var r = null
    for (var i = 0; i < peripherals.length; i++)
      if (!r || peripherals[i].pct < r.pct) r = peripherals[i]
    return r
  }
  readonly property int peripheralTier: neediestPeripheral
    ? DeviceIcons.tier(neediestPeripheral.pct, neediestPeripheral.state, lowThreshold, criticalThreshold) : 0

  // What the bar shows next to the battery icon: pinned devices, or in
  // compact mode pinned devices first and then the rest, up to compactLimit.
  readonly property var barPeripherals: {
    var pinned = []
    var rest = []
    for (var i = 0; i < peripherals.length; i++) {
      if (pinnedNames.indexOf(deviceName(peripherals[i])) !== -1) pinned.push(peripherals[i])
      else rest.push(peripherals[i])
    }
    return (compactMode ? pinned.concat(rest) : pinned).slice(0, compactLimit)
  }
  readonly property string peripheralBarText: {
    var parts = []
    for (var i = 0; i < barPeripherals.length; i++)
      parts.push(DeviceIcons.glyph(barPeripherals[i].type) + " " + barPeripherals[i].pct + "%")
    return parts.join(" · ")
  }

  function persistSettings(extra) {
    root.settings = Object.assign({}, root.settings, extra)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function togglePin(name) {
    var list = pinnedNames.slice()
    var i = list.indexOf(name)
    if (i !== -1) list.splice(i, 1)
    else list.push(name)
    persistSettings({ pinned: list })
  }

  function setCompact(on) { persistSettings({ compact: !!on }) }
  function toggleCompact() { setCompact(!compactMode) }

  function activatePeripheral(i) {
    if (i < 0 || i >= peripherals.length) return
    togglePin(deviceName(peripherals[i]))
  }

  // Up/down walks profiles -> compact switch -> device rows; left/right picks
  // a profile. Without peripherals this is the stock behavior.
  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (focusSection === "profiles") {
      if (dx !== 0) selectProfileByDelta(dx)
      else if (dy > 0 && hasPeripherals) focusSection = "compact"
      else if (dy !== 0) selectProfileByDelta(dy)
    } else if (focusSection === "compact") {
      if (dy > 0) { focusSection = "devices"; deviceIndex = 0 }
      else if (dy < 0) focusSection = "profiles"
    } else if (focusSection === "devices") {
      if (dy > 0) deviceIndex = Math.min(peripherals.length - 1, deviceIndex + 1)
      else if (dy < 0) {
        if (deviceIndex > 0) deviceIndex--
        else focusSection = "compact"
      }
    }
  }

  function activateCursor() {
    if (focusSection === "compact") toggleCompact()
    else if (focusSection === "devices") activatePeripheral(deviceIndex)
    else activateSelectedProfile()
  }

  onPeripheralsChanged: {
    if (!hasPeripherals && focusSection !== "profiles") focusSection = "profiles"
    else if (deviceIndex >= peripherals.length) deviceIndex = Math.max(0, peripherals.length - 1)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Commons.Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    function toggleCompact() { root.toggleCompact() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      focusSection = "profiles"
      deviceIndex = 0
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent
    ? button.implicitWidth + (showPeripheralLabel ? peripheralButton.implicitWidth : 0) : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0
  readonly property bool showPeripheralLabel: peripheralBarText !== "" && !button.vertical

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  // Battery icon, then the pinned peripherals ("glyph pct · ...") when any.
  Row {
    id: indicator
    height: parent.height

    BarIconButton {
      id: button
      // Fill the slot like the stock button unless the peripheral label sits beside it.
      width: root.showPeripheralLabel ? implicitWidth : root.width
      height: root.height
      bar: root.bar
      text: root.showPercentage && !vertical
        ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
        : root.batteryIcon()
      slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
      tooltipText: ""
      onPressed: function(b) {
        if (!root.batteryPresent) return
        if (b === Qt.RightButton) root.togglePercentage()
        else root.toggle()
      }
    }

    WidgetButton {
      id: peripheralButton
      height: root.height
      visible: root.showPeripheralLabel
      bar: root.bar
      text: root.peripheralBarText
      labelVisible: true
      useActiveColor: false
      fontSize: Style.font.body
      foreground: DeviceIcons.tierColor(root.peripheralTier, root.barForeground)
      tooltipText: root.neediestPeripheral
        ? root.deviceName(root.neediestPeripheral) + " " + root.neediestPeripheral.pct + "%"
        : ""
      // Right-click flips "show all in bar", like the original plugin.
      onPressed: function(b) {
        if (b === Qt.RightButton) root.toggleCompact()
        else root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: indicator
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "profiles"
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        // ---------- Peripherals ----------
        PanelSeparator {
          visible: root.hasPeripherals
          foreground: root.bar.foreground
        }

        PeripheralSection {
          visible: root.hasPeripherals
          width: parent.width
          bar: root.bar
          devices: root.peripherals
          pinnedNames: root.pinnedNames
          compactMode: root.compactMode
          lowThreshold: root.lowThreshold
          criticalThreshold: root.criticalThreshold
          cursorActive: root.cursorActive
          focusSection: root.focusSection
          selectedIndex: root.deviceIndex
          onTogglePin: function(name) { root.togglePin(name) }
          onCompactToggle: function(on) { root.setCompact(on) }
          onHoverToggle: { root.cursorActive = true; root.focusSection = "compact" }
          onHoverDevice: function(i) { root.cursorActive = true; root.focusSection = "devices"; root.deviceIndex = i }
          onActivateDevice: function(i) { root.activatePeripheral(i) }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
