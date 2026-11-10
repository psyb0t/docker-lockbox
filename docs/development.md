---
title: "Development"
description: "Build, lint and test docker-lockbox with Make and Docker, add a built-in command, and how the CI pipeline publishes and releases images."
nav_order: 9
---

# Development

This page is for changing lockbox itself. You need Docker, Make, Bash and an SSH client. Lint runs in containers, so no Python or shellcheck install is needed on the host.

## Make targets

```bash
make build        # build psyb0t/lockbox:latest
make build-test   # build psyb0t/lockbox:latest-test
make test         # build the test image and run ./test.sh
make lint         # shellcheck and flake8, both in containers
make docs         # build this documentation site locally
make clean        # remove both images
make help         # list the targets
```

`make lint` runs two targets:

- `lint-shell`: shellcheck v0.11.0 from the `koalaman/shellcheck` image over `entrypoint.sh`, `create_installer.sh` and `test.sh`.
- `lint-python`: flake8 7.3.0 in `python:3.12-slim` over `lockbox-wrapper`, at line length 88 to match black.

## Tests

[`test.sh`](https://github.com/psyb0t/docker-lockbox/blob/main/test.sh) is an integration suite. It builds the test image, generates a throwaway ed25519 key, starts a container, copies the key in with `docker cp` and runs every check as a real SSH command against the container's IP. It covers:

- refused commands and the usage message;
- injection attempts with `&&`, `;`, `|` and `$()`;
- every built-in, including traversal and absolute-path cases;
- host key persistence across a container recreate, through a mounted `host_keys` directory;
- `create_installer.sh` output for volumes, environment entries, processing units and the `set_env` upgrade path.

It prints a pass or fail line per check and exits 1 if any check failed. Because it connects to the container's IP, the machine running it needs a route to Docker's bridge network, which a normal Linux Docker host and GitHub's Ubuntu runners have.

## Adding a built-in

In [`lockbox-wrapper`](https://github.com/psyb0t/docker-lockbox/blob/main/lockbox-wrapper):

1. Write `cmd_<name>(args)`. Pass every path through `safe_path()` and call `die("path outside /work")` when it returns `None`. Use `die()` for every error.
2. Add the name to `BUILTINS`, which feeds the usage message.
3. Add it to the `builtins` dict in `main()`, which dispatches it.

Then add `run_test` checks to `test.sh`, including a `../../etc/...` traversal case, and a section to [File operations](file-operations.md).

## CI

[`.github/workflows/pipeline.yml`](https://github.com/psyb0t/docker-lockbox/blob/main/.github/workflows/pipeline.yml) runs on every push and calls workflows from [psyb0t/reusable-github-workflows](https://github.com/psyb0t/reusable-github-workflows):

| Push | What runs |
| --- | --- |
| Any branch | `make lint` and `make test` |
| `main` | Then builds `psyb0t/lockbox` for `linux/amd64` and `linux/arm64`, pushes `:latest` and `:sha-<commit>` to Docker Hub, scans the image with Grype, and refreshes the version and license badges |
| A `v*` tag | Waits for that commit's `main` run to pass, points the version tag at the same image digest without rebuilding, creates the GitHub release, and refreshes the badges |

Other branches stop after lint and tests. Scan findings go to the repository's Security tab and do not fail the run.

The other workflows mirror the repository to GitLab and Codeberg, archive it to the Wayback Machine and Software Heritage, pull issues opened on those mirrors back to GitHub, and close pull requests from people who are not collaborators.

## Releases

A release is a `vX.Y.Z` tag on a `main` commit whose pipeline run passed. Update `CHANGELOG.md` in that commit. The tag pipeline promotes the image already built for that commit, so what was tested is what ships.
