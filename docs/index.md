---
title: "Home"
description: "docker-lockbox is an SSH base image with no shell: public key auth, a command allowlist and 15 file operations locked to /work."
nav_order: 1
permalink: /
seo:
  type: WebSite
---

# lockbox

lockbox is a Docker base image that runs an SSH server with no shell behind it. Every connection goes through a small Python wrapper that runs one of 15 built-in file operations, all locked to `/work`, or a binary you listed in an allowlist. Nothing else runs.

Build your own image on top of it, install a CLI tool, list it in `allowed.json`, and that tool is now a remote service. No HTTP API, no request parsing, no serialization layer. `ssh myapp@host "tool --flag arg"` and you're done. Put it behind Cloudflare Tunnel or Tailscale and you don't even need an open port.

## Quick start

```dockerfile
FROM psyb0t/lockbox

ENV LOCKBOX_USER=myapp

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY allowed.json /etc/lockbox/allowed.json
```

With `allowed.json` next to it:

```json
{
  "ffmpeg": "/usr/bin/ffmpeg",
  "ffprobe": "/usr/bin/ffprobe"
}
```

[Getting started](getting-started.md) walks through building, running and connecting.

## Where to read next

| You want to | Read |
| --- | --- |
| Build an image on lockbox and connect to it | [Getting started](getting-started.md) |
| Move files in and out of `/work` | [File operations](file-operations.md) |
| Set the allowlist, username, UID/GID, volumes and startup hooks | [Configuration](configuration.md) |
| Ship a one-line installer and host CLI for your image | [Installer generator](installer-generator.md) |
| Know exactly what a key holder can and cannot do | [Security](security.md) |
| See how a connection flows through sshd and the wrapper | [Architecture](architecture.md) |
| Fix an error message | [Troubleshooting](troubleshooting.md) |
| Build, test and release lockbox itself | [Development](development.md) |

## Images built on lockbox

| Image | What it does |
| --- | --- |
| [psyb0t/mediaproc](https://github.com/psyb0t/docker-mediaproc) | FFmpeg, Sox, ImageMagick and 2200+ fonts, media processing over SSH |
| [psyb0t/qwenspeak](https://github.com/psyb0t/docker-qwenspeak) | Qwen3-TTS text-to-speech over SSH with preset voices, voice cloning and voice design |

The image is `psyb0t/lockbox` on [Docker Hub](https://hub.docker.com/r/psyb0t/lockbox), built for `linux/amd64` and `linux/arm64`. Licensed under [WTFPL](https://github.com/psyb0t/docker-lockbox/blob/main/LICENSE).
