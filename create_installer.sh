#!/bin/bash
set -e

CONFIG="${1:?Usage: $0 <config.yml>}"

if [ ! -f "$CONFIG" ]; then
	echo "Error: $CONFIG not found" >&2
	exit 1
fi

# ── Parse YAML ─────────────────────────────────────────────

name=$(awk '/^name:/{print $2}' "$CONFIG")
image=$(awk '/^image:/{print $2}' "$CONFIG")
repo=$(awk '/^repo:/{print $2}' "$CONFIG")
: "${name:?missing 'name' in $CONFIG}"
: "${image:?missing 'image' in $CONFIG}"
: "${repo:?missing 'repo' in $CONFIG}"

upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')

# Parse volumes list
declare -a vflag venv vmount vdefault vdesc
vc=0
in_vol=false
started=false

while IFS= read -r line; do
	[[ "$line" =~ ^volumes: ]] && {
		in_vol=true
		continue
	}
	$in_vol || continue
	[[ "$line" =~ ^[a-z] ]] && break

	if [[ "$line" =~ ^[[:space:]]*- ]]; then
		$started && vc=$((vc + 1))
		started=true
	fi

	[[ "$line" =~ flag:[[:space:]]*(.*) ]] && {
		vflag[$vc]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ env:[[:space:]]*(.*) ]] && {
		venv[$vc]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ mount:[[:space:]]*(.*) ]] && {
		vmount[$vc]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ default:[[:space:]]*(.*) ]] && {
		vdefault[$vc]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ description:[[:space:]]*(.*) ]] && {
		vdesc[$vc]="${BASH_REMATCH[1]}"
		continue
	}
done <"$CONFIG"

$started && vc=$((vc + 1))

# Parse environment list
declare -a eflag eenv econtainerenv edefault edesc
ec=0
in_env=false
started=false

while IFS= read -r line; do
	[[ "$line" =~ ^environment: ]] && {
		in_env=true
		continue
	}
	$in_env || continue
	[[ "$line" =~ ^[a-z] ]] && break

	if [[ "$line" =~ ^[[:space:]]*- ]]; then
		$started && ec=$((ec + 1))
		started=true
	fi

	[[ "$line" =~ flag:[[:space:]]*(.*) ]] && {
		eflag[$ec]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ container_env:[[:space:]]*(.*) ]] && {
		econtainerenv[$ec]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ env:[[:space:]]*(.*) ]] && {
		eenv[$ec]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ default:[[:space:]]*(.*) ]] && {
		edefault[$ec]="${BASH_REMATCH[1]}"
		continue
	}
	[[ "$line" =~ description:[[:space:]]*(.*) ]] && {
		edesc[$ec]="${BASH_REMATCH[1]}"
		continue
	}
done <"$CONFIG"

$started && ec=$((ec + 1))

# ── Generate install.sh to stdout ──────────────────────────

# --- Header ---
cat <<EOF
#!/bin/bash
IMAGE="$image"
INSTALL_PATH="/usr/local/bin/$name"
EOF

# --- Sudo resolution ---
cat <<'EOF'

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
EOF

# --- Home setup ---
echo ""
echo "${upper}_HOME=\"\$REAL_HOME/.$name\""
echo ""
printf 'mkdir -p "$%s_HOME/work" "$%s_HOME/host_keys"' "$upper" "$upper"
for ((i = 0; i < vc; i++)); do
	printf ' "$%s_HOME/%s"' "$upper" "${vdefault[$i]#./}"
done
echo ""
echo "touch \"\$${upper}_HOME/authorized_keys\""

# --- .env ---
echo ""
echo "if [ ! -f \"\$${upper}_HOME/.env\" ]; then"
echo "    cat > \"\$${upper}_HOME/.env\" << ENVEOF"
echo "${upper}_PORT=2222"
for ((i = 0; i < vc; i++)); do
	echo "${upper}_${venv[$i]}=\$${upper}_HOME/${vdefault[$i]#./}"
done
for ((i = 0; i < ec; i++)); do
	echo "${upper}_${eenv[$i]}=${edefault[$i]}"
done
echo "${upper}_PROCESSING_UNIT=cpu"
echo "${upper}_GPUS=all"
echo "${upper}_CPUS=0"
echo "${upper}_MEMORY=0"
echo "${upper}_SWAP=0"
echo "ENVEOF"
echo "fi"

