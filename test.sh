#!/bin/bash
set -e

IMAGE="psyb0t/lockbox:latest-test"
CONTAINER="lockbox-test-$$"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR="$SCRIPT_DIR/.test-tmp-$$"
mkdir -p "$TMPDIR"
KEY="$TMPDIR/id_test"
AUTHKEYS="$TMPDIR/authorized_keys"
PASSED=0
FAILED=0
TOTAL=0

cleanup() {
	echo ""
	echo "Cleaning up..."
	docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
	rm -rf "$TMPDIR"
}

trap cleanup EXIT

fail() {
	echo "  FAIL: $1"
	if [ -n "$2" ]; then
		echo "        got: $(echo "$2" | head -1)"
	fi
	FAILED=$((FAILED + 1))
	TOTAL=$((TOTAL + 1))
}

pass() {
	echo "  PASS: $1"
	PASSED=$((PASSED + 1))
	TOTAL=$((TOTAL + 1))
}

ssh_cmd() {
	ssh -p 22 \
		-i "$KEY" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR \
		-o ConnectTimeout=5 \
		"lockbox@$CONTAINER_IP" "$1" 2>&1 || true
}

ssh_cmd_stdin() {
	ssh -p 22 \
		-i "$KEY" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR \
		-o ConnectTimeout=5 \
		"lockbox@$CONTAINER_IP" "$1" 2>/dev/null || true
}

# run_test <test_name> <ssh_command> <grep_pattern> [case_insensitive]
run_test() {
	local name="$1"
	local cmd="$2"
	local pattern="$3"
	local case_insensitive="${4:-}"

	local output
	output=$(ssh_cmd "$cmd")

	local grep_flags="-q"
	if [ "$case_insensitive" = "i" ]; then
		grep_flags="-qi"
	fi

	if echo "$output" | grep $grep_flags "$pattern"; then
		pass "$name"
		return
	fi

	fail "$name" "$output"
}

# run_test_negative <test_name> <ssh_command> <grep_pattern_that_should_NOT_match>
run_test_negative() {
	local name="$1"
	local cmd="$2"
	local pattern="$3"

	local output
	output=$(ssh_cmd "$cmd")

	if echo "$output" | grep -q "$pattern"; then
		fail "$name" "$output"
		return
	fi

	pass "$name"
}

echo "=== Building test image ==="
make build-test

echo ""
echo "=== Generating test SSH key ==="
ssh-keygen -t ed25519 -f "$KEY" -N "" -q
cp "$KEY.pub" "$AUTHKEYS"

echo ""
echo "=== Starting container ==="
docker run -d \
	--name "$CONTAINER" \
	-e "LOCKBOX_UID=$(id -u)" \
	-e "LOCKBOX_GID=$(id -g)" \
	"$IMAGE" >/dev/null

# Inject authorized_keys via docker cp (works in Docker-in-Docker environments
# where bind mounts resolve paths on the host, not in the client container)
docker cp "$AUTHKEYS" "$CONTAINER:/etc/lockbox/authorized_keys"
docker exec "$CONTAINER" chmod 644 /etc/lockbox/authorized_keys

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER")
echo "Container IP: $CONTAINER_IP"

echo "Waiting for sshd..."
for i in $(seq 1 30); do
	if docker exec "$CONTAINER" pgrep sshd >/dev/null 2>&1; then
		break
	fi
	sleep 0.5
done

# Give sshd a moment to be ready for connections
sleep 1

echo ""
echo "=== Container debug info ==="
docker exec "$CONTAINER" id lockbox
docker exec "$CONTAINER" ls -la /home/lockbox/
docker exec "$CONTAINER" cat /etc/lockbox/authorized_keys
echo "--- sshd logs ---"
docker logs "$CONTAINER" 2>&1 | tail -20

echo ""
echo "=== Testing blocked commands ==="

#                  name                       command                    pattern
run_test "cat blocked" "cat /etc/passwd" "not allowed"
run_test "bash blocked" "bash -c 'echo pwned'" "not allowed"
run_test "empty command shows usage" "" "Usage"

echo ""
echo "=== Testing command injection ==="

