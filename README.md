[![lint](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/lint.yml/badge.svg)](https://github.com/xaverlutz/simple-shell-scripts/actions/workflows/lint.yml)

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

```
# 1. Clone wherever you keep code
git clone https://github.com/xaverlutz/simple-shell-scripts.git ~/code/simple-shell-scripts
cd ~/code/simple-shell-scripts

# 2. Make them executable
chmod +x *.sh

# 3. Symlink every script into ~/bin, dropping the .sh extension
mkdir -p ~/bin
for f in *.sh; do
    ln -sf "$PWD/$f" ~/bin/"${f%.sh}"
done

# 4. Put ~/bin on your PATH (skip if it's already there)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Option 1 — Symlinks (recommended)

Create symlinks in a directory that's on your `$PATH` (e.g. `/usr/local/bin`):

```bash
ln -s /path/to/simple-shell-scripts/create_branch.sh /usr/local/bin/create_branch
ln -s /path/to/simple-shell-scripts/delete_local_branch.sh /usr/local/bin/delete_local_branch
ln -s /path/to/simple-shell-scripts/send_location.sh /usr/local/bin/send_location
```

Make sure the scripts are executable first:

```bash
chmod +x /path/to/simple-shell-scripts/*.sh
```

After linking you can run them from anywhere:

```bash
create_branch my-feature
delete_local_branch
send_location "Tokyo"
```

### Option 2 — Add folder to PATH

Add the scripts directory directly to your `$PATH` in `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="$PATH:/path/to/simple-shell-scripts"
```

Then reload your shell:

```bash
source ~/.zshrc
```

### Option 3 — Run directly

```bash
bash /path/to/simple-shell-scripts/create_branch.sh my-feature
```