# --- docker-compose.yml ---
echo ""
echo "cat > \"\$${upper}_HOME/docker-compose.yml\" << EOF"
echo "services:"
echo "  $name:"
echo "    image: \${IMAGE}"
echo "    ports:"
echo "      - \"\\\${${upper}_PORT:-2222}:22\""
echo "    environment:"
echo "      - LOCKBOX_UID=\${REAL_UID}"
echo "      - LOCKBOX_GID=\${REAL_GID}"
for ((i = 0; i < ec; i++)); do
	echo "      - ${econtainerenv[$i]}=\\\${${upper}_${eenv[$i]}:-${edefault[$i]}}"
done
echo "      - PROCESSING_UNIT=\\\${${upper}_PROCESSING_UNIT:-cpu}"
echo "    volumes:"
echo "      - ./authorized_keys:/etc/lockbox/authorized_keys:ro"
echo "      - ./host_keys:/etc/lockbox/host_keys"
echo "      - ./work:/work"
for ((i = 0; i < vc; i++)); do
	echo "      - \\\${${upper}_${venv[$i]}:-${vdefault[$i]}}:${vmount[$i]}"
done
echo "    cpus: \\\${${upper}_CPUS:-0}"
echo "    mem_limit: \\\${${upper}_MEMORY:-0}"
echo "    memswap_limit: \\\${${upper}_MEMSWAP:-0}"
echo "    restart: unless-stopped"
echo "EOF"

# --- GPU compose overlays ---
echo ""
echo "cat > \"\$${upper}_HOME/docker-compose.cuda.yml\" << EOF"
echo "services:"
echo "  $name:"
echo "    environment:"
echo "      - NVIDIA_VISIBLE_DEVICES=\\\${${upper}_GPUS:-all}"
echo "    deploy:"
echo "      resources:"
echo "        reservations:"
echo "          devices:"
echo "            - driver: nvidia"
echo "              capabilities: [gpu]"
echo "EOF"

echo ""
echo "cat > \"\$${upper}_HOME/docker-compose.rocm.yml\" << EOF"
echo "services:"
echo "  $name:"
echo "    environment:"
echo "      - HIP_VISIBLE_DEVICES=\\\${${upper}_GPUS:-all}"
echo "    devices:"
echo "      - /dev/kfd:/dev/kfd"
echo "      - /dev/dri:/dev/dri"
echo "    group_add:"
echo "      - video"
echo "      - render"
echo "EOF"

# --- CLI wrapper script ---
echo ""
echo "cat > \"\$INSTALL_PATH\" << 'SCRIPT'"
echo "#!/bin/bash"
echo "{"
echo ""
echo "${upper}_HOME=\"__${upper}_HOME__\""
echo "ENV_FILE=\"\$${upper}_HOME/.env\""
echo ""
echo "compose() {"
echo "    . \"\$ENV_FILE\""
echo "    local overlay=\"\""
echo "    case \"\${${upper}_PROCESSING_UNIT:-cpu}\" in"
echo "        cuda*) overlay=\"-f \$${upper}_HOME/docker-compose.cuda.yml\" ;;"
echo "        rocm*) overlay=\"-f \$${upper}_HOME/docker-compose.rocm.yml\" ;;"
echo "    esac"
echo "    docker compose --env-file \"\$ENV_FILE\" -f \"\$${upper}_HOME/docker-compose.yml\" \$overlay \"\$@\""
echo "}"

# set_env helper
echo ""
echo "set_env() {"
echo "    local key=\"\$1\" val=\"\$2\""
echo "    sed -i \"/^\${key}=/d\" \"\$ENV_FILE\""
echo "    echo \"\${key}=\${val}\" >> \"\$ENV_FILE\""
echo "}"