#                       name                   command                                    bad_pattern
run_test_negative "&& injection blocked" "list-files && cat /etc/passwd" "root:"
run_test_negative "; injection blocked" "list-files; cat /etc/passwd" "root:"
run_test_negative "| injection blocked" "list-files | cat /etc/passwd" "root:"
run_test_negative "\$() injection blocked" 'list-files $(cat /etc/passwd)' "root:"

echo ""
echo "=== Testing file operations ==="

# put a file
echo "hello lockbox" | ssh_cmd_stdin "put testfile.txt"
run_test "put file" "get testfile.txt" "hello lockbox"

# list-files shows the file (plain filename output)
run_test "list-files shows file" "list-files" "testfile.txt"

# list-files --json output
run_test "list-files --json valid" "list-files --json" '"name"'
run_test "list-files --json has size" "list-files --json" '"size"'
run_test "list-files --json has mode" "list-files --json" '"mode"'
run_test "list-files --json has isDir" "list-files --json" '"isDir"'
run_test "list-files --json shows file" "list-files --json" '"testfile.txt"'

# list-files default should not have . or ..
run_test_negative "list-files no dot" "list-files" '^\.\/$'
run_test_negative "list-files no dotdot" "list-files" '^\.\.\/$'

# create-dir
ssh_cmd "create-dir subdir"
run_test "create-dir creates dir" "list-files" "subdir"

# put into subdir
echo "nested content" | ssh_cmd_stdin "put subdir/nested.txt"
run_test "put in subdir" "get subdir/nested.txt" "nested content"

# list-files subdir
run_test "list-files subdir" "list-files subdir" "nested.txt"
run_test "list-files --json subdir" "list-files --json subdir" '"nested.txt"'

# remove-file
ssh_cmd "remove-file testfile.txt"
run_test_negative "remove-file deletes file" "list-files" "testfile.txt"

# remove-file dir blocked
run_test "remove-file dir blocked" "remove-file subdir" "is a directory"

# remove-dir on non-empty dir blocked
run_test "remove-dir non-empty blocked" "remove-dir subdir" "directory not empty"

# remove-dir on file blocked
run_test "remove-dir on file blocked" "remove-dir subdir/nested.txt" "not a directory"

# remove-dir-recursive nukes the whole thing
ssh_cmd "remove-dir-recursive subdir"
run_test_negative "remove-dir-recursive removes dir" "list-files" "subdir"

# remove-dir empty dir works
ssh_cmd "create-dir emptydir"
run_test "create-dir emptydir" "list-files" "emptydir"
ssh_cmd "remove-dir emptydir"
run_test_negative "remove-dir removes empty dir" "list-files" "emptydir"

# remove-dir-recursive /work blocked
run_test "remove-dir-recursive /work blocked" "remove-dir-recursive /" "cannot remove /work"
run_test "remove-dir /work blocked" "remove-dir /" "cannot remove /work"

# remove-dir/remove-dir-recursive traversal blocked
run_test "remove-dir traversal blocked" "remove-dir ../../etc" "path outside /work"
run_test "remove-dir-recursive traversal blocked" "remove-dir-recursive ../../etc" "path outside /work"

# path traversal blocked
run_test "get traversal blocked" "get ../../etc/passwd" "path outside /work"
run_test "put traversal blocked" "put ../../etc/evil" "path outside /work"
run_test "list-files traversal blocked" "list-files ../../etc" "path outside /work"
run_test "remove-file traversal blocked" "remove-file ../../etc/passwd" "path outside /work"
run_test "create-dir traversal blocked" "create-dir ../../etc/pwned" "path outside /work"

# absolute paths remap to /work (so /etc/passwd becomes /work/etc/passwd)
run_test "get abs path remapped" "get /etc/passwd" "no such file"
run_test_negative "get abs path no leak" "get /etc/passwd" "root:"

echo ""
echo "=== Testing new file operations ==="

# --- move-file ---
echo "move test" | ssh_cmd_stdin "put moveme.txt"
ssh_cmd "move-file moveme.txt moved.txt"
run_test "move-file creates dst" "get moved.txt" "move test"
run_test_negative "move-file removes src" "list-files" "moveme.txt"
run_test "move-file traversal blocked" "move-file ../../etc/passwd /tmp/x" "path outside /work"

