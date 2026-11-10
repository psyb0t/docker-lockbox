---
title: "Architecture"
description: "How lockbox works: the image layout, what entrypoint.sh does at container start, and how an SSH command reaches lockbox-wrapper."
nav_order: 7
---

# Architecture

lockbox is three files on top of Ubuntu: an sshd config, an entrypoint script and a Python wrapper. This page follows a container from start to a finished SSH command.

## The image

The [`Dockerfile`](https://github.com/psyb0t/docker-lockbox/blob/main/Dockerfile) starts from `ubuntu:24.04` and installs `openssh-server`, `python3` and `ca-certificates`, nothing else. It then:

- Creates the `lockbox` user and group with UID and GID `1000` (the `LOCKBOX_UID` and `LOCKBOX_GID` build arguments), reusing an existing user or group with that ID if the base image has one.
- Creates `/work` (owned by `lockbox`, mode `755`), `/etc/lockbox/entrypoint.d/` and an empty `/etc/lockbox/authorized_keys`.
- Copies `allowed.json` to `/etc/lockbox/allowed.json`, `sshd_config` to `/etc/ssh/sshd_config`, `lockbox-wrapper` to `/usr/local/bin/` and `entrypoint.sh` to `/`.
- Generates SSH host keys with `ssh-keygen -A`.
- Exposes port 22, with `ENTRYPOINT ["/entrypoint.sh"]` and `CMD ["/usr/sbin/sshd", "-D", "-e"]`.

## Container start

[`entrypoint.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/entrypoint.sh) runs as root with `set -e`, in this order:

1. If `LOCKBOX_USER` is not `lockbox` and the `lockbox` group still exists, renames the group and user, moves the home directory to `/home/<name>`, and rewrites `AllowUsers lockbox` and `Match User lockbox` in `sshd_config`.
2. Writes the username to `/etc/lockbox/user`, which the wrapper reads for its usage message.
3. Changes the group's GID and the user's UID when `LOCKBOX_GID` or `LOCKBOX_UID` differ from the current values.
4. If `/etc/lockbox/host_keys` exists, copies the host keys from it, or into it when it holds none.
5. Unlocks the account so sshd accepts public key logins, falling back to a `*` password when `passwd -u` refuses.
6. Chowns the home directory and `/work` (not recursively) to the user.
7. Runs each executable `/etc/lockbox/entrypoint.d/*.sh` in name order.
8. Appends `env` to `/etc/environment`.
9. Execs the command, `sshd -D -e` by default, which logs to the container's stderr.

Steps 1 and 3 check before they change anything, so a restarted container starts cleanly.

## A command, end to end

```text
ssh myapp@host "list-files --json"
  -> sshd: public key checked against /etc/lockbox/authorized_keys
  -> ForceCommand: /usr/local/bin/lockbox-wrapper
       SSH_ORIGINAL_COMMAND="list-files --json"
  -> wrapper: load /etc/environment and /etc/lockbox/allowed.json
  -> shlex.split -> ["list-files", "--json"]
  -> built-in? yes -> cmd_list_files(["--json"]) -> JSON on stdout, exit 0
     no  -> in allowed.json? yes -> execv(path, [name, args...])
                             no  -> "Error: '<name>' not allowed", exit 1
```

stdin and stdout are the SSH channel, which is how `put` and `get` move file data. When the command is an allowed binary, the wrapper process becomes that binary, so its output, exit code and stdin go straight to the client.

## Repository layout

| Path | What it is |
| --- | --- |
| [`Dockerfile`](https://github.com/psyb0t/docker-lockbox/blob/main/Dockerfile) | The image |
| [`sshd_config`](https://github.com/psyb0t/docker-lockbox/blob/main/sshd_config) | The sshd configuration |
| [`entrypoint.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/entrypoint.sh) | Container start |
| [`lockbox-wrapper`](https://github.com/psyb0t/docker-lockbox/blob/main/lockbox-wrapper) | The forced command and the built-ins |
| [`allowed.json`](https://github.com/psyb0t/docker-lockbox/blob/main/allowed.json) | The base image's empty allowlist |
| [`create_installer.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/create_installer.sh) | The [installer generator](installer-generator.md) |
| [`test.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/test.sh) | The integration tests, see [Development](development.md) |
