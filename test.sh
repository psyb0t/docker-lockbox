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
run_test           "cat blocked"              "cat /etc/passwd"          "not allowed"
run_test           "bash blocked"             "bash -c 'echo pwned'"     "not allowed"
run_test           "empty command shows usage" ""                        "Usage"

echo ""
echo "=== Testing command injection ==="

#                       name                   command                                    bad_pattern
run_test_negative       "&& injection blocked" "ls && cat /etc/passwd"                     "root:"
run_test_negative       "; injection blocked"  "ls; cat /etc/passwd"                       "root:"
run_test_negative       "| injection blocked"  "ls | cat /etc/passwd"                      "root:"
run_test_negative       "\$() injection blocked" 'ls $(cat /etc/passwd)'                   "root:"

echo ""
echo "=== Testing file operations ==="

# put a file
echo "hello lockbox" | ssh_cmd_stdin "put testfile.txt"
run_test "put file" "get testfile.txt" "hello lockbox"

# ls shows the file (default ls -alph style)
run_test "ls shows file" "ls" "testfile.txt"
run_test "ls shows permissions" "ls" "rw-"
run_test "ls shows owner" "ls" "lockbox"

# ls --json output
run_test "ls --json valid" "ls --json" '"name"'
run_test "ls --json has size" "ls --json" '"size"'
run_test "ls --json has mode" "ls --json" '"mode"'
run_test "ls --json has isDir" "ls --json" '"isDir"'
run_test "ls --json shows file" "ls --json" '"testfile.txt"'

# ls default should not have . or ..
run_test_negative "ls no dot" "ls" '^\.\/$'
run_test_negative "ls no dotdot" "ls" '^\.\.\/$'

# mkdir
ssh_cmd "mkdir subdir"
run_test "mkdir creates dir" "ls" "subdir"

# put into subdir
echo "nested content" | ssh_cmd_stdin "put subdir/nested.txt"
run_test "put in subdir" "get subdir/nested.txt" "nested content"

# ls subdir
run_test "ls subdir" "ls subdir" "nested.txt"
run_test "ls --json subdir" "ls --json subdir" '"nested.txt"'

# rm
ssh_cmd "rm testfile.txt"
run_test_negative "rm deletes file" "ls" "testfile.txt"

# rm dir blocked
run_test "rm dir blocked" "rm subdir" "is a directory"

# rmdir on non-empty dir blocked
run_test "rmdir non-empty blocked" "rmdir subdir" "directory not empty"

# rmdir on file blocked
run_test "rmdir on file blocked" "rmdir subdir/nested.txt" "not a directory"

# rrmdir nukes the whole thing
ssh_cmd "rrmdir subdir"
run_test_negative "rrmdir removes dir" "ls" "subdir"

# rmdir empty dir works
ssh_cmd "mkdir emptydir"
run_test "mkdir emptydir" "ls" "emptydir"
ssh_cmd "rmdir emptydir"
run_test_negative "rmdir removes empty dir" "ls" "emptydir"

# rrmdir /work blocked
run_test "rrmdir /work blocked" "rrmdir /" "cannot remove /work"
run_test "rmdir /work blocked" "rmdir /" "cannot remove /work"

# rmdir/rrmdir traversal blocked
run_test "rmdir traversal blocked" "rmdir ../../etc" "path outside /work"
run_test "rrmdir traversal blocked" "rrmdir ../../etc" "path outside /work"

# path traversal blocked
run_test "get traversal blocked" "get ../../etc/passwd" "path outside /work"
run_test "put traversal blocked" "put ../../etc/evil" "path outside /work"
run_test "ls traversal blocked" "ls ../../etc" "path outside /work"
run_test "rm traversal blocked" "rm ../../etc/passwd" "path outside /work"
run_test "mkdir traversal blocked" "mkdir ../../etc/pwned" "path outside /work"

# absolute paths remap to /work (so /etc/passwd becomes /work/etc/passwd)
run_test "get abs path remapped" "get /etc/passwd" "no such file"
run_test_negative "get abs path no leak" "get /etc/passwd" "root:"

echo ""
echo "================================"
echo "Results: $PASSED passed, $FAILED failed, $TOTAL total"
echo "================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
