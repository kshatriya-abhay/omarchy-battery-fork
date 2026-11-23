# omarchy-battery-fork

My fork of Omarchy's built-in `omarchy.power` bar widget (laptop battery, power
profiles, system stats), installed as `abhay.power`. It adds peripheral
batteries (mouse, keyboard, headset, controllers), adapted from
`hl.peripheral_battery` (source: `/data/Projects/omarchy-peripheral-battery`).

## Layout

- `Panel.qml`, `Model.js`, `manifest.json`: the stock plugin files, edited.
  Keep changes to these small, so upstream merges stay easy.
- `peripherals/`: everything new. `PeripheralService.qml` is the shell service
  entry point (one instance shared by every monitor), `PeripheralSection.qml`
  is the popup section, `DeviceIcons.qml` is a singleton registered in
  `peripherals/qmldir`.
- Devices UPower doesn't expose are read by small C helpers over hidraw
  (`steam_controller_battery.c`, `cosmic_byte_aether_battery.c`). Each one is
  a `HelperSource` in `PeripheralService.qml`, compiled on first use by
  `build_helper.sh <name>` into `~/.cache/abhay-power-peripherals/`. Every
  line a helper prints is the device's state (`{id, type, pct, state, model,
  charging}`, pct may be null) or `{"absent": true}`. The Steam one is
  one-shot: it runs on the 30 s poll and prints nothing when the controller is
  absent. The Aether one is `persistent: true`: it runs for the life of the
  shell and prints a line only when the reading changes.
- The Aether helper is event-driven to stay cheap: inotify on `/dev` for
  hotplug, no requests at all on the cable, and on the dongle one reading
  every 5 min, sent only after the mouse sends some input (so a sleeping
  mouse is never asked). Build it with `-DAETHER_TRACE` to log its activity
  to stderr.
- Cosmic Byte Aether protocol (from the Orbit web configurator's
  `AetherDriver.js`): SET_FEATURE `09 81 01 00…` on the `0xFF05` interface,
  reply is input report `09 <battery%> …`. Once asked, the mouse pushes its
  state every 5 s on its own and ignores requests in between, so the helper
  re-sends every second for up to 6 s, then closes the node until the next
  reading. The first report after the link comes up can be wrong (50 on a
  full battery), so it reads again 30 s after connecting. On the cable
  it always reads 100, so the wired PID (`0x5B49`) alone means charging and
  the helper prints `"pct": null`; the popup then shows "Charging", no bar.

## Branches

- `upstream`: the stock files from `/usr/share/omarchy/shell/plugins/panels/power/`,
  exactly as shipped, one commit per Omarchy version.
- `main`: `upstream` plus my changes.

To take a new stock version, run `./sync-upstream.sh` on a clean `main`. It
copies the installed stock plugin onto `upstream` and commits it as "sync with
upstream omarchy <version>" if anything changed, then cherry-picks that onto
`main`. On success it copies the plugin into place and restarts the shell.
Pushing both branches to `origin` is off by default; this clone turns it on
with `git config sync-upstream.push true` (or pass `--push`). On a
conflict it aborts, puts `upstream` back so the next run retries, and prints
the commands to resolve it by hand. It always exits 0. It runs after every `omarchy update` through the symlink
`~/.config/omarchy/hooks/post-update.d/omarchy-battery-fork-sync.hook`.

## After every change

1. **Copy the code into the installed plugin.** The shell runs the copy in
   `~/.config/omarchy/plugins/abhay.power/`, not this repo:
   ```bash
   rsync -a --delete --exclude .git --exclude CLAUDE.md --exclude sync-upstream.sh \
     /data/Projects/omarchy-battery-fork/ ~/.config/omarchy/plugins/abhay.power/
   ```
2. **Restart the shell** so the changes apply (the service and the qmldir
   singleton aren't reliably picked up by hot-reload):
   ```bash
   omarchy restart shell
   ```
3. Check the shell log for QML errors mentioning `abhay.power` or `peripherals/`:
   `quickshell log -p /usr/share/omarchy/shell | grep -iE 'abhay.power/|peripherals/|Error'`

To test without clicking: `omarchy-shell omarchy.power open|close|toggleCompact`
(the clone keeps the built-in IPC target), then screenshot with `grim`.

Never edit `/usr/share/omarchy/`; it belongs to the omarchy package.
