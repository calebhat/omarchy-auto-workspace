# Contributing

Source of truth: this repository, installed as a normal Omarchy plugin.
Display name is **SceneBook**; plugin id is `io.github.calebhat.scenebook`.

```bash
omarchy plugin add https://github.com/calebhat/omarchy-scenebook.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.calebhat.scenebook
```

On this machine, development lives in `~/Work/omarchy-scenebook` and deploys with rsync (plugin folders must not contain symlinks):

```bash
rsync -a --delete --exclude .git --exclude .gitignore --exclude test --exclude CONTRIBUTING.md \
  ~/Work/omarchy-scenebook/ \
  ~/.config/omarchy/plugins/io.github.calebhat.scenebook/
omarchy restart shell
```

Do not keep a second copy inside private dotfiles.

Commit as `calebhat <97716470+calebhat@users.noreply.github.com>`.

Do not submit this plugin to the Omarchy plugin marketplace unless that is asked for explicitly.
