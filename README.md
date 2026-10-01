# linx

Your home on a 42 machine is capped at about 5 GB. Caches, `node_modules` and
editor extensions eat most of it, and deleting them is pointless because they
come straight back.

linx moves the regenerable directories to ur goinfre and leaves a symlink behind
so every app still finds its files and none of it counts against your quota

## Use it

```sh
git clone https://github.com/ayouz0/linx.git ~/linx
~/linx/linx.sh
```

It scans your home, shows what it can move, and waits for you to choose:

```
linx scanning /home/aaitabde -> /goinfre/aaitabde/cache

  #    size  what
  1    848 MB  .var/app/com.visualstudio.code/data/vscode/extensions
  2    635 MB  hyperTube/backend/node_modules
  3    120 MB  .var/app/com.google.Chrome/config/google-chrome/screen_ai
  4     18 MB  .var/app/com.visualstudio.code/config/Code/WebStorage/1/CacheStorage  <- code is RUNNING
     1621 MB movable in total

warn quit a RUNNING app before moving its dirs, or it may misbehave until restart

move what? [a]ll / numbers like 1 3 5 / [q]uit:
```

Nothing is touched until you answer.

| | |
|---|---|
| `linx.sh` | scan, then ask |
| `linx.sh -n` | dry run, show the table and stop |
| `linx.sh -y` | move everything, no questions |
| `linx.sh -q` | re-create the targets, silent (for your shell rc) |
| `MIN_MB=5 linx.sh` | include dirs smaller than the 25 MB default |
| `STORE=/sgoinfre/$USER/cache linx.sh` | use somewhere other than `/goinfre/$USER/cache` |

## Changing machine

`/goinfre` is per machine and gets wiped, which would leave your symlinks
pointing at nothing. So `linx.sh -q` walks your home, finds its own links and
re-creates whatever targets are missing. After the first move the script offers
to add it to your `~/.zshrc` for you:

```sh
~/linx/linx.sh -q
```

The directories come back empty, which is the point: run `npm install` again,
let VS Code reinstall its extensions, let the browsers rebuild their caches.
Nothing you had to keep was in there.

## What it moves

Found fresh on every run, never a hardcoded list:

- `~/.cache`, `~/.local/share/Trash`, and the package stores it finds
  (`.npm/_cacache`, bun, yarn, cargo registry, `.m2`, go mod, gradle, nuget)
- every cache-shaped directory under `~/.var/app` — so it works with whatever
  flatpaks you happen to have, not just the ones I use
- every `node_modules` and `.venv` in your projects, at any depth
- VS Code / VSCodium extension stores

Only directories at least `MIN_MB` big get a symlink, so a fresh machine
doesn't end up with a hundred links to empty folders.

## What it will not move

- `~/.nvm/versions/*/lib/node_modules` — `npm` itself lives there, and losing
  it on a machine change breaks node, not just your packages
- browser `Default/Extensions` — that is real extension data, not cache
- anything already a symlink

It copies before it deletes, so a full `/goinfre` costs you time, not files.

## Docker

linx does not touch docker. If images are filling your home, point docker at
goinfre yourself in `~/.config/docker/daemon.json` and restart it:

```json
{ "data-root": "/goinfre/YOUR_LOGIN/docker/" }
```

## Credit

The directory list started from [xcleaner](https://github.com/bahimzabir/xcleaner)
by azabir, which cleans the same caches by deleting them.

by aaitabde