# to_bytes + compute_memswap
echo ""
cat <<'EOF'
# Convert size string (e.g. 4g, 512m) to bytes
to_bytes() {
    local val="$1"
    if [ "$val" = "0" ]; then echo 0; return; fi
    local num="${val%[bBkKmMgG]*}"
    local unit="${val##*[0-9.]}"
    case "${unit,,}" in
        g) echo $(( ${num%.*} * 1073741824 )) ;;
        m) echo $(( ${num%.*} * 1048576 )) ;;
        k) echo $(( ${num%.*} * 1024 )) ;;
        *) echo "$num" ;;
    esac
}
EOF
echo ""
echo "# Compute memswap (Docker's memswap_limit = ram + swap)"
echo "compute_memswap() {"
echo "    . \"\$ENV_FILE\""
echo "    local mem=\"\$${upper}_MEMORY\""
echo "    local swap=\"\$${upper}_SWAP\""
echo ""
echo "    if [ \"\$mem\" = \"0\" ] || [ -z \"\$mem\" ]; then"
echo "        set_env ${upper}_MEMSWAP 0"
echo "        return"
echo "    fi"
echo ""
echo "    if [ \"\$swap\" = \"0\" ] || [ -z \"\$swap\" ]; then"
echo "        set_env ${upper}_MEMSWAP \"\$mem\""
echo "        return"
echo "    fi"
echo ""
echo "    local mem_bytes swap_bytes total"
echo "    mem_bytes=\$(to_bytes \"\$mem\")"
echo "    swap_bytes=\$(to_bytes \"\$swap\")"
echo "    total=\$(( mem_bytes + swap_bytes ))"
echo ""
echo "    set_env ${upper}_MEMSWAP \"\$total\""
echo "}"

# usage()
echo ""
echo "usage() {"
echo "    echo \"Usage: $name <command>\""
echo "    echo \"\""
echo "    echo \"Commands:\""

# Build start flags string
start_flags="[-d] [--port PORT]"
for ((i = 0; i < vc; i++)); do
	uf=$(echo "${venv[$i]}" | tr '[:lower:]' '[:upper:]')
	start_flags+=" [${vflag[$i]} ${uf}]"
done
for ((i = 0; i < ec; i++)); do
	uf=$(echo "${eenv[$i]}" | tr '[:lower:]' '[:upper:]')
	start_flags+=" [${eflag[$i]} ${uf}]"
done
start_flags+=" [--processing-unit UNIT] [--gpus GPUS]"
start_flags+=" [--cpus CPUS] [--memory MEMORY] [--swap SWAP]"

echo "    echo \"  start $start_flags\""
echo "    echo \"                        Start $name (-d for detached)\""
for ((i = 0; i < vc; i++)); do
	echo "    echo \"                        ${vflag[$i]}  ${vdesc[$i]}\""
done
for ((i = 0; i < ec; i++)); do
	echo "    echo \"                        ${eflag[$i]}  ${edesc[$i]}\""
done
echo "    echo \"                        --processing-unit  Processing unit (cpu, cuda, rocm)\""
echo "    echo \"                        --gpus  GPUs to expose (all, 0, 0,1, etc.)\""
echo "    echo \"                        --cpus  CPU limit (e.g. 4, 0.5) - 0 = unlimited\""
echo "    echo \"                        --memory  RAM limit (e.g. 4g, 512m) - 0 = unlimited\""
echo "    echo \"                        --swap  Swap limit (e.g. 2g, 512m) - 0 = no swap\""
echo "    echo \"  stop                  Stop $name\""
echo "    echo \"  upgrade               Pull latest image and restart if needed\""
echo "    echo \"  uninstall             Stop $name and remove everything\""
echo "    echo \"  status                Show container status\""
echo "    echo \"  logs                  Show container logs (pass extra args to docker compose logs)\""
echo "}"

# case statement
echo ""
echo "case \"\${1:-}\" in"

# start
echo "    start)"
echo "        shift"
echo "        DETACHED=false"
echo "        while [ \$# -gt 0 ]; do"
echo "            case \"\$1\" in"
echo "                -d) DETACHED=true ;;"
echo "                --port) shift; set_env ${upper}_PORT \"\$1\" ;;"
for ((i = 0; i < vc; i++)); do
	echo "                ${vflag[$i]}) shift; set_env ${upper}_${venv[$i]} \"\$1\" ;;"
done
for ((i = 0; i < ec; i++)); do
	echo "                ${eflag[$i]}) shift; set_env ${upper}_${eenv[$i]} \"\$1\" ;;"
