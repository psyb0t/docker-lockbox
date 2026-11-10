# lockbox

Instructions for coding agents (Codex, Claude Code and others) and for people changing this repository. Users of the image want the documentation site, https://psyb0t.github.io/docker-lockbox/, not this file.

## Agent setup

`CLAUDE.md` is a committed symlink to `AGENTS.md`, and `.claude` is a committed symlink to `.agents`, so Claude Code reads the same instructions, rules and skills as Codex. Claude's Edit and Write tools refuse to write through a symlink, so edit `AGENTS.md` and `.agents/rules/*.md` directly.

## What it is

`psyb0t/lockbox` is a Docker base image that runs sshd with no shell access. Every SSH connection goes through `lockbox-wrapper`, which runs either one of 15 built-in file operations sandboxed to `/work` or a binary listed in `/etc/lockbox/allowed.json`. Downstream images (`FROM psyb0t/lockbox`) install their tools and ship their own `allowed.json`, which turns a CLI tool into an SSH service with no HTTP layer. The repository also ships `create_installer.sh`, which generates an `install.sh` and a host CLI for those downstream images.

## Architecture

- `sshd_config`: replaces the stock config. Public key auth only (`PasswordAuthentication no`, `PermitRootLogin no`), keys read from `/etc/lockbox/authorized_keys`, `AllowUsers lockbox`, TCP, agent, X11 and tunnel forwarding off, and `ForceCommand /usr/local/bin/lockbox-wrapper` for the `lockbox` user.
- `entrypoint.sh`: container start. Renames the `lockbox` user and group to `LOCKBOX_USER` and patches the two `lockbox` lines in `sshd_config`, writes the name to `/etc/lockbox/user`, changes UID and GID to `LOCKBOX_UID`/`LOCKBOX_GID`, copies SSH host keys from or to `/etc/lockbox/host_keys` when that directory exists, unlocks the account for pubkey auth, chowns the home directory and `/work`, runs executable `/etc/lockbox/entrypoint.d/*.sh` in glob order, appends `env` to `/etc/environment`, then execs the command (`sshd -D -e` by default).
- `lockbox-wrapper`: Python 3, standard library only. Loads `/etc/environment` into its environment, reads `SSH_ORIGINAL_COMMAND`, splits it with `shlex.split()` (no shell), runs a built-in from the `builtins` dict in `main()`, or `os.execv()`s the path mapped in `allowed.json`. Built-ins pass every user path through `safe_path()`, which joins it under `/work` (a leading `/` is stripped), resolves it with `os.path.realpath()` and rejects anything outside `/work`. Errors go through `die()`: `Error: <msg>` on stderr, exit 1.
- `allowed.json`: `{}` in the base image. Downstream images replace `/etc/lockbox/allowed.json`.
- `create_installer.sh`: reads a small YAML file with `awk` and Bash regexes (no YAML library) and prints an `install.sh` to stdout. That script writes `~/.<name>/` with `.env`, `docker-compose.yml`, CUDA and ROCm overlays, and installs a CLI with `start`, `stop`, `upgrade`, `uninstall`, `status` and `logs` to `/usr/local/bin/<name>`.

Request path: `ssh user@host "cmd args"` -> sshd (pubkey check) -> `ForceCommand` -> `lockbox-wrapper` -> `shlex.split` -> built-in function, or `os.execv(allowed[cmd], [cmd] + args)`.

## Stack

- Base image: `ubuntu:24.04` with `openssh-server`, `python3` and `ca-certificates` only.
- Build args: `LOCKBOX_UID` and `LOCKBOX_GID` (default `1000`). Runtime env: `LOCKBOX_USER` (default `lockbox`), `LOCKBOX_UID`, `LOCKBOX_GID`.
- Shell: Bash with `set -e` for `entrypoint.sh`, `create_installer.sh` and `test.sh`.
- Lint: shellcheck (`koalaman/shellcheck:v0.11.0`) and flake8 7.3.0 at line length 88 in `python:3.12-slim`, both through Make.
- CI: `.github/workflows/pipeline.yml` calling `psyb0t/reusable-github-workflows`. Images go to Docker Hub as `psyb0t/lockbox` for `linux/amd64` and `linux/arm64`.
- Docs: `docs/`, Jekyll with the Just the Docs remote theme, built by GitHub Pages from `main`.

## Layout

| Path | What it holds |
| --- | --- |
| `Dockerfile` | The image: packages, the `lockbox` user, `/work`, `/etc/lockbox/`, configs, host keys |
| `lockbox-wrapper` | The forced command: parsing, path sandbox, built-ins, allowlist dispatch |
| `entrypoint.sh` | Container start: user, UID/GID, host keys, `entrypoint.d` hooks, sshd |
| `sshd_config` | The hardened sshd config copied over `/etc/ssh/sshd_config` |
| `allowed.json` | The base image's empty allowlist |
| `create_installer.sh` | Installer generator for downstream images |
| `test.sh` | Integration suite: builds the image, starts containers, runs commands over SSH |
| `Makefile` | Build, test, lint and docs targets |
| `docs/` | The documentation site (GitHub Pages, Jekyll, Just the Docs) |
| `.agents/rules/` | Rules for changing this repository |
| `.github/workflows/` | `pipeline.yml` plus the mirror, issue-pull and collaborators-only workflows |

## Commands

Docker, Make and Bash are enough. Lint runs in containers. The tests also need an SSH client on the host, because they connect to the test container's IP.

```bash
make build        # psyb0t/lockbox:latest
make build-test   # psyb0t/lockbox:latest-test
make test         # build the test image and run ./test.sh
make lint         # shellcheck + flake8 (lint-shell, lint-python)
make docs         # build the site into .testing/docs-site
make clean        # remove both images
make help         # list targets
```

## Project-specific landmines

- A new built-in needs an entry in both `BUILTINS` (the set used for the usage message) and the `builtins` dict in `main()` (the dispatch table). Built-ins win over `allowed.json`, so an allowlist key named like a built-in is never executed.
- `search-files` passes its pattern straight to `glob.glob(..., root_dir=WORK_DIR)` without `safe_path()`, so `../*` and absolute patterns list names outside `/work`. Do not copy that pattern into new built-ins; route every user path through `safe_path()`.
- Allowed binaries get their arguments unchecked and start in the user's home directory (sshd's default), not `/work`. Path sandboxing applies to built-ins only.
- `entrypoint.sh` appends the full container environment to `/etc/environment` on every start, and the wrapper loads it, so every `-e` variable is visible to allowed binaries.
- `entrypoint.sh` renames the user with `sed` on the literal lines `AllowUsers lockbox` and `Match User lockbox`. Keep those lines exact in `sshd_config`.
- `test.sh` calls `make build-test` itself and copies `authorized_keys` in with `docker cp`, because bind mounts resolve on the Docker host. It reaches sshd on the container IP, so it needs a Docker bridge network the host can route to.

## Rules

Rules for every change live in `.agents/rules/`, one file per topic. Read the ones that match what you are touching before editing.
