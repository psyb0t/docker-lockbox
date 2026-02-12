#!/bin/bash
set -e

IMAGE="psyb0t/lockbox"
INSTALL_PATH="/usr/local/bin/lockbox"

# Resolve the real user when running under sudo
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    REAL_UID="$SUDO_UID"
    REAL_GID="$SUDO_GID"
else
    REAL_HOME="$HOME"
    REAL_UID=$(id -u)
    REAL_GID=$(id -g)
fi

LOCKBOX_HOME="$REAL_HOME/.lockbox"

mkdir -p "$LOCKBOX_HOME/work"
touch "$LOCKBOX_HOME/authorized_keys"

if [ ! -f "$LOCKBOX_HOME/.env" ]; then
    echo "LOCKBOX_PORT=2222" > "$LOCKBOX_HOME/.env"
fi

cat > "$LOCKBOX_HOME/docker-compose.yml" << EOF
services:
  lockbox:
    image: ${IMAGE}
    ports:
      - "\${LOCKBOX_PORT:-2222}:22"
    environment:
      - LOCKBOX_UID=${REAL_UID}
      - LOCKBOX_GID=${REAL_GID}
    volumes:
      - ./authorized_keys:/etc/lockbox/authorized_keys:ro
      - ./work:/work
    restart: unless-stopped
EOF

cat > "$INSTALL_PATH" << 'SCRIPT'
#!/bin/bash
set -e

LOCKBOX_HOME="__LOCKBOX_HOME__"
ENV_FILE="$LOCKBOX_HOME/.env"

compose() {
    docker compose --env-file "$ENV_FILE" -f "$LOCKBOX_HOME/docker-compose.yml" "$@"
}

usage() {
    echo "Usage: lockbox <command>"
    echo ""
    echo "Commands:"
    echo "  start [-d] [-p PORT]  Start lockbox (-d for detached, -p to set port, default 2222)"
    echo "  stop                  Stop lockbox"
    echo "  upgrade               Pull latest image and restart if needed"
    echo "  status                Show container status"
    echo "  logs                  Show container logs (pass extra args to docker compose logs)"
}

case "${1:-}" in
    start)
        shift
        DETACHED=false
        while [ $# -gt 0 ]; do
            case "$1" in
                -d) DETACHED=true ;;
                -p) shift; sed -i "s/^LOCKBOX_PORT=.*/LOCKBOX_PORT=$1/" "$ENV_FILE" ;;
            esac
            shift
        done

        if compose ps --status running 2>/dev/null | grep -q lockbox; then
            read -rp "lockbox is already running. Recreate? [y/N] " answer
            if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
                exit 0
            fi
        fi

        COMPOSE_ARGS="up --force-recreate"
        if [ "$DETACHED" = true ]; then
            COMPOSE_ARGS="up --force-recreate -d"
        fi

        compose $COMPOSE_ARGS
        ;;
    stop)
        compose down
        ;;
    upgrade)
        WAS_RUNNING=false
        if compose ps --status running 2>/dev/null | grep -q lockbox; then
            WAS_RUNNING=true
            read -rp "lockbox is running. Stop it to upgrade? [y/N] " answer
            if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
                echo "Upgrade cancelled"
                exit 0
            fi
            compose down
        fi

        echo "Updating lockbox..."
        curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-lockbox/main/install.sh | sudo bash
        echo "Upgrade complete"

        if [ "$WAS_RUNNING" = true ]; then
            read -rp "Start lockbox again? [y/N] " answer
            if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
                exit 0
            fi
            compose up -d
        fi
        ;;
    status)
        compose ps
        ;;
    logs)
        shift
        compose logs "$@"
        ;;
    *)
        usage
        ;;
esac
SCRIPT

sed -i "s|__LOCKBOX_HOME__|$LOCKBOX_HOME|g" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

chown -R "$REAL_UID:$REAL_GID" "$LOCKBOX_HOME"

docker pull "$IMAGE"

echo ""
echo "lockbox installed!"
echo ""
echo "  Command:         $INSTALL_PATH"
echo "  Authorized keys: $LOCKBOX_HOME/authorized_keys"
echo "  Work directory:  $LOCKBOX_HOME/work"
echo ""
echo "Add your SSH public key(s) to the authorized_keys file and run:"
echo ""
echo "  lockbox start -d"
echo ""
