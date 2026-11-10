# Security

- Never read, print or commit `.env` or `*.env` files, private keys or `authorized_keys` files with real keys. Tests generate a throwaway ed25519 key in a temporary directory.
- Keep the sshd hardening in `sshd_config`: `PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers lockbox`, forwarding off, and `ForceCommand /usr/local/bin/lockbox-wrapper` under `Match User lockbox`. A change there updates `docs/security.md`.
- The wrapper is the only thing between a key holder and the container. No code path may fall through to a shell, and no built-in may touch a path that did not pass `safe_path()`.
- `allowed.json` maps names to absolute binary paths. Allowed binaries receive arguments unchecked, start in the user's home directory and see the container environment through `/etc/environment`. Document any change to that in `docs/security.md`, since downstream images depend on it.
- `search-files` does not sandbox its glob pattern (see `AGENTS.md`). Treat that as a known gap; do not widen it.
- Host keys persist only through the `/etc/lockbox/host_keys` volume. Without it, every new container gets the keys baked into the image at build time.
