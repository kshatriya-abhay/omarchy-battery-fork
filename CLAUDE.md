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

## Branches

- `upstream`: the stock files from `/usr/share/omarchy/shell/plugins/panels/power/`,
  exactly as shipped, one commit per Omarchy version.
- `main`: `upstream` plus my changes.

To take a new stock version, run `./sync-upstream.sh` on a clean `main`. It
compares `upstream` with the installed stock plugin and, if they differ, merges
the new stock files into `main` as "sync with upstream omarchy <version>",
moves `upstream` forward, copies the plugin into place and restarts the shell.
On a merge conflict it lists the files, aborts the merge so nothing changes,
prints the `git merge` command to resolve it by hand, and still exits 0.

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
