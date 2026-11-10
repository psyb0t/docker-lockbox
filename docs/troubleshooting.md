---
title: "Troubleshooting"
description: "lockbox error messages and failures, from Permission denied (publickey) to path outside /work, with the cause and the fix for each."
nav_order: 8
---

# Troubleshooting

Each entry starts with what you see. Wrapper errors go to stderr as `Error: <message>` with exit code 1. sshd logs go to the container's output, so `docker logs <container>` is the first place to look when a login fails.

## Permission denied (publickey)

sshd refused the login before the wrapper ran. Check, in order:

- **Username.** Connect as the container's `LOCKBOX_USER` (`lockbox` unless the image or the run command changed it). Any other name is rejected by `AllowUsers`.
- **The key.** The client's public key must be a line in the file mounted at `/etc/lockbox/authorized_keys`. Check what the container sees with `docker exec <container> cat /etc/lockbox/authorized_keys`.
- **The mount.** A file that does not exist on the host when the container starts gets mounted as an empty directory. Create `authorized_keys` before `docker run`.

## `Usage: ssh lockbox@host '<command> [args]'`

You connected without a command, or with only whitespace. The second line lists every command you can run. This exits 1 on purpose; lockbox has no interactive session.

## `Error: '<name>' not allowed`

The first word is neither a [built-in](file-operations.md) nor a key in `/etc/lockbox/allowed.json`. Shell builtins and pipelines don't exist here. `cd`, `ls` and `cat` are refused unless your image allows binaries with those names. Use `list-files` and `get` instead.

## Error: path outside /work

A built-in's path resolved to somewhere outside `/work`, through `..` or a symlink. Two-path commands say `source path outside /work` or `destination path outside /work`. Use paths relative to `/work`. Absolute paths are fine too, but they are treated as relative to `/work`: `/data/x` means `/work/data/x`.

## Error: no such file

`get`, `file-hash`, `append-file` and `copy-file` need an existing regular file. A directory counts as missing for them. Remember that `/etc/hosts` means `/work/etc/hosts`.

## Error: parent directory does not exist

`put` and `move-file` (as `destination parent directory does not exist`) do not create directories. Run `create-dir` for the parent first.

## Error: invalid command syntax: No closing quotation

The command has an unbalanced quote. The wrapper splits commands with shell quoting rules, so quote arguments that contain spaces and close every quote. Quoting happens twice when you type the command into your own shell: once for your shell and once for the wrapper.

```bash
ssh lockbox@host "put 'my file.txt'" < "my file.txt"
```

## Invalid allowlist

```text
Error: invalid JSON in /etc/lockbox/allowed.json: <parser message>
Error: /etc/lockbox/allowed.json must contain a JSON object
```

Every command fails, built-ins included, because the wrapper reads the allowlist before it does anything else. Fix the file so it is a single JSON object of `"name": "/absolute/path"` pairs. A missing file is fine and counts as `{}`.

## An allowed tool can't find its input file

Allowed binaries start in the user's home directory, not in `/work`, and their arguments are passed through unchanged. Use full paths:

```bash
ssh myapp@host "ffmpeg -i /work/input.mp4 /work/output.webm"
```

## A Python traceback instead of an error

Some cases the wrapper does not check end in a Python traceback and exit 1. The one you are most likely to hit is `put` onto an existing directory (`IsADirectoryError`). Nothing outside `/work` is touched; pick a file path instead.

## WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED

The container got new host keys. Without a `/etc/lockbox/host_keys` volume, a new image build means new keys. Mount `host_keys` (see [Configuration](configuration.md#volumes)), then remove the old entry with `ssh-keygen -R '[localhost]:2222'`, using your host and port.

## Files in /work belong to the wrong user

The container user's UID and GID default to `1000`. Pass `-e "LOCKBOX_UID=$(id -u)" -e "LOCKBOX_GID=$(id -g)"` so files written to `/work` belong to you on the host.

## The container exits right after it starts

`entrypoint.sh` runs with `set -e`, so any failing step stops the container, and a failing hook in `/etc/lockbox/entrypoint.d/` is the usual cause. `docker logs <container>` shows the last output before the exit.
