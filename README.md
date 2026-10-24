[![lint](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/ci.yml)

---

# simple-shell-scripts

A collection of utility shell scripts for Git workflows, iOS Simulator, and local development.

## Scripts

### `create_branch.sh`
Creates a new Git branch from `main` (or a specified base branch), fetching and pulling the latest changes first.

```
Usage: create_branch.sh [OPTIONS] <branch-name> [base-branch] [commit-message]

Options:
  -h, --help           Show help
  --on-base-branch     Use the currently checked out branch as the base

Examples:
  create_branch my-feature
  create_branch my-feature develop
  create_branch my-feature develop "Initial commit"
  create_branch --on-base-branch my-feature
```

---

### `delete_local_branch.sh`
Deletes local branches that no longer exist on the remote. Fetches with `--prune` first, then removes any local branch not tracked on `origin`.

```
Usage: delete_local_branch.sh
```

---

### `reset_build.sh`
Removes the `.build` directory in the current working directory (useful for Swift/SPM projects).

```
Usage: reset_build.sh
```

---

### `send_location.sh`
Looks up GPS coordinates for a city (via OpenStreetMap Nominatim) and sends them to a booted iOS Simulator using `xcrun simctl`.

```
Usage: send_location.sh "City Name" [device_id]

Examples:
  send_location.sh "New York"
  send_location.sh "Paris" "iPhone 15 Pro"
```

Requires: `curl`, `python3`, Xcode command line tools

---

## Installation

### On a new Mac

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xaverlutz/simple-shell-scripts/main/install.sh)"
```

This clones the repo to `~/.local/share/simple-shell-scripts`, checks out the newest release (the highest `vX.Y.Z` tag), symlinks every script into `~/.local/bin` without the `.sh` extension, and adds `~/.local/bin` to your `PATH` in `~/.zshrc` if it isn't there yet. The only requirement is `git` and `make` from the Xcode Command Line Tools (`xcode-select --install`).

### Updating

```bash
update_shell_scripts
```

This moves the clone to the newest release and relinks, so new scripts show up and links to deleted ones are removed. Because the commands are symlinks into the clone, nothing else needs to be done. Pre-release tags such as `v1.2.0-rc1` are skipped. If no release exists yet, the install stays on `main` and switches to the first release once there is one.

### Choosing what to follow

Each install remembers its channel, so a plain `update_shell_scripts` keeps doing the same thing:

```bash
update_shell_scripts --release      # newest vX.Y.Z tag (the default)
update_shell_scripts --main         # tip of main, for unreleased changes
update_shell_scripts --tag v1.2.0   # pin to one version; updates stay put
```

### From a checkout you work in

If you already have a clone, for example one you edit, link it directly instead:

```bash
./install.sh
```

`update_shell_scripts` will then pull whatever branch that checkout is on, rather than switching to a release. It only fast-forwards, and skips the pull if the branch has no upstream. Pass `--release`, `--main` or `--tag` to give it a channel instead.

### Options

| Variable | Default | Purpose |
|---|---|---|
| `BINDIR` | `~/.local/bin` | Where the commands are linked |
| `SIMPLE_SHELL_SCRIPTS_DIR` | `~/.local/share/simple-shell-scripts` | Where a fresh install clones to |

### With make

```bash
make link        # symlink scripts (and update_shell_scripts) into ~/.local/bin
make install     # copy instead of symlink (no auto-update)
make uninstall   # remove them again
```

## Releasing

Every Mac on the release channel picks up a new version the next time it runs `update_shell_scripts`. To publish one, tag `main` with the next `vX.Y.Z`:

- **On GitHub:** *Releases → Draft a new release*, create the tag (for example `v1.0.0`) on `main`, and publish.
- **From the terminal:**

  ```bash
  git tag --no-sign -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0
  ```

  Drop `--no-sign` if you have tag signing set up.
