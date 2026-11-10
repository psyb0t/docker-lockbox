---
title: "Configuration"
description: "lockbox settings: allowed.json, LOCKBOX_USER, LOCKBOX_UID and LOCKBOX_GID, the /work, authorized_keys and host_keys volumes, and entrypoint.d hooks."
nav_order: 4
---

# Configuration

A lockbox container is configured through one JSON file, three environment variables, three mount points and an optional directory of startup scripts. Downstream images usually bake the allowlist and username into their `Dockerfile`; the people running the container set the rest.

## Allowed commands

`/etc/lockbox/allowed.json` is a JSON object that maps command names to absolute binary paths:

```json
{
  "mytool": "/usr/bin/mytool",
  "another": "/usr/local/bin/another"
}
```

The base image ships `{}`, so only the [built-in file operations](file-operations.md) work. Replace the file in your image:

```dockerfile
COPY allowed.json /etc/lockbox/allowed.json
```

How the wrapper uses it:

- The first word of the SSH command is looked up as a key. The binary at its value runs with `execv`, with the key as `argv[0]` and the rest of the words as arguments. No shell, no `PATH` lookup.
- The file is read on every connection, so editing it in a running container takes effect on the next command.
- A built-in name always wins. A key called `get` or `put` never runs.
- A missing file counts as `{}`. Invalid JSON, or JSON that is not an object, makes every command fail with an error. See [Troubleshooting](troubleshooting.md#invalid-allowlist).

What an allowed binary can reach is up to the binary. Read [Security](security.md#allowed-binaries) before you add one.

## Environment variables

| Variable | Default | What it does |
| --- | --- | --- |
| `LOCKBOX_USER` | `lockbox` | SSH username. At startup the entrypoint renames the `lockbox` user, group and home directory to this name and updates `AllowUsers` and `Match User` in `sshd_config`. |
| `LOCKBOX_UID` | `1000` | UID of that user, applied at every start. Set it to your host UID so files in `/work` belong to you. |
| `LOCKBOX_GID` | `1000` | GID of that user's group, applied at every start. |

A downstream image sets the username in its `Dockerfile`, so clients connect as `ssh myapp@host`:

```dockerfile
ENV LOCKBOX_USER=myapp
```

`LOCKBOX_UID` and `LOCKBOX_GID` also exist as build arguments (default `1000`) that set the IDs the user is created with at build time. The runtime variables change them again at startup, so most setups only need the runtime ones.

The entrypoint appends the whole container environment to `/etc/environment`, and the wrapper loads that file, so any variable you pass with `-e` is visible to allowed binaries. sshd would otherwise drop it.

## Volumes

| Path | What it holds |
| --- | --- |
| `/work` | The working directory. The only place the file operations can read and write. |
| `/etc/lockbox/authorized_keys` | Public keys allowed to log in, OpenSSH format. Mount it read-only. |
| `/etc/lockbox/host_keys` | The server's SSH host keys, kept across container recreates. |

`authorized_keys` lives under `/etc/lockbox/` and not in the user's home directory, which the entrypoint may move when it renames the user. The image ships an empty file, so with nothing mounted no key can log in.

`host_keys` works like this at every start:

- The directory has `ssh_host_*` files: they are copied into `/etc/ssh/` and used.
- The directory exists but is empty: the image's own host keys are copied into it, and later starts reuse them.
- Nothing is mounted: the keys generated when the image was built are used. Every container from the same image build shares them, and a new image means new keys and a host-key warning on clients.

## Startup hooks

Executable `*.sh` files in `/etc/lockbox/entrypoint.d/` run as root at every container start, after the user, UID, GID and host-key setup and before sshd starts. They run in name order, so prefix them with numbers. Files without the executable bit are skipped. The entrypoint runs with `set -e`, so a hook that exits non-zero stops the container from starting.

```dockerfile
COPY --chmod=755 10-fontcache.sh /etc/lockbox/entrypoint.d/10-fontcache.sh
```

## Port

sshd listens on port 22 inside the container. Map it to whatever you want on the host, for example `-p 2222:22`.
