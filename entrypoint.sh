#!/bin/bash
set -e

# Rename lockbox user/group if LOCKBOX_USER is set (skip if already renamed)
TARGET_USER="${LOCKBOX_USER:-lockbox}"
if [ "$TARGET_USER" != "lockbox" ] && getent group lockbox >/dev/null 2>&1; then
	groupmod -n "$TARGET_USER" lockbox
	usermod -l "$TARGET_USER" -d "/home/$TARGET_USER" -m lockbox
	sed -i "s/AllowUsers lockbox/AllowUsers $TARGET_USER/" /etc/ssh/sshd_config
	sed -i "s/Match User lockbox/Match User $TARGET_USER/" /etc/ssh/sshd_config
fi

# Persist username for lockbox-wrapper (sshd strips env vars from ForceCommand children)
echo "$TARGET_USER" >/etc/lockbox/user

# Adjust UID/GID to match host user if env vars provided
TARGET_UID="${LOCKBOX_UID:-1000}"
TARGET_GID="${LOCKBOX_GID:-1000}"
CURRENT_UID=$(id -u "$TARGET_USER")
CURRENT_GID=$(id -g "$TARGET_USER")

if [ "$TARGET_GID" != "$CURRENT_GID" ]; then
	groupmod -g "$TARGET_GID" "$TARGET_USER"
fi

if [ "$TARGET_UID" != "$CURRENT_UID" ]; then
	usermod -u "$TARGET_UID" -o "$TARGET_USER"
fi

# Persist SSH host keys across container recreates
HOST_KEYS_DIR="/etc/lockbox/host_keys"
if [ -d "$HOST_KEYS_DIR" ]; then
	if ls "$HOST_KEYS_DIR"/ssh_host_* >/dev/null 2>&1; then
		cp "$HOST_KEYS_DIR"/ssh_host_* /etc/ssh/
	else
		cp /etc/ssh/ssh_host_* "$HOST_KEYS_DIR/"
	fi
fi

# Unlock the account so sshd allows pubkey auth
passwd -u "$TARGET_USER" >/dev/null 2>&1 || usermod -p '*' "$TARGET_USER"

chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER" /work

# Run entrypoint extension scripts if any
if [ -d "/etc/lockbox/entrypoint.d" ]; then
	shopt -s nullglob
	for script in /etc/lockbox/entrypoint.d/*.sh; do
		[ -x "$script" ] && "$script"
	done
	shopt -u nullglob
fi

# Dump env vars so SSH sessions can see them
env >>/etc/environment

exec "$@"
