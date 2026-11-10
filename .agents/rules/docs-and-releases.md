# Docs and releases

- The documentation site is `docs/`, published by GitHub Pages from `main` at https://psyb0t.github.io/docker-lockbox/ with the Just the Docs theme (`remote_theme` pinned in `docs/_config.yml`, colors in `docs/_sass/`).
- Every page has front matter with a unique `title` and a `description` of 50 to 170 characters, and exactly one `#` heading.
- Links between pages use the relative `.md` path. A link to a file outside `docs/` uses the full `https://github.com/psyb0t/docker-lockbox/blob/main/<path>` URL. Wrap code blocks containing `{{` or `{%` in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`.
- After a docs change, run `make docs` and check the built site's links before handing off.
- The README is the front door: what lockbox is, the quick start, and a Documentation section with full site URLs. Reference material goes in `docs/`. Each fact has one home.
- A behavior, setting or command change updates the matching docs page in the same change.
- Prose: no em dashes, "directory" never "folder", no AI vocabulary, sentence case headings, one paragraph per source line.
- CHANGELOG entries are written at release time, newest first. A release is a `vX.Y.Z` tag on a commit whose `main` pipeline run passed; the pipeline promotes that run's image and cuts the GitHub release.
