pragma Singleton
import QtQuick

// Single source of truth for device *types*: the canonical type list, the words
// the `upower` CLI can emit, and the type -> glyph mapping. Registered as a
// singleton in qmldir, so PeripheralService / UPowerSource / PeripheralSection share it.
//
// Nerd Font (Material Design) codepoints — needs a Nerd-Font-patched family at the
// bar for these to render. Built via String.fromCodePoint so the Plane-15 (5-hex)
// codepoints can't get truncated/mangled by text encoding.
QtObject {
    // Canonical peripheral types we display. Also the default filter set.
    readonly property var known: [
        "mouse", "keyboard", "headset", "headphones",
        "gamepad", "pen", "other"
    ]

    // Section-header words `upower -i` can emit (path B parses these). Superset of
    // `known` plus power-supply / non-peripheral types we recognize only so the
    // parser can identify and then filter them out.
    readonly property var parseHeaders: [
        "gaming-input", "gaming input",
        "battery", "ups", "tablet", "phone", "touchpad", "speakers"
    ].concat(known)

    function normalizeType(type) {
        var normalized = String(type || "").trim().toLowerCase();
        if (normalized === "gaming-input" || normalized === "gaming input")
            return "gamepad";
        return normalized;
    }

    // Charge tier used for the popup's red rows and the low-battery notifications:
    // 0 = normal, 1 = warning (<= lowThreshold), 2 = critical (<= criticalThreshold).
    // Charging/fully-charged is always 0 regardless of pct.
    function tier(pct, state, lowThreshold, criticalThreshold) {
        if (state === "charging" || state === "fully-charged") return 0;
        if (pct <= criticalThreshold) return 2;
        if (pct <= lowThreshold) return 1;
        return 0;
    }

    function glyph(type) {
        switch (type) {
        case "mouse":        return String.fromCodePoint(0xF037D); // nf-md-mouse
        case "keyboard":     return String.fromCodePoint(0xF030C); // nf-md-keyboard
        case "headset":      return String.fromCodePoint(0xF02CE); // nf-md-headset
        case "headphones":   return String.fromCodePoint(0xF02CB); // nf-md-headphones
        case "gamepad":      return String.fromCodePoint(0xF0297); // nf-md-gamepad_variant
        case "pen":          return String.fromCodePoint(0xF03EA); // nf-md-pen
        default:             return String.fromCodePoint(0xF0FB0); // nf-md-devices
        }
    }

    // charging indicator: nf-md-lightning_bolt
    readonly property string bolt: String.fromCodePoint(0xF140B)
}
