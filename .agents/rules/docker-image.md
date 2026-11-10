# Docker image

- The base stays `ubuntu:24.04` with `openssh-server`, `python3` and `ca-certificates` and nothing else. Tools belong in downstream images, not here.
- The image contract downstream images depend on: `/etc/lockbox/allowed.json`, `/etc/lockbox/authorized_keys`, `/etc/lockbox/host_keys`, `/etc/lockbox/entrypoint.d/*.sh`, `/work`, the `LOCKBOX_USER`, `LOCKBOX_UID` and `LOCKBOX_GID` variables, `ENTRYPOINT ["/entrypoint.sh"]` and `CMD ["/usr/sbin/sshd", "-D", "-e"]`. Changing any of them is a breaking change and needs a CHANGELOG note.
- `authorized_keys` lives in `/etc/lockbox/`, not the home directory, because a bind mount into a home directory moved by `usermod -m` hits overlay2 problems (see the comment in `Dockerfile`).
- The `Dockerfile` copies only `allowed.json`, `sshd_config`, `lockbox-wrapper` and `entrypoint.sh`. `.dockerignore` keeps `docs/`, `.testing/`, Markdown other than the README and local files out of the build context.
- CI builds `linux/amd64` and `linux/arm64`. Do not add anything architecture-specific.
