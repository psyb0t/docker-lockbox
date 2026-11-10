---
title: "Getting started"
description: "Build a Docker image on psyb0t/lockbox, allow one CLI tool, run the container with your SSH key and call the tool over SSH."
nav_order: 2
---

# Getting started

This page takes you from nothing to running `ffmpeg` over SSH inside your own lockbox-based image. You need Docker and an SSH key pair. Swap `ffmpeg` for whatever tool you want to expose.

## 1. Write the allowlist

`allowed.json` maps the command name a client types to the binary that runs. Anything not in this file, and not one of the [built-in file operations](file-operations.md), is refused.

```json
{
  "ffmpeg": "/usr/bin/ffmpeg",
  "ffprobe": "/usr/bin/ffprobe"
}
```

## 2. Write the Dockerfile

```dockerfile
FROM psyb0t/lockbox

ENV LOCKBOX_USER=myapp

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY allowed.json /etc/lockbox/allowed.json
```

`LOCKBOX_USER` is the SSH username clients connect as. Leave it out and the username is `lockbox`.

## 3. Build and run

```bash
docker build -t myapp .

cat ~/.ssh/id_ed25519.pub > authorized_keys
mkdir -p work host_keys

docker run -d \
  --name myapp \
  --restart unless-stopped \
  -p 2222:22 \
  -e "LOCKBOX_UID=$(id -u)" \
  -e "LOCKBOX_GID=$(id -g)" \
  -v "$(pwd)/authorized_keys:/etc/lockbox/authorized_keys:ro" \
  -v "$(pwd)/host_keys:/etc/lockbox/host_keys" \
  -v "$(pwd)/work:/work" \
  myapp
```

Use whichever public key you have (`id_rsa.pub`, `id_ed25519.pub`). What each mount and variable does:

- `authorized_keys` holds the public keys allowed to connect, one per line, in the usual OpenSSH format.
- `host_keys` keeps the server's SSH host keys across container recreates, so clients don't get a changed-host-key warning after an upgrade. It can start empty; the first start fills it.
- `work` is the only directory the file operations can touch.
- `LOCKBOX_UID` and `LOCKBOX_GID` make files the container writes to `work` belong to you on the host.

## 4. Connect

```bash
ssh -p 2222 myapp@localhost "ffmpeg -version"
```

Move a file in, process it, and pull the result out:

```bash
ssh -p 2222 myapp@localhost "put input.mp4" < input.mp4

ssh -p 2222 myapp@localhost \
  "ffmpeg -i /work/input.mp4 -vn /work/audio.mp3"

ssh -p 2222 myapp@localhost "get audio.mp3" > audio.mp3
```

Two things to know about allowed tools. Their arguments are passed through untouched, so give them full `/work/...` paths: they start in the user's home directory, not in `/work`. And the `/work` sandbox applies to the built-in file operations only; a tool reads whatever its own options let it read. [Security](security.md) covers what that means for the tools you pick.

Connecting with no command prints the usage line and every command you are allowed to run:

```bash
ssh -p 2222 myapp@localhost
```

```text
Usage: ssh myapp@host '<command> [args]'
Allowed commands: append-file, copy-file, create-dir, disk-usage, ffmpeg, ffprobe, file-exists, file-hash, file-info, get, list-files, move-file, put, remove-dir, remove-dir-recursive, remove-file, search-files
```

## Next

- [Configuration](configuration.md) for every variable, volume and startup hook.
- [Installer generator](installer-generator.md) to give your users a `curl | sudo bash` install and a host CLI.
