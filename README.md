<div align="center">

# 🐢 simple-shell-scripts

**Small, friendly shell scripts for Git, Xcode and the iOS Simulator.**<br>
Install once per Mac, update with one command. They carry their shell everywhere.

[![CI](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/tag/xaverlutz/simple-shell-scripts?label=release&sort=semver&color=2ea44f)](https://github.com/xaverlutz/simple-shell-scripts/tags)
![macOS](https://img.shields.io/badge/macOS-zsh%20%26%20bash-555?logo=apple)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE.md)

</div>

---

## ✨ At a glance

| Command | What it does |
|---|---|
| 🌱 [`create_branch`](#-create_branch) | New branch from a freshly pulled `main`, optionally with a first commit |
| 🧹 [`delete_local_branch`](#-delete_local_branch) | Removes local branches whose remote branch is gone |
| 🧽 [`reset_build`](#-reset_build) | Deletes the `.build` folder of a Swift package |
| 📍 [`send_location`](#-send_location) | Sets the iOS Simulator's location from a city name |
| 🐢 [`update_shell_scripts`](#-staying-up-to-date) | Updates all of the above to the newest release |

## 🚀 Install

On any Mac, paste this into Terminal:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xaverlutz/simple-shell-scripts/main/install.sh)"
```

That's it. The installer:

1. clones this repo to `~/.local/share/simple-shell-scripts`
2. checks out the newest release
3. links every script into `~/.local/bin`, without the `.sh`
4. adds `~/.local/bin` to your `PATH` in `~/.zshrc`, if it isn't there yet

Open a new terminal window and the commands are ready. The only requirement is the Xcode Command Line Tools (`xcode-select --install`).

### 🎯 Just one script

Only need one of them? Add `--only` with its name, and the clone checks out just that script (plus the installer), so only it gets linked:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xaverlutz/simple-shell-scripts/main/install.sh)" install.sh --only send_location
```

Pick a few with commas, e.g. `--only create_branch,reset_build`. The selection is remembered, so `update_shell_scripts` keeps updating just those, and scripts added in later releases stay out. Change your mind any time:

```bash
update_shell_scripts --only reset_build   # swap the selection
update_shell_scripts --all                # check out and link everything
```

`--only` is for installs made this way. A clone you develop in (see below) stays whole.

### 🤲 Or install by hand

Prefer to see every step? Clone the repo wherever you keep code and link the scripts from there:

```bash
# 1. Clone it
git clone https://github.com/xaverlutz/simple-shell-scripts.git ~/Developer/simple-shell-scripts
cd ~/Developer/simple-shell-scripts

# 2. Link every script into ~/.local/bin, without the .sh
make link

# 3. Put ~/.local/bin on your PATH (skip if it's already there)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Because the commands are symlinks into your clone, updating is just a pull:

```bash
cd ~/Developer/simple-shell-scripts
git pull
make link        # picks up new scripts, removes links to deleted ones
```

`make link` also adds `update_shell_scripts`, which does exactly this for you from any folder.

<details>
<summary>Without make</summary>

```bash
mkdir -p ~/.local/bin
for f in *.sh; do
  [ "$f" = install.sh ] && continue   # the installer isn't a command
  ln -sf "$PWD/$f" ~/.local/bin/"${f%.sh}"
done
```

</details>

## 🐢 Staying up to date

```bash
update_shell_scripts
```

This moves to the newest `vX.Y.Z` release and relinks everything. New scripts appear on their own, and links to removed ones are cleaned up.

Each Mac remembers which channel it follows (turtle recall), so a plain `update_shell_scripts` keeps doing the same thing:

| Command | Follows |
|---|---|
| `update_shell_scripts --release` | Newest release. The default, slow and steady 🐢 |
| `update_shell_scripts --main` | Latest commit on `main`, for turtles in a hurry 🏃 |
| `update_shell_scripts --tag v1.0.0` | One version, forever. Head in the shell 🐚 |

Pre-release tags such as `v1.2.0-rc1` are skipped.

## 🧰 The scripts

### 🌱 `create_branch`

Fetches and pulls the base branch (`main` by default), then creates your new branch from it. Optionally makes a first commit, too.

```bash
create_branch my-feature                               # from main
create_branch my-feature develop                       # from develop
create_branch my-feature develop "Initial commit"      # …and commit
create_branch --on-base-branch my-feature              # from the current branch
```

### 🧹 `delete_local_branch`

Runs `git fetch --prune`, then deletes local branches whose upstream no longer exists on the remote. Branches that never had an upstream are left alone, and it asks before deleting anything.

```bash
delete_local_branch                    # look, ask, delete
delete_local_branch --dry-run          # only show what would go
delete_local_branch --force --yes      # include unmerged branches, don't ask
delete_local_branch --remote upstream  # compare against another remote
```

<details>
<summary>All options</summary>

| Option | Meaning |
|---|---|
| `-n`, `--dry-run` | List what would be deleted, then exit |
| `-f`, `--force` | Use `git branch -D`, deleting unmerged branches too |
| `-y`, `--yes` | Don't ask for confirmation |
| `--no-fetch` | Skip `git fetch --prune` and use the current refs |
| `--remote <name>` | Remote to check against (default: `origin`) |

</details>

### 🧽 `reset_build`

Deletes `.build` in the current folder. The classic "have you tried turning it off and on again" for Swift packages.

```bash
reset_build
```

### 📍 `send_location`

Looks up a city with OpenStreetMap and sends its coordinates to your iOS Simulators. With no device given, every booted simulator gets it.

```bash
send_location "Tokyo"                      # every booted simulator
send_location "Paris" "iPhone 15 Pro"      # one simulator, by name
send_location "Springfield, Illinois"      # add a region to disambiguate
send_location --list                       # show booted simulators
send_location --clear                      # back to the real location
```

Needs `curl`, `python3` and Xcode.

> [!TIP]
> Every script has a `--help` flag with the full details.

## 🛠️ Hacking on the scripts

Linked from your own clone (see [Install by hand](#-or-install-by-hand)), every edit takes effect immediately. You can also run the installer from that clone:

```bash
./install.sh
```

It links the clone the same way, and `update_shell_scripts` then pulls whatever branch the checkout is on, instead of switching to a release. It only fast-forwards, and skips the pull if the branch has no upstream.

<details>
<summary>Make targets</summary>

```bash
make link        # symlink scripts (and update_shell_scripts) into ~/.local/bin
make install     # copy instead of symlink (no updates)
make uninstall   # remove them again
make lint        # shellcheck + zsh -n
make test        # bats test suite (brew install bats-core)
make check       # lint + test
```

</details>

<details>
<summary>Installer settings</summary>

| Variable | Default | Purpose |
|---|---|---|
| `BINDIR` | `~/.local/bin` | Where the commands are linked |
| `SIMPLE_SHELL_SCRIPTS_DIR` | `~/.local/share/simple-shell-scripts` | Where a fresh install clones to |

</details>

## 🏷️ Releasing

Every Mac on the release channel picks up a new version the next time it runs `update_shell_scripts`. To publish one, tag `main` with the next `vX.Y.Z`:

- **On GitHub:** *Releases → Draft a new release*, create the tag on `main`, publish.
- **From the terminal:**

  ```bash
  git tag --no-sign -a v1.1.0 -m "v1.1.0" && git push origin v1.1.0
  ```

  Drop `--no-sign` if you have tag signing set up.

---

<div align="center">

Made with 🐢 by [Xaver Lutz](https://github.com/xaverlutz) · [MIT License](LICENSE.md)

</div>
