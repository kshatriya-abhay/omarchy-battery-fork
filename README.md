# omarchy-battery-fork

Omarchy's built-in `omarchy.power` bar widget (laptop battery, power profiles,
system stats), with peripheral batteries added from
[omarchy-peripheral-battery](https://github.com/kshatriya-abhay/omarchy-peripheral-battery).

The bar looks the same as stock. The popup gets a **Peripherals** section
listing each wireless mouse, keyboard, headset or controller with its charge.
A device turns red when it drops to the low threshold (20% by default), and a
desktop notification fires at the same point, with a critical one at 10%.

## Branches

- `upstream`: the stock `omarchy.power` files, one commit per Omarchy version.
- `main`: `upstream` plus the peripheral changes (mostly in `peripherals/`).

## Install

```bash
git clone https://github.com/kshatriya-abhay/omarchy-battery-fork.git ~/src/omarchy-battery-fork
rsync -a --exclude .git --exclude CLAUDE.md --exclude sync-upstream.sh \
  ~/src/omarchy-battery-fork/ ~/.config/omarchy/plugins/abhay.power/
omarchy-shell shell rescanPlugins
omarchy plugin enable abhay.power   # replaces omarchy.power in the bar
```

## Keeping up with Omarchy updates

`sync-upstream.sh` brings new versions of the stock plugin into the fork. It
commits the installed `omarchy.power` files on `upstream`, cherry-picks that
onto `main`, then copies the plugin into place, restarts the shell and pushes
both branches. If the cherry-pick conflicts, it changes nothing and prints how
to resolve it by hand. It always exits 0.

To run it at the end of every `omarchy update`, symlink it into the
post-update hooks. Use a symlink, not `omarchy hook install`, which makes a
copy: the script finds the repo from its own location.

```bash
ln -s ~/src/omarchy-battery-fork/sync-upstream.sh \
  ~/.config/omarchy/hooks/post-update.d/omarchy-battery-fork-sync.hook
```

Keep the clone on `main` with no uncommitted changes; otherwise the hook skips
with a message. The push only works to a repo you can write to, so fork this
one and clone your fork if you want that step. Without access, the push fails
with a message and the rest still runs.

To remove the hook: `rm ~/.config/omarchy/hooks/post-update.d/omarchy-battery-fork-sync.hook`