done
echo "                --processing-unit) shift; set_env ${upper}_PROCESSING_UNIT \"\$1\" ;;"
echo "                --gpus) shift; set_env ${upper}_GPUS \"\$1\" ;;"
echo "                --cpus) shift; set_env ${upper}_CPUS \"\$1\" ;;"
echo "                --memory) shift; set_env ${upper}_MEMORY \"\$1\" ;;"
echo "                --swap) shift; set_env ${upper}_SWAP \"\$1\" ;;"
echo "            esac"
echo "            shift"
echo "        done"
echo ""
echo "        if compose ps --status running 2>/dev/null | grep -q $name; then"
echo "            read -rp \"$name is already running. Recreate? [y/N] \" answer"
echo "            if [ \"\$answer\" != \"y\" ] && [ \"\$answer\" != \"Y\" ]; then"
echo "                exit 0"
echo "            fi"
echo "        fi"
echo ""
echo "        compute_memswap"
echo ""
echo "        COMPOSE_ARGS=\"up --force-recreate\""
echo "        if [ \"\$DETACHED\" = true ]; then"
echo "            COMPOSE_ARGS=\"up --force-recreate -d\""
echo "        fi"
echo ""
echo "        compose \$COMPOSE_ARGS"
echo "        ;;"

# stop
echo "    stop)"
echo "        compose down"
echo "        ;;"

# upgrade
echo "    upgrade)"
echo "        WAS_RUNNING=false"
echo "        if compose ps --status running 2>/dev/null | grep -q $name; then"
echo "            WAS_RUNNING=true"
echo "            read -rp \"$name is running. Stop it to upgrade? [y/N] \" answer"
echo "            if [ \"\$answer\" != \"y\" ] && [ \"\$answer\" != \"Y\" ]; then"
echo "                echo \"Upgrade cancelled\""
echo "                exit 0"
echo "            fi"
echo "            compose down"
echo "        fi"
echo ""
echo "        sudo -v"
echo "        echo \"Updating $name...\""
echo "        curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | sudo bash"
echo "        echo \"Upgrade complete\""
echo ""
echo "        if [ \"\$WAS_RUNNING\" = true ]; then"
echo "            read -rp \"Start $name again? [y/N] \" answer"
echo "            if [ \"\$answer\" != \"y\" ] && [ \"\$answer\" != \"Y\" ]; then"
echo "                exit 0"
echo "            fi"
echo "            compose up -d"
echo "        fi"
echo "        ;;"

# uninstall
echo "    uninstall)"
echo "        read -rp \"Uninstall $name? [y/N] \" answer"
echo "        if [ \"\$answer\" != \"y\" ] && [ \"\$answer\" != \"Y\" ]; then"
echo "            exit 0"
echo "        fi"
echo ""
echo "        compose down 2>/dev/null"
echo "        sudo rm -f \"\$0\""
echo ""
echo "        read -rp \"Remove \$${upper}_HOME? This deletes all data including work files. [y/N] \" answer"
echo "        if [ \"\$answer\" = \"y\" ] || [ \"\$answer\" = \"Y\" ]; then"
echo "            rm -rf \"\$${upper}_HOME\""
echo "        fi"
echo ""
echo "        echo \"$name uninstalled\""
echo "        ;;"
echo ""
# status
echo "    status)"
echo "        compose ps"
echo "        ;;"

# logs
echo "    logs)"
echo "        shift"
echo "        compose logs \"\$@\""
echo "        ;;"

# default
echo "    *)"
echo "        usage"
echo "        ;;"
echo "esac"
echo ""
echo "exit"
echo "}"

# End of CLI script heredoc
echo "SCRIPT"

# --- Finalization ---
echo ""
echo "sed -i \"s|__${upper}_HOME__|\$${upper}_HOME|g\" \"\$INSTALL_PATH\""
echo "chmod +x \"\$INSTALL_PATH\""
echo ""
echo "chown -R \"\$REAL_UID:\$REAL_GID\" \"\$${upper}_HOME\""
echo ""
echo "docker pull \"\$IMAGE\""

# --- Success message ---
echo ""
echo "echo \"\""
echo "echo \"$name installed!\""
echo "echo \"\""
echo "echo \"  Command:         \$INSTALL_PATH\""
echo "echo \"  Authorized keys: \$${upper}_HOME/authorized_keys\""
echo "echo \"  Work directory:  \$${upper}_HOME/work\""
for ((i = 0; i < vc; i++)); do
	printf 'echo "  %-16s $%s_HOME/%s/"\n' "${vdesc[$i]}:" "$upper" "${vdefault[$i]#./}"
done
echo "echo \"\""
echo "echo \"Add your SSH public key(s) to the authorized_keys file and run:\""
echo "echo \"\""
echo "echo \"  $name start -d\""
echo "echo \"\""
