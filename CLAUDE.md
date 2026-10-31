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
