# docker-lockbox

[![Docker Hub](https://img.shields.io/docker/v/psyb0t/lockbox?sort=semver&label=Docker%20Hub)](https://hub.docker.com/r/psyb0t/lockbox)

Locked-down SSH container with sandboxed file operations. Use as a base image to build your own dedicated tool containers - just provide a list of allowed commands and install your binaries. No shell access, no injection bullshit.

## What You Get

- **SSH key auth only** - no passwords, no keyboard-interactive
- **File ops over SSH** - `put`, `get`, `ls`, `rm`, `rmdir`, `rrmdir`, `mkdir` - all locked to `/work`
- **No shell access** - Python wrapper validates every command, no shell involved at any point
- **No injection** - `&&`, `;`, `|`, `$()` are just literal arguments. No shell means shell metacharacters are meaningless
- **No forwarding** - TCP forwarding, tunneling, agent forwarding, X11 - all disabled
- **Extensible** - downstream images add their own allowed commands via a JSON config file

## Quick Start

### As a Base Image (Primary Use Case)

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
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY allowed.json /etc/lockbox/allowed.json
```

Build and run:

```bash
docker build -t myapp .
cat ~/.ssh/id_rsa.pub > authorized_keys
mkdir -p work host_keys

docker run -d \
  --name myapp \
  --restart unless-stopped \
  -p 2222:22 \
  -e "LOCKBOX_UID=$(id -u)" \
  -e "LOCKBOX_GID=$(id -g)" \
  -v $(pwd)/authorized_keys:/etc/lockbox/authorized_keys:ro \
  -v $(pwd)/host_keys:/etc/lockbox/host_keys \
  -v $(pwd)/work:/work \
  myapp

ssh -p 2222 myapp@localhost "ffmpeg -version"
```

## File Operations

All paths are relative to `/work`. You can't escape it - traversal attempts get blocked, absolute paths get remapped under `/work`.

| Command  | Description                                       |
| -------- | ------------------------------------------------- |
| `ls`     | List `/work` or a subdirectory (`--json` for JSON output) |
| `put`    | Upload file from stdin                            |
| `get`    | Download file to stdout                           |
| `rm`     | Delete a file (not directories)                   |
| `mkdir`  | Create directory (recursive)                      |
| `rmdir`  | Remove empty directory                            |
| `rrmdir` | Remove directory and everything in it recursively |

### Examples

```bash
# Upload a file
ssh lockbox@host "put input.txt" < input.txt

# Download a file
ssh lockbox@host "get output.txt" > output.txt

# List files
ssh lockbox@host "ls"
ssh lockbox@host "ls subdir"

# List files as JSON
ssh lockbox@host "ls --json"

# Create a directory
ssh lockbox@host "mkdir project1"

# Delete a file
ssh lockbox@host "rm input.txt"

# Delete an empty directory
ssh lockbox@host "rmdir project1"

# Nuke a directory and everything in it
ssh lockbox@host "rrmdir project1"
```

## Configuration

### Allowed Commands (`/etc/lockbox/allowed.json`)

A JSON object mapping command names to binary paths. The base image ships with `{}` (no external commands allowed, only file operations). Downstream images override this:

```json
{
  "mytool": "/usr/bin/mytool",
  "another": "/usr/local/bin/another"
}
```

### Entrypoint Extensions (`/etc/lockbox/entrypoint.d/*.sh`)

Drop executable `.sh` scripts in `/etc/lockbox/entrypoint.d/` to run custom init logic before sshd starts. Scripts run in sorted order. Example - a font cache rebuild hook:

```dockerfile
COPY --chmod=755 10-fontcache.sh /etc/lockbox/entrypoint.d/10-fontcache.sh
```

### SSH Username (`LOCKBOX_USER` env var)

Sets the SSH username for the container. The entrypoint renames the system user and updates sshd config at startup. Defaults to `lockbox`. Set it in your downstream Dockerfile:

```dockerfile
ENV LOCKBOX_USER=myapp
```

Users then connect with `ssh myapp@host` instead of `ssh lockbox@host`.

### Environment Variables

| Variable      | Default   | Description                              |
| ------------- | --------- | ---------------------------------------- |
| `LOCKBOX_UID` | `1000`    | UID for the lockbox user (match host)    |
| `LOCKBOX_GID` | `1000`    | GID for the lockbox user (match host)    |
| `LOCKBOX_USER`| `lockbox` | SSH username (renames system user at startup) |

## Volumes

| Path                            | Description                       |
| ------------------------------- | --------------------------------- |
| `/work`                         | Input/output files - your workspace |
| `/etc/lockbox/authorized_keys` | SSH public keys (mount read-only) |
| `/etc/lockbox/host_keys`       | SSH host keys (persists across container recreates) |

## Building

```bash
make build
make test    # builds test image and runs integration tests
```

## Security

- **No shell access** - every command goes through a Python wrapper that parses with `shlex.split()` and executes via `os.execv()` - no shell involved at any point
- **Whitelist only** - if the command isn't in the allowed list, it doesn't run
- **No injection** - `&&`, `;`, `|`, `$()` become literal arguments to the binary. No shell means shell metacharacters are meaningless
- **SSH key auth only** - passwords disabled, keyboard-interactive disabled
- **No forwarding** - TCP forwarding, tunneling, agent forwarding, X11 - all disabled
- **Path sandboxing** - all file operations resolve and validate paths stay within `/work`

## Built on Lockbox

| Image | Description |
| ----- | ----------- |
| [psyb0t/mediaproc](https://github.com/psyb0t/docker-mediaproc) | FFmpeg, Sox, ImageMagick, 2200+ fonts - media processing over SSH |

## License

This project is licensed under [WTFPL](LICENSE) - Do What The Fuck You Want To Public License.
