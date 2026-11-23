import QtQuick
import Quickshell.Io

// A device UPower doesn't know about, read by a native helper (<name>.c beside
// this file), compiled once by build_helper.sh.
//
// Every line the helper prints is the device's current state:
// {id, type, pct, state, model, charging}, where pct is null when the device
// can't report it (a mouse charging on its cable), or {"absent": true}.
// A one-shot helper (the default) runs on every refresh() and prints at most
// one line; printing none means absent. A persistent helper starts once and
// prints a line whenever the state changes; if it exits, it is restarted.
Item {
    id: src

    required property string name      // helper source name, without ".c"
    property bool persistent: false
    property var device: null           // {id, type, pct, state, model, charging} or null

    property string _binary: ""

    function localPath(relativePath) {
        var url = Qt.resolvedUrl(relativePath).toString();
        return url.startsWith("file://") ? decodeURIComponent(url.substring(7)) : url;
    }

    function refresh() {
        if (!persistent && _binary && !run.running) run.running = true;
    }

    Process {
        id: build
        command: ["sh", src.localPath("build_helper.sh"), src.name]
        running: true
        stdout: StdioCollector { id: buildOut; waitForEnd: true }
        stderr: StdioCollector { id: buildErr; waitForEnd: true }
        onExited: function (code, status) {
            if (code !== 0) {
                console.warn(src.name + " battery helper build failed:", code, buildErr.text);
                return;
            }
            src._binary = buildOut.text.trim();
            run.running = true;
        }
    }

    Process {
        id: run
        property bool _printed: false
        command: src._binary ? [src._binary] : []
        onRunningChanged: if (running) _printed = false
        stdout: SplitParser {
            onRead: function (line) {
                var r;
                try {
                    r = JSON.parse(line);
                } catch (error) {
                    console.warn(src.name + " battery helper: invalid output:", error);
                    return;
                }
                run._printed = true;
                src.device = r.absent ? null
                    : {id: r.id, type: r.type, pct: r.pct, state: r.state,
                       model: r.model, charging: r.charging};
            }
        }
        stderr: StdioCollector { id: runErr }
        onExited: function (code, status) {
            if (src.persistent || !_printed) src.device = null;
            if (src.persistent || code > 1)
                console.warn(src.name + " battery helper exited:", code, runErr.text);
            if (src.persistent) restart.start();
        }
    }

    Timer {
        id: restart
        interval: 10000
        onTriggered: run.running = true
    }
}
