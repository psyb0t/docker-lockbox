# Shell style

Applies to `entrypoint.sh`, `create_installer.sh` and `test.sh`.

- `#!/bin/bash`, then `set -e`. Quote every expansion.
- Indent with tabs, as the files already do.
- `make lint-shell` runs shellcheck (pinned image) over the three scripts at the default severity, and it must stay clean. Fix the code. A `# shellcheck disable=SCxxxx` needs a reason on the same or the previous line.
- `create_installer.sh` writes the generated `install.sh` to stdout only. Diagnostics go to stderr, or they end up inside the generated script.
- In `create_installer.sh`, text for the generated script is escaped once for `echo` and again for the heredocs inside the generated script (`\\\${VAR}` survives into `docker-compose.yml` as `${VAR}`). Check a change by generating an installer and reading the result; `test.sh` does this for the documented config shapes.
- `entrypoint.sh` runs as root on every container start, so each step must be safe to repeat: the rename skips when the user is already renamed, and UID/GID changes run only when the value differs.
