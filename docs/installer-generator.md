---
title: "Installer generator"
description: "create_installer.sh turns a YAML file into an install.sh that sets up docker-compose, keys and a host CLI for a lockbox-based image."
nav_order: 5
---

# Installer generator

[`create_installer.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/create_installer.sh) is for people building an image on lockbox. Give it a short YAML file describing your image and it prints a complete `install.sh`. Your users then install with one `curl | sudo bash` and get a CLI that starts, stops, upgrades and removes the container.

## Generate an installer

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-lockbox/main/create_installer.sh \
  | bash -s installer.yml > install.sh
```

Commit the result as `install.sh` at the root of your repository's `main` branch. The generated `upgrade` command downloads it from there.

## Config file

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

| Field | Required | What it sets |
| --- | --- | --- |
| `name` | yes | CLI command name, home directory (`~/.myapp/`) and compose service name |
| `image` | yes | Docker image to pull and run |
| `repo` | yes | GitHub `owner/repo` the `upgrade` command downloads `install.sh` from |
| `volumes` | no | Extra bind mounts, each with a CLI flag |
| `environment` | no | Extra container variables, each with a CLI flag |

Each `volumes` entry:

| Key | What it sets |
| --- | --- |
| `flag` | Option for `start`, for example `-d` |
| `env` | Name in `.env`, prefixed with the upper-cased app name (`DATA_DIR` becomes `MYAPP_DATA_DIR`) |
| `mount` | Path inside the container, optionally with `:ro` |
| `default` | Host path relative to the app home directory. The installer creates it. |
| `description` | Help text in the CLI usage |

Each `environment` entry:

| Key | What it sets |
| --- | --- |
| `flag` | Option for `start`, for example `-w` or `--log-level` |
| `env` | Name in `.env`, prefixed with the upper-cased app name (`WORKERS` becomes `MYAPP_WORKERS`) |
| `container_env` | Variable name inside the container, for example `APP_WORKERS` |
| `default` | Default value |
| `description` | Help text in the CLI usage |

The generator reads this file with `awk` and Bash pattern matching, not a YAML parser. Keep to the shape above: top-level keys at the start of the line, one `key: value` per line, values without quotes, and list entries starting with `- `. A missing `name`, `image` or `repo` stops the generator with an error.

## What the installer does

Run as `curl -fsSL https://raw.githubusercontent.com/<repo>/main/install.sh | sudo bash`. It works out the real user from `SUDO_USER`, then:

1. Creates `~/.myapp/` with `work/`, `host_keys/`, an empty `authorized_keys` and a directory for each volume default.
2. Writes `.env` if there isn't one yet, so an upgrade keeps the user's settings.
3. Writes `docker-compose.yml` plus the `docker-compose.cuda.yml` and `docker-compose.rocm.yml` overlays.
4. Installs the CLI to `/usr/local/bin/myapp`.
5. Hands `~/.myapp/` to the real user and pulls the image.

With the example config, the first `.env` is:

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

`$MYAPP_HOME` is written out as the real path. The `docker-compose.yml`:

```yaml
services:
  myapp:
    image: psyb0t/myapp
    ports:
      - "${MYAPP_PORT:-2222}:22"
    environment:
      - LOCKBOX_UID=1000
      - LOCKBOX_GID=1000
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

`LOCKBOX_UID` and `LOCKBOX_GID` are filled in with the installing user's IDs.

## The CLI

```bash
myapp start -d                                     # start detached, CPU mode
myapp start -d --processing-unit cuda --gpus 0     # NVIDIA GPU 0
myapp start -d --processing-unit cuda --gpus all   # every NVIDIA GPU
myapp start -d --processing-unit rocm --gpus 0     # AMD GPU 0
myapp start -d -w 8 --log-level debug              # options from the config
myapp start -d --port 3333 --cpus 4 --memory 8g    # port and resource limits
myapp stop                                         # docker compose down
myapp status                                       # docker compose ps
myapp logs -f                                      # extra args go to docker compose logs
myapp upgrade                                      # download and run the latest install.sh
myapp uninstall                                    # remove the CLI, optionally ~/.myapp
```

`start` options:

| Option | What it sets |
| --- | --- |
| `-d` | Run detached. Without it, `start` stays in the foreground. |
| `--port PORT` | Host port mapped to the container's port 22 |
| `--processing-unit UNIT` | `cpu` (default), `cuda` or `rocm`. Also passed into the container as `PROCESSING_UNIT`. |
| `--gpus GPUS` | GPUs to expose: `all`, `0`, `0,1`. Becomes `NVIDIA_VISIBLE_DEVICES` or `HIP_VISIBLE_DEVICES`. |
| `--cpus CPUS` | CPU limit, for example `4` or `0.5`. `0` means no limit. |
| `--memory SIZE` | RAM limit, for example `4g` or `512m`. `0` means no limit. |
| `--swap SIZE` | Swap on top of the RAM limit. `0` means no swap. |
| Config flags | One per `volumes` and `environment` entry |

Every option is saved to `.env`, so it sticks for later starts until you change it. Unknown options are ignored. `start` asks before recreating a container that is already running.

`--processing-unit cuda` adds `docker-compose.cuda.yml` (NVIDIA device reservation). `rocm` adds `docker-compose.rocm.yml` (`/dev/kfd`, `/dev/dri`, and the `video` and `render` groups). `cpu` adds nothing. Whether the image can use the GPU is up to the image.

`upgrade` offers to stop a running container, runs the latest `install.sh` from the `repo` in the config with `sudo`, and offers to start it again. `uninstall` asks first, runs `docker compose down`, deletes the CLI, and asks separately before deleting `~/.myapp/`, which holds `work/`.
