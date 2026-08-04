# Repository Participation Policy

Forsetti Jamf Pro is open source software licensed under the [Apache License, Version 2.0](LICENSE).

## External development

This project does not currently accept code or documentation contributions from outside contributors. Pull requests opened by anyone other than a designated project maintainer will not be reviewed, approved, or merged.

You may fork, clone, modify, and redistribute the project under the terms of the Apache License 2.0. Please do not open pull requests with an expectation that external work will be incorporated into this repository unless a maintainer has invited the contribution.

## Maintainer submissions

Only designated project maintainers are eligible to submit work for inclusion in the official repository. Maintainers must have the right to submit all included material and must identify any third-party material and required notices.

Unless stated otherwise, contributions intentionally submitted for inclusion are under the terms of the Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Attribution and identity

This repository enforces a **no tool-origin attribution** rule for commits,
authors, paths, pull request text, and source content. Maintainers must not
credit assistive tooling as author of the work.

Enforcement:

- GitHub Actions workflow **Provenance Guard** (`.github/workflows/provenance-guard.yml`)
- Local hooks via `scripts/install-hooks.sh` and `.githooks/`