# --- copy-file ---
ssh_cmd "copy-file moved.txt copied.txt"
run_test "copy-file creates dst" "get copied.txt" "move test"
run_test "copy-file keeps src" "get moved.txt" "move test"
run_test "copy-file traversal blocked" "copy-file ../../etc/passwd /tmp/x" "path outside /work"

# --- file-info ---
run_test "file-info has name" "file-info moved.txt" '"name"'
run_test "file-info has size" "file-info moved.txt" '"size"'
run_test "file-info has mode" "file-info moved.txt" '"mode"'
run_test "file-info has isDir" "file-info moved.txt" '"isDir"'
run_test "file-info nonexistent" "file-info nope.txt" "no such file"
run_test "file-info traversal blocked" "file-info ../../etc/passwd" "path outside /work"

# --- file-exists ---
run_test "file-exists true" "file-exists moved.txt" "true"
run_test "file-exists false" "file-exists nope.txt" "false"
run_test "file-exists traversal false" "file-exists ../../etc/passwd" "false"

# --- file-hash ---
# sha256 of "move test\n" = known hash
EXPECTED_HASH=$(printf "move test\n" | sha256sum | awk '{print $1}')
run_test "file-hash correct" "file-hash moved.txt" "$EXPECTED_HASH"
run_test "file-hash nonexistent" "file-hash nope.txt" "no such file"
run_test "file-hash traversal blocked" "file-hash ../../etc/passwd" "path outside /work"

# --- disk-usage ---
USAGE_OUTPUT=$(ssh_cmd "disk-usage")
if echo "$USAGE_OUTPUT" | grep -qE '^[0-9]+$'; then
	pass "disk-usage returns number"
else
	fail "disk-usage returns number" "$USAGE_OUTPUT"
fi
run_test "disk-usage traversal blocked" "disk-usage ../../etc" "path outside /work"

# --- search-files ---
ssh_cmd "create-dir searchdir/nested"
echo "findme" | ssh_cmd_stdin "put searchdir/found.txt"
echo "findme" | ssh_cmd_stdin "put searchdir/nested/deep.txt"
run_test "search-files finds file" "search-files **/*.txt" "found.txt"
run_test "search-files finds nested" "search-files **/*.txt" "deep.txt"
SEARCH_EMPTY=$(ssh_cmd "search-files **/*.xyz")
if [ -z "$SEARCH_EMPTY" ]; then
	pass "search-files no match returns empty"
else
	fail "search-files no match returns empty" "$SEARCH_EMPTY"
fi

# --- append-file ---
echo " appended" | ssh_cmd_stdin "append-file moved.txt"
run_test "append-file adds content" "get moved.txt" "appended"
run_test "append-file keeps original" "get moved.txt" "move test"
run_test "append-file nonexistent" "append-file nope.txt" "no such file"
run_test "append-file traversal blocked" "append-file ../../etc/passwd" "path outside /work"

# cleanup test files
ssh_cmd "remove-dir-recursive searchdir"
ssh_cmd "remove-file moved.txt"
ssh_cmd "remove-file copied.txt"

echo ""
echo "=== Testing host key persistence ==="

# Create a host_keys dir, start container with it mounted, grab fingerprint,
# destroy container, start a new one with same mount, verify fingerprint matches.
HOST_KEYS_DIR="$TMPDIR/host_keys"
mkdir -p "$HOST_KEYS_DIR"
CONTAINER2="lockbox-hostkey-test-$$"

docker run -d \
	--name "$CONTAINER2" \
	-e "LOCKBOX_UID=$(id -u)" \
	-e "LOCKBOX_GID=$(id -g)" \
	-v "$HOST_KEYS_DIR:/etc/lockbox/host_keys" \
	"$IMAGE" >/dev/null

docker cp "$AUTHKEYS" "$CONTAINER2:/etc/lockbox/authorized_keys"
docker exec "$CONTAINER2" chmod 644 /etc/lockbox/authorized_keys

# Wait for sshd
for i in $(seq 1 30); do
	if docker exec "$CONTAINER2" pgrep sshd >/dev/null 2>&1; then break; fi
	sleep 0.5
