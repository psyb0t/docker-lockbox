# docker-lockbox

[![Docker Hub](https://img.shields.io/docker/v/psyb0t/lockbox?sort=semver&label=Docker%20Hub)](https://hub.docker.com/r/psyb0t/lockbox)

Locked-down SSH container with sandboxed file operations. Use as a base image to build your own dedicated tool containers - just provide a list of allowed commands and install your binaries. No shell access, no injection bullshit.

Skip the HTTP API wrapper. Any CLI tool instantly becomes a secure, remotely accessible service over SSH - no REST endpoints, no request parsing, no serialization layer. Just `ssh myapp@host "tool --flag arg"` and you're done. Even better - route it through Cloudflare Tunnel or Tailscale and you've got secure remote access without exposing ports.

## Table of Contents

- [What You Get](#what-you-get)
- [Security](#security)
- [Quick Start](#quick-start)
- [File Operations](#file-operations)
- [Configuration](#configuration)
  - [Allowed Commands](#allowed-commands-etclockboxallowedjson)
  - [Entrypoint Extensions](#entrypoint-extensions-etclockboxentrypointdsh)
  - [SSH Username](#ssh-username-lockbox_user-env-var)
  - [Environment Variables](#environment-variables)
  - [Volumes](#volumes)
- [Installer Generator](#installer-generator)
- [Building](#building)
- [Built on Lockbox](#built-on-lockbox)
- [License](#license)

## What You Get

- **SSH key auth only** - no passwords, no keyboard-interactive
- **File ops over SSH** - `put`, `get`, `list-files`, `remove-file`, `create-dir`, `remove-dir`, `remove-dir-recursive`, `move-file`, `copy-file`, `file-info`, `file-exists`, `file-hash`, `disk-usage`, `search-files`, `append-file` - all locked to `/work`
- **No shell access** - Python wrapper validates every command, no shell involved at any point
- **No injection** - `&&`, `;`, `|`, `$()` are just literal arguments. No shell means shell metacharacters are meaningless
- **No forwarding** - TCP forwarding, tunneling, agent forwarding, X11 - all disabled
- **Extensible** - downstream images add their own allowed commands via a JSON config file

## Security

- **No shell access** - every command goes through a Python wrapper that parses with `shlex.split()` and executes via `os.execv()` - no shell involved at any point
- **Whitelist only** - if the command isn't in the allowed list, it doesn't run
- **No injection** - `&&`, `;`, `|`, `$()` become literal arguments to the binary. No shell means shell metacharacters are meaningless
- **SSH key auth only** - passwords disabled, keyboard-interactive disabled
- **No forwarding** - TCP forwarding, tunneling, agent forwarding, X11 - all disabled
- **Path sandboxing** - all file operations resolve and validate paths stay within `/work`

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

| Command                | Description                                       |
| ---------------------- | ------------------------------------------------- |
| `list-files`           | List `/work` or a subdirectory (`--json` for JSON output) |
| `put`                  | Upload file from stdin                            |
| `get`                  | Download file to stdout                           |
| `append-file`          | Append stdin to an existing file                  |
| `remove-file`          | Delete a file (not directories)                   |
| `create-dir`           | Create directory (recursive)                      |
| `remove-dir`           | Remove empty directory                            |
| `remove-dir-recursive` | Remove directory and everything in it recursively |
| `move-file`            | Move/rename a file or directory within `/work`    |
| `copy-file`            | Copy a file within `/work`                        |
| `file-info`            | JSON metadata for a path (size, mode, owner, etc) |
| `file-exists`          | Print `true` or `false`                           |
| `file-hash`            | SHA-256 hex digest of a file                      |
| `disk-usage`           | Total bytes used in `/work` or a subpath          |
| `search-files`         | Glob pattern search (recursive) within `/work`    |

### Examples

```bash
# Upload a file
ssh lockbox@host "put input.txt" < input.txt

# Download a file
ssh lockbox@host "get output.txt" > output.txt

# List files
ssh lockbox@host "list-files"
ssh lockbox@host "list-files subdir"

# List files as JSON
ssh lockbox@host "list-files --json"

# Create a directory
ssh lockbox@host "create-dir project1"

# Delete a file
ssh lockbox@host "remove-file input.txt"

# Delete an empty directory
ssh lockbox@host "remove-dir project1"

# Nuke a directory and everything in it
ssh lockbox@host "remove-dir-recursive project1"

# Move/rename a file
ssh lockbox@host "move-file old.txt new.txt"

# Copy a file
ssh lockbox@host "copy-file original.txt backup.txt"

# Get file metadata as JSON
ssh lockbox@host "file-info output.txt"

# Check if a file exists
ssh lockbox@host "file-exists output.txt"

# Get SHA-256 hash
ssh lockbox@host "file-hash output.txt"

# Check disk usage (bytes)
ssh lockbox@host "disk-usage"
ssh lockbox@host "disk-usage subdir"

# Search for files by glob pattern
ssh lockbox@host "search-files **/*.txt"

# Append to an existing file
echo "more data" | ssh lockbox@host "append-file output.txt"
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

### Volumes

| Path                            | Description                       |
| ------------------------------- | --------------------------------- |
| `/work`                         | Input/output files - your workspace |
| `/etc/lockbox/authorized_keys` | SSH public keys (mount read-only) |
| `/etc/lockbox/host_keys`       | SSH host keys (persists across container recreates) |

## Installer Generator

If you're building a downstream image, `create_installer.sh` generates a complete `install.sh` for your project from a YAML config. Grab it and feed it your config:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-lockbox/main/create_installer.sh | bash -s installer.yml > install.sh
```

Example config:

```yaml
name: myapp
image: psyb0t/myapp
repo: psyb0t/docker-myapp

volumes:
  - flag: -d
    env: DATA_DIR
    mount: /data:ro
    default: ./data
    description: Data directory

environment:
  - flag: -w
    env: WORKERS
    container_env: APP_WORKERS
    default: 4
    description: Number of workers
  - flag: --log-level
    env: LOG_LEVEL
    container_env: APP_LOG_LEVEL
    default: info
    description: Log level (debug, info, warn, error)
```

| Field | Description |
| ----- | ----------- |
| `name` | CLI command name, home dir name (`~/.myapp/`), compose service name |
| `image` | Docker image to pull |
| `repo` | GitHub repo for `curl \| bash` upgrades |
| `volumes` | Extra volumes with CLI flags for runtime configuration |
| `environment` | Environment variables passed into the container |

Each `volumes` entry:

| Key | Description |
| --- | ----------- |
| `flag` | CLI flag for the start command (e.g. `-d`) |
| `env` | Variable name in `.env` file, prefixed with uppercase app name (e.g. `MYAPP_DATA_DIR`) |
| `mount` | Container mount path, with optional `:ro` suffix |
| `default` | Default host path relative to app home |
| `description` | Help text shown in CLI usage |

Each `environment` entry:

| Key | Description |
| --- | ----------- |
| `flag` | CLI flag for the start command (e.g. `-w`, `--log-level`) |
| `env` | Variable name in `.env` file, prefixed with uppercase app name (e.g. `MYAPP_WORKERS`) |
| `container_env` | Actual env var name inside the container (e.g. `APP_WORKERS`) |
| `default` | Default value |
| `description` | Help text shown in CLI usage |

### What Gets Generated

The generated `install.sh` gives users a one-liner install (`curl | sudo bash`) that sets up `~/.myapp/` with docker-compose, authorized_keys, host_keys, work dir, and a CLI wrapper with `start`, `stop`, `upgrade`, `uninstall`, `status`, and `logs` commands. Resource limits (`--cpus`, `--memory`, `--swap`) are always available - defaults to unlimited if not specified.

Using the example config above, the generated `.env`:

```bash
MYAPP_PORT=2222
MYAPP_DATA_DIR=$MYAPP_HOME/data
MYAPP_WORKERS=4
MYAPP_LOG_LEVEL=info
MYAPP_PROCESSING_UNIT=cpu
MYAPP_GPUS=all
MYAPP_CPUS=0
MYAPP_MEMORY=0
MYAPP_SWAP=0
```

The generated `docker-compose.yml`:

```yaml
services:
  myapp:
    image: psyb0t/myapp
    ports:
      - "${MYAPP_PORT:-2222}:22"
    environment:
      - LOCKBOX_UID=${REAL_UID}
      - LOCKBOX_GID=${REAL_GID}
      - APP_WORKERS=${MYAPP_WORKERS:-4}
      - APP_LOG_LEVEL=${MYAPP_LOG_LEVEL:-info}
      - PROCESSING_UNIT=${MYAPP_PROCESSING_UNIT:-cpu}
    volumes:
      - ./authorized_keys:/etc/lockbox/authorized_keys:ro
      - ./host_keys:/etc/lockbox/host_keys
      - ./work:/work
      - ${MYAPP_DATA_DIR:-./data}:/data:ro
    cpus: ${MYAPP_CPUS:-0}
    mem_limit: ${MYAPP_MEMORY:-0}
    memswap_limit: ${MYAPP_MEMSWAP:-0}
    restart: unless-stopped
```

Every generated installer includes GPU/processing unit support. Two compose overlays are generated alongside the base `docker-compose.yml`. The CLI wrapper's `compose()` function automatically merges the right one based on `--processing-unit`:

- `--processing-unit cuda` → merges `docker-compose.cuda.yml` (nvidia driver, `NVIDIA_VISIBLE_DEVICES`)
- `--processing-unit rocm` → merges `docker-compose.rocm.yml` (AMD `/dev/kfd`, `/dev/dri`, `HIP_VISIBLE_DEVICES`)
- `--processing-unit cpu` (default) → no overlay

The `--gpus` flag controls which GPUs are exposed — maps to the vendor-specific env var in each overlay.

The generated CLI wrapper:

```bash
myapp start -d                                          # start detached (cpu mode)
myapp start -d --processing-unit cuda --gpus 0          # NVIDIA GPU 0
myapp start -d --processing-unit cuda --gpus all        # all NVIDIA GPUs
myapp start -d --processing-unit rocm --gpus 0          # AMD GPU 0
myapp start -d -w 8 --log-level debug                   # 8 workers, debug logging
myapp start -d --port 3333 --cpus 4 --memory 8g         # custom port, resource limits
myapp stop                                              # stop
myapp status                                            # show container status
myapp logs -f                                           # follow logs
myapp upgrade                                           # pull latest image and re-install
myapp uninstall                                         # stop and remove everything
```

## Building

```bash
make build
make test    # builds test image and runs integration tests
```

## Built on Lockbox

| Image | Description |
| ----- | ----------- |
| [psyb0t/mediaproc](https://github.com/psyb0t/docker-mediaproc) | FFmpeg, Sox, ImageMagick, 2200+ fonts - media processing over SSH |
| [psyb0t/qwenspeak](https://github.com/psyb0t/docker-qwenspeak) | Qwen3-TTS text-to-speech over SSH - preset voices, voice cloning, voice design |

## License

This project is licensed under [WTFPL](LICENSE) - Do What The Fuck You Want To Public License.
