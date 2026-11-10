# Changelog

All notable changes per release. Versions follow [semver](https://semver.org).

## v2.1.9 — 2026-11-10

- The documentation is published at https://psyb0t.github.io/docker-lockbox/. The file operations, configuration, installer generator, security, architecture, troubleshooting and development reference moved there from the README, which keeps the overview, the quick start and links.
- Every branch push now runs lint and the integration tests before anything is built. A push to `main` publishes `:latest` and `:sha-<commit>`, and a release tag promotes that same image instead of rebuilding it, then cuts the GitHub release.
- Added `make lint`, which runs shellcheck on the shell scripts and flake8 on `lockbox-wrapper` from pinned images.
- Added Buy Me a Coffee to the funding links, and committed `AGENTS.md` plus project rules in `.agents/rules/` for coding agents.

## v2.1.8 — 2026-08-01

CI only — no image or wrapper changes. The published image is identical to v2.1.7.

- Added `.github/workflows/mirror-and-archive.yml`: pushes are mirrored to GitLab and Codeberg, and the default branch plus tags are archived to the Wayback Machine and Software Heritage. Feature-branch pushes skip the archive because it is rate-limited. Gitee mirroring is present but disabled — it silently creates the repo private unless the account has a mobile number bound.
- Added `.github/workflows/issue-pull.yml`: issues opened on the GitLab and Codeberg mirrors are pulled back into this repo every six hours. The schedule is staggered per repo and jitters on top of that, since GitHub fires an account's crons at the same instant; a manual `workflow_dispatch` run skips the jitter.

## v2.1.7 — 2026-07-27

- Added a GitHub Actions CI status badge to the README.

## v2.1.6 — 2026-07-27

Add README status badges.

- Added self-hosted version and license badges (rendered as SVGs on the `badges` branch by the `create-badges` CI job, no third-party render service) plus a Docker Hub pulls badge. Wired a badges job into pipeline.yml.
