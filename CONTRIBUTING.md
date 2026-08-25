# Contributing

Source of truth: this repository, installed as a normal Omarchy plugin.
Display name is **WorkScape**; plugin id is `io.github.calebhat.workscape`.

```bash
omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.calebhat.workscape
```

On a development machine, rsync into the user plugin dir (plugin folders must
not contain symlinks):

```bash
rsync -a --delete --exclude .git --exclude .gitignore --exclude test \
  --exclude CONTRIBUTING.md \
  ./ ~/.config/omarchy/plugins/io.github.calebhat.workscape/
omarchy restart shell
```

Run tests from the repo root:

```bash
node test/model.test.js
python3 test/gestures.test.py
python3 test/network.test.py
bash test/match.test.sh
omarchy plugin validate .
```

Marketplace listing: only after this tree is on GitHub `master` (the site
clones HEAD). Do not file the omarchyplugins.com issue until the owner has
day-to-day tested the pushed commit.

Suggested listing: category Desktop; tags Hyprland, Workspaces, Bar.
Copy the “Marketplace blurb” from README.md into the issue form.
