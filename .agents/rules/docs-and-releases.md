# Docs and releases

- The documentation site is `docs/`, published by GitHub Pages from `main` at https://psyb0t.github.io/docker-lockbox/ with the Just the Docs theme (`remote_theme` pinned in `docs/_config.yml`, colors in `docs/_sass/`).
- Wrap code blocks containing `{{` or `{%` in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`.
- After a docs change, run `make docs` and check the built site's links.
- A release tag goes on a commit whose `main` pipeline run passed, because the pipeline promotes that run's image and cuts the GitHub release.