done
sleep 1

# Get the host key fingerprint
FP1=$(docker exec "$CONTAINER2" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')

# Verify keys were copied to mounted dir
if ls "$HOST_KEYS_DIR"/ssh_host_* >/dev/null 2>&1; then
	pass "host keys saved to volume"
else
	fail "host keys saved to volume" "no keys found in $HOST_KEYS_DIR"
fi

# Destroy and recreate
docker rm -f "$CONTAINER2" >/dev/null 2>&1

CONTAINER3="lockbox-hostkey-test2-$$"
docker run -d \
	--name "$CONTAINER3" \
	-e "LOCKBOX_UID=$(id -u)" \
	-e "LOCKBOX_GID=$(id -g)" \
	-v "$HOST_KEYS_DIR:/etc/lockbox/host_keys" \
	"$IMAGE" >/dev/null

for i in $(seq 1 30); do
	if docker exec "$CONTAINER3" pgrep sshd >/dev/null 2>&1; then break; fi
	sleep 0.5
done
sleep 1

FP2=$(docker exec "$CONTAINER3" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')

if [ "$FP1" = "$FP2" ] && [ -n "$FP1" ]; then
	pass "host keys persist across recreates"
else
	fail "host keys persist across recreates" "fp1=$FP1 fp2=$FP2"
fi

docker rm -f "$CONTAINER2" "$CONTAINER3" >/dev/null 2>&1 || true

echo ""
echo "=== Testing create_installer.sh environment support ==="

# Create a test YAML config with both volumes and environment
INSTALLER_CONFIG="$TMPDIR/test-config.yml"
INSTALLER_OUTPUT="$TMPDIR/test-install.sh"

cat >"$INSTALLER_CONFIG" <<'YAMLEOF'
name: testapp
image: psyb0t/testapp
repo: psyb0t/docker-testapp

volumes:
  - flag: -d
    env: DATA_DIR
    mount: /data
    default: ./data
    description: Data directory

environment:
  - flag: -g
    env: DEVICE
    container_env: APP_DEVICE
    default: cpu
    description: Device selection
  - flag: --gpus
    env: GPUS
    container_env: NVIDIA_VISIBLE_DEVICES
    default: all
    description: GPUs to expose
YAMLEOF

"$SCRIPT_DIR/create_installer.sh" "$INSTALLER_CONFIG" >"$INSTALLER_OUTPUT" 2>&1

# .env has environment defaults with correct env names
if grep -q "TESTAPP_DEVICE=cpu" "$INSTALLER_OUTPUT"; then
	pass "env: DEVICE mapped to TESTAPP_DEVICE in .env"
else
	fail "env: DEVICE mapped to TESTAPP_DEVICE in .env" "$(grep DEVICE "$INSTALLER_OUTPUT" | head -3)"
fi

if grep -q "TESTAPP_GPUS=all" "$INSTALLER_OUTPUT"; then
	pass "env: GPUS mapped to TESTAPP_GPUS in .env"
else
	fail "env: GPUS mapped to TESTAPP_GPUS in .env" "$(grep GPUS "$INSTALLER_OUTPUT" | head -3)"
fi

# docker-compose has container_env mapped to .env vars
if grep -q 'APP_DEVICE=.*TESTAPP_DEVICE' "$INSTALLER_OUTPUT"; then
	pass "container_env APP_DEVICE in docker-compose"
else
	fail "container_env APP_DEVICE in docker-compose" "$(grep APP_DEVICE "$INSTALLER_OUTPUT" | head -3)"
fi

if grep -q 'NVIDIA_VISIBLE_DEVICES=.*TESTAPP_GPUS' "$INSTALLER_OUTPUT"; then
	pass "container_env NVIDIA_VISIBLE_DEVICES in docker-compose"
else
	fail "container_env NVIDIA_VISIBLE_DEVICES in docker-compose" "$(grep NVIDIA "$INSTALLER_OUTPUT" | head -3)"
fi

# CLI help contains environment flags
if grep -q '\-g' "$INSTALLER_OUTPUT" && grep -q 'Device selection' "$INSTALLER_OUTPUT"; then
	pass "CLI help shows -g flag with description"
else
	fail "CLI help shows -g flag with description"
fi

if grep -q '\-\-gpus' "$INSTALLER_OUTPUT" && grep -q 'GPUs to expose' "$INSTALLER_OUTPUT"; then
	pass "CLI help shows --gpus flag with description"
else
	fail "CLI help shows --gpus flag with description"
fi

# start command handles environment flags via set_env
if grep -q 'set_env TESTAPP_DEVICE' "$INSTALLER_OUTPUT"; then
	pass "start -g updates TESTAPP_DEVICE via set_env"
else
	fail "start -g updates TESTAPP_DEVICE via set_env" "$(grep -n 'DEVICE' "$INSTALLER_OUTPUT" | head -5)"
fi

if grep -q 'set_env TESTAPP_GPUS' "$INSTALLER_OUTPUT"; then
	pass "start --gpus updates TESTAPP_GPUS via set_env"
else
	fail "start --gpus updates TESTAPP_GPUS via set_env" "$(grep -n 'GPUS' "$INSTALLER_OUTPUT" | head -5)"
fi

# Volumes still work alongside environment
if grep -q 'TESTAPP_DATA_DIR=' "$INSTALLER_OUTPUT"; then
	pass "volumes still work with environment present"
else
	fail "volumes still work with environment present"
fi

# No environment section without environment config
NOENV_CONFIG="$TMPDIR/noenv-config.yml"
NOENV_OUTPUT="$TMPDIR/noenv-install.sh"

cat >"$NOENV_CONFIG" <<'YAMLEOF'
name: simpleapp
image: psyb0t/simpleapp
repo: psyb0t/docker-simpleapp

volumes:
  - flag: -d
    env: DATA_DIR
    mount: /data
    default: ./data
    description: Data directory
YAMLEOF

"$SCRIPT_DIR/create_installer.sh" "$NOENV_CONFIG" >"$NOENV_OUTPUT" 2>&1

# docker-compose environment should only have LOCKBOX_UID/GID + PROCESSING_UNIT + overlay env vars, no extra env vars
env_lines=$(grep -c '^\s*- [A-Z].*=.*\$' "$NOENV_OUTPUT" 2>/dev/null || echo "0")
if [ "$env_lines" -le 5 ]; then
	pass "no extra env vars without environment config"
else
	fail "no extra env vars without environment config" "found $env_lines env lines"
fi

# Even without environment config, processing unit support is always present
if grep -q 'SIMPLEAPP_PROCESSING_UNIT=cpu' "$NOENV_OUTPUT"; then
	pass "processing unit always present (no env config)"
else
	fail "processing unit always present (no env config)" "$(grep PROCESSING "$NOENV_OUTPUT" | head -3)"
fi

if grep -q 'docker-compose.cuda.yml' "$NOENV_OUTPUT"; then
	pass "cuda overlay always generated (no env config)"
else
	fail "cuda overlay always generated (no env config)"
fi

if grep -q 'docker-compose.rocm.yml' "$NOENV_OUTPUT"; then
	pass "rocm overlay always generated (no env config)"
else
	fail "rocm overlay always generated (no env config)"
fi

echo ""
echo "=== Testing create_installer.sh processing unit support ==="

GPU_CONFIG="$TMPDIR/gpu-config.yml"
GPU_OUTPUT="$TMPDIR/gpu-install.sh"

cat >"$GPU_CONFIG" <<'YAMLEOF'
name: gpuapp
image: psyb0t/gpuapp
repo: psyb0t/docker-gpuapp

volumes:
  - flag: -d
    env: DATA_DIR
    mount: /data
    default: ./data
    description: Data directory
YAMLEOF

"$SCRIPT_DIR/create_installer.sh" "$GPU_CONFIG" >"$GPU_OUTPUT" 2>&1

# .env has PROCESSING_UNIT and GPUS
if grep -q "GPUAPP_PROCESSING_UNIT=cpu" "$GPU_OUTPUT"; then
	pass "gpu: PROCESSING_UNIT default in .env"
else
	fail "gpu: PROCESSING_UNIT default in .env" "$(grep PROCESSING "$GPU_OUTPUT" | head -3)"
fi

if grep -q "GPUAPP_GPUS=all" "$GPU_OUTPUT"; then
	pass "gpu: GPUS default in .env"
else
	fail "gpu: GPUS default in .env" "$(grep GPUS "$GPU_OUTPUT" | head -3)"
fi

# docker-compose.yml has PROCESSING_UNIT and NVIDIA_VISIBLE_DEVICES env vars
if grep -q 'PROCESSING_UNIT=.*GPUAPP_PROCESSING_UNIT' "$GPU_OUTPUT"; then
	pass "gpu: PROCESSING_UNIT in docker-compose env"
else
	fail "gpu: PROCESSING_UNIT in docker-compose env" "$(grep PROCESSING "$GPU_OUTPUT" | head -3)"
fi

# docker-compose.cuda.yml has NVIDIA_VISIBLE_DEVICES and nvidia driver
if grep -q 'docker-compose.cuda.yml' "$GPU_OUTPUT"; then
	pass "gpu: docker-compose.cuda.yml generated"
else
	fail "gpu: docker-compose.cuda.yml generated"
fi

if grep -q 'NVIDIA_VISIBLE_DEVICES=.*GPUAPP_GPUS' "$GPU_OUTPUT"; then
	pass "gpu: NVIDIA_VISIBLE_DEVICES in cuda overlay"
else
	fail "gpu: NVIDIA_VISIBLE_DEVICES in cuda overlay" "$(grep NVIDIA "$GPU_OUTPUT" | head -3)"
fi

if grep -q 'driver: nvidia' "$GPU_OUTPUT"; then
	pass "gpu: nvidia driver in cuda overlay"
else
	fail "gpu: nvidia driver in cuda overlay"
fi

# docker-compose.rocm.yml has HIP_VISIBLE_DEVICES and amd devices
if grep -q 'docker-compose.rocm.yml' "$GPU_OUTPUT"; then
	pass "gpu: docker-compose.rocm.yml generated"
else
	fail "gpu: docker-compose.rocm.yml generated"
fi

if grep -q 'HIP_VISIBLE_DEVICES=.*GPUAPP_GPUS' "$GPU_OUTPUT"; then
	pass "gpu: HIP_VISIBLE_DEVICES in rocm overlay"
else
	fail "gpu: HIP_VISIBLE_DEVICES in rocm overlay" "$(grep HIP "$GPU_OUTPUT" | head -3)"
fi

if grep -q '/dev/kfd' "$GPU_OUTPUT"; then
	pass "gpu: /dev/kfd in rocm overlay"
else
	fail "gpu: /dev/kfd in rocm overlay"
fi

# compose() has conditional cuda and rocm overlays
if grep -q 'cuda\*.*overlay.*docker-compose.cuda.yml' "$GPU_OUTPUT"; then
	pass "gpu: compose() has cuda conditional"
else
	fail "gpu: compose() has cuda conditional" "$(grep -A7 'compose()' "$GPU_OUTPUT" | head -8)"
fi

if grep -q 'rocm\*.*overlay.*docker-compose.rocm.yml' "$GPU_OUTPUT"; then
	pass "gpu: compose() has rocm conditional"
else
	fail "gpu: compose() has rocm conditional" "$(grep -A7 'compose()' "$GPU_OUTPUT" | head -8)"
fi

# CLI has --processing-unit and --gpus flags
if grep -q '\-\-processing-unit.*Processing unit' "$GPU_OUTPUT"; then
	pass "gpu: CLI help shows --processing-unit flag"
else
	fail "gpu: CLI help shows --processing-unit flag"
fi

if grep -q '\-\-gpus.*GPUs to expose' "$GPU_OUTPUT"; then
	pass "gpu: CLI help shows --gpus flag"
else
	fail "gpu: CLI help shows --gpus flag"
fi

# start handles --processing-unit and --gpus via set_env
if grep -q 'set_env GPUAPP_PROCESSING_UNIT' "$GPU_OUTPUT"; then
	pass "gpu: start --processing-unit updates PROCESSING_UNIT via set_env"
else
	fail "gpu: start --processing-unit updates PROCESSING_UNIT via set_env"
fi

if grep -q 'set_env GPUAPP_GPUS' "$GPU_OUTPUT"; then
	pass "gpu: start --gpus updates GPUS via set_env"
else
	fail "gpu: start --gpus updates GPUS via set_env"
fi

# set_env helper is present in generated CLI
if grep -q 'set_env()' "$GPU_OUTPUT"; then
	pass "gpu: set_env helper function present"
else
	fail "gpu: set_env helper function present"
fi

# All flag handlers use set_env (none should use sed for env updates)
if grep -q 'sed -i "s/^.*_PORT=/' "$GPU_OUTPUT"; then
	fail "gpu: no sed-based env updates (should use set_env)"
else
	pass "gpu: no sed-based env updates (all use set_env)"
fi

echo ""
echo "=== Testing set_env upgrade scenario ==="

# Simulate an upgrade scenario: .env exists but is missing keys that new
# CLI flags try to set. The old sed approach would silently do nothing;
# set_env should add missing keys.
SETENV_DIR="$TMPDIR/setenv-test"
mkdir -p "$SETENV_DIR"

# Extract the CLI wrapper from the generated installer
SETENV_INSTALLER="$TMPDIR/setenv-installer.sh"
"$SCRIPT_DIR/create_installer.sh" "$GPU_CONFIG" >"$SETENV_INSTALLER" 2>&1

# Extract just the set_env function from the generated installer
SETENV_CLI="$SETENV_DIR/cli.sh"
sed -n '/^set_env() {/,/^}/p' "$SETENV_INSTALLER" >"$SETENV_CLI"

# Create a minimal .env (simulating old install that's missing new keys)
cat >"$SETENV_DIR/.env" <<'MINENV'
GPUAPP_MEMSWAP=0
MINENV

# Create stub docker-compose files so compose() doesn't blow up
touch "$SETENV_DIR/docker-compose.yml"
touch "$SETENV_DIR/docker-compose.cuda.yml"
touch "$SETENV_DIR/docker-compose.rocm.yml"

# Source the CLI and call set_env directly
(
	export ENV_FILE="$SETENV_DIR/.env"
	# shellcheck disable=SC1090
	. "$SETENV_CLI"
	set_env GPUAPP_PORT 3333
	set_env GPUAPP_MEMORY 4g
	set_env GPUAPP_PROCESSING_UNIT cuda
)

# Verify the keys were added
if grep -q 'GPUAPP_PORT=3333' "$SETENV_DIR/.env"; then
	pass "set_env adds missing GPUAPP_PORT"
else
	fail "set_env adds missing GPUAPP_PORT" "$(cat "$SETENV_DIR/.env")"
fi

if grep -q 'GPUAPP_MEMORY=4g' "$SETENV_DIR/.env"; then
	pass "set_env adds missing GPUAPP_MEMORY"
else
	fail "set_env adds missing GPUAPP_MEMORY" "$(cat "$SETENV_DIR/.env")"
fi

if grep -q 'GPUAPP_PROCESSING_UNIT=cuda' "$SETENV_DIR/.env"; then
	pass "set_env adds missing GPUAPP_PROCESSING_UNIT"
else
	fail "set_env adds missing GPUAPP_PROCESSING_UNIT" "$(cat "$SETENV_DIR/.env")"
fi

# Verify set_env replaces existing key (not duplicates)
(
	export ENV_FILE="$SETENV_DIR/.env"
	# shellcheck disable=SC1090
	. "$SETENV_CLI"
	set_env GPUAPP_PORT 4444
)

PORT_COUNT=$(grep -c 'GPUAPP_PORT=' "$SETENV_DIR/.env")
if [ "$PORT_COUNT" -eq 1 ]; then
	pass "set_env replaces existing key (no duplicates)"
else
	fail "set_env replaces existing key (no duplicates)" "found $PORT_COUNT lines"
fi

if grep -q 'GPUAPP_PORT=4444' "$SETENV_DIR/.env"; then
	pass "set_env updates value correctly"
else
	fail "set_env updates value correctly" "$(grep GPUAPP_PORT "$SETENV_DIR/.env")"
fi

echo ""
echo "================================"
echo "Results: $PASSED passed, $FAILED failed, $TOTAL total"
echo "================================"

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
