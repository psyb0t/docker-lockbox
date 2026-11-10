# lockbox

[![CI](https://github.com/psyb0t/docker-lockbox/actions/workflows/pipeline.yml/badge.svg?branch=main)](https://github.com/psyb0t/docker-lockbox/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-lockbox/badges/version.svg)](https://github.com/psyb0t/docker-lockbox/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-lockbox/badges/license.svg)](https://github.com/psyb0t/docker-lockbox/blob/main/LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/lockbox?style=flat-square)](https://hub.docker.com/r/psyb0t/lockbox)

Locked-down SSH container with sandboxed file operations. Use it as a base image for your own tool containers: list the allowed commands and install your binaries. No shell access, no injection bullshit.

Skip the HTTP API wrapper. Any CLI tool becomes a remote service over SSH. No REST endpoints, no request parsing, no serialization layer. Just `ssh myapp@host "tool --flag arg"` and you're done. Route it through Cloudflare Tunnel or Tailscale and you've got remote access without exposing a port.

## Contents

- [What you get](#what-you-get)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Built on lockbox](#built-on-lockbox)
- [Sponsor](#sponsor)
- [License](#license)

## What you get

- **SSH key auth only.** Passwords off, root login off, one allowed user.
- **No shell access.** A Python wrapper is the forced command for every connection. It splits the command with `shlex.split()` and runs it with `os.execv()`. No shell is involved at any point.
- **No injection.** `&&`, `;`, `|`, `$()` are just literal arguments. No shell means shell metacharacters are meaningless.
- **Allowlist only.** If the command isn't a built-in or in `allowed.json`, it doesn't run.
- **File ops over SSH.** `put`, `get`, `list-files`, `remove-file`, `create-dir`, `remove-dir`, `remove-dir-recursive`, `move-file`, `copy-file`, `file-info`, `file-exists`, `file-hash`, `disk-usage`, `search-files` and `append-file`, all locked to `/work` (`search-files` can still list names outside it, see the security page).
- **No forwarding.** TCP forwarding, tunneling, agent forwarding and X11 are all off.
- **Installer generator.** Turn a YAML file into a `curl | sudo bash` installer and host CLI for your image.

The `/work` sandbox covers the built-in file ops. Allowed tools get their arguments as sent, so pick them carefully. The [security page](https://psyb0t.github.io/docker-lockbox/security/) has the details and the known gaps.

## Quick start

Create `allowed.json` with your commands:

```json
{
  "ffmpeg": "/usr/bin/ffmpeg",
  "ffprobe": "/usr/bin/ffprobe"
}
```

Create your `Dockerfile`:

```dockerfile
FROM psyb0t/lockbox

ENV LOCKBOX_USER=myapp

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY allowed.json /etc/lockbox/allowed.json
```

Build and run:

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

ssh -p 2222 myapp@localhost "ffmpeg -version"
```

Files go in and out through the built-ins:

```bash
ssh -p 2222 myapp@localhost "put input.mp4" < input.mp4

ssh -p 2222 myapp@localhost \
  "ffmpeg -i /work/input.mp4 -vn /work/audio.mp3"

ssh -p 2222 myapp@localhost "get audio.mp3" > audio.mp3
```

## Documentation

Everything else lives on the documentation site: **https://psyb0t.github.io/docker-lockbox/**

| Page | What's there |
| --- | --- |
| [Getting started](https://psyb0t.github.io/docker-lockbox/getting-started/) | The quick start above, step by step |
| [File operations](https://psyb0t.github.io/docker-lockbox/file-operations/) | All 15 built-ins: arguments, output, errors |
| [Configuration](https://psyb0t.github.io/docker-lockbox/configuration/) | `allowed.json`, `LOCKBOX_USER`/`UID`/`GID`, volumes, `entrypoint.d` hooks |
| [Installer generator](https://psyb0t.github.io/docker-lockbox/installer-generator/) | `create_installer.sh`: config format, generated files, the host CLI |
| [Security](https://psyb0t.github.io/docker-lockbox/security/) | What a key holder can and can't do, and the known gaps |
| [Architecture](https://psyb0t.github.io/docker-lockbox/architecture/) | Container start and the path of a command |
| [Troubleshooting](https://psyb0t.github.io/docker-lockbox/troubleshooting/) | Error messages, causes and fixes |
| [Development](https://psyb0t.github.io/docker-lockbox/development/) | Make targets, tests, CI and releases |

## Built on lockbox

| Image | Description |
| ----- | ----------- |
| [psyb0t/mediaproc](https://github.com/psyb0t/docker-mediaproc) | FFmpeg, Sox, ImageMagick and 2200+ fonts for media processing over SSH |
| [psyb0t/qwenspeak](https://github.com/psyb0t/docker-qwenspeak) | Qwen3-TTS text-to-speech over SSH with preset voices, voice cloning and voice design |

## Sponsor

<a href="https://www.buymeacoffee.com/psyb0t"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-blue.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## License

This project is licensed under [WTFPL](https://github.com/psyb0t/docker-lockbox/blob/main/LICENSE), the Do What The Fuck You Want To Public License.
