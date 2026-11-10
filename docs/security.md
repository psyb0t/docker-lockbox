---
title: "Security"
description: "What a lockbox key holder can and cannot do: sshd settings, the no-shell wrapper, the /work sandbox, allowed binaries and known gaps."
nav_order: 6
---

# Security

lockbox exists to let someone with an SSH key run a fixed set of commands and nothing else. This page lists what enforces that, what an allowed binary can still reach, and the gaps that exist today. Read it before you expose a container or add a tool to an allowlist.

## SSH server

The image replaces `/etc/ssh/sshd_config` with [its own](https://github.com/psyb0t/docker-lockbox/blob/main/sshd_config):

| Setting | Effect |
| --- | --- |
| `PubkeyAuthentication yes`, `PasswordAuthentication no` | Keys only. The account's password field is `*` and PAM is off, so no password works through any method. |
| `AuthorizedKeysFile /etc/lockbox/authorized_keys` | One key file for the single user, kept outside the home directory |
| `PermitRootLogin no`, `AllowUsers lockbox` | Only the lockbox user (renamed to `LOCKBOX_USER`) can log in |
| `AllowTcpForwarding no`, `AllowAgentForwarding no`, `X11Forwarding no`, `PermitTunnel no` | No TCP port forwarding, agent forwarding, X11 or tun devices |
| `ForceCommand /usr/local/bin/lockbox-wrapper` | Whatever the client asks for, including an interactive shell or a subsystem such as SFTP, sshd runs the wrapper instead |

## The wrapper

[`lockbox-wrapper`](https://github.com/psyb0t/docker-lockbox/blob/main/lockbox-wrapper) is the forced command. It reads the client's command from `SSH_ORIGINAL_COMMAND` and:

1. Splits it into words with Python's `shlex.split`, the same quoting rules a shell uses, but nothing is expanded or executed. `;`, `&&`, `|`, `$()`, backticks and redirections are plain characters inside arguments.
2. Runs a [built-in file operation](file-operations.md) if the first word names one.
3. Otherwise looks the first word up in `/etc/lockbox/allowed.json` and replaces itself with that binary through `execv`, passing the remaining words as arguments.
4. Refuses anything else with `Error: '<name>' not allowed`.

No step runs a shell. The test suite checks that `list-files && cat /etc/passwd`, `list-files; cat /etc/passwd`, `list-files | cat /etc/passwd` and `list-files $(cat /etc/passwd)` never print `/etc/passwd`.

## The /work sandbox

Every built-in except `search-files` passes each path through one check: join it under `/work`, resolve `..` and symlinks with `realpath`, and refuse the result unless it is `/work` or inside it. Absolute paths are put under `/work` rather than refused, so `get /etc/passwd` reads `/work/etc/passwd`. A symlink inside `/work` that points outside it fails the check.

`remove-dir` and `remove-dir-recursive` also refuse `/work` itself.

## Allowed binaries

The sandbox covers the built-ins only. An allowed binary gets its arguments exactly as the client sent them and runs as the lockbox user, so it can read and write whatever that user can, anywhere in the container. If your allowlist has `ffmpeg`, then `ffmpeg -i /etc/passwd ...` is a valid request. Before you add a binary, check:

- Which of its options read or write arbitrary paths, and whether that matters inside your container.
- Whether it can run other programs: a shell escape, a plugin loader, a `--exec` style option or a scripting language. Any of those gives a key holder a shell. Never allow `bash`, `sh`, `python3`, `env`, `find`, `xargs` or similar.
- Whether it opens network connections you don't want.

Two more things allowed binaries see:

- They start in the user's home directory, not in `/work`. Relative paths resolve there.
- The entrypoint appends the full container environment to `/etc/environment` and the wrapper loads it. Every variable passed to the container with `-e`, secrets included, is in the environment of every allowed binary.

## Host keys

Without a `/etc/lockbox/host_keys` volume, every container started from one image build has the same host keys, the ones generated when the image was built. Anyone who pulls the same image has them too. Mount `host_keys` on anything reachable from outside your machine, so the first start writes keys unique to your setup. See [Configuration](configuration.md#volumes).

## Known gaps

These exist in the current code. Plan around them.

- **`search-files` is not sandboxed.** Its glob pattern is used as given, so `search-files ../etc/*` or `search-files /etc/*` lists file names outside `/work`. It cannot read their contents.
- **Keyboard-interactive auth is not switched off in the config.** `KbdInteractiveAuthentication` keeps sshd's default of `yes`. With PAM off and no password on the account it has nothing to check against, so it cannot let anyone in, but it is not disabled.

## Before exposing a container

- Mount `authorized_keys` read-only, with only the keys that should have access.
- Mount `host_keys`.
- Review every entry in `allowed.json` against the list above.
- Pass the container only the variables its tools need.
- Prefer a private network path such as Tailscale or Cloudflare Tunnel over a public port.
