# Repository Participation Policy

Forsetti Jamf Pro is proprietary software. Public visibility of the source code permits inspection and the limited individual evaluation described in [`LICENSE`](LICENSE); it does not make the project open source.

## External development

This project does not accept code or documentation contributions from outside contributors. Pull requests opened by anyone other than a designated project maintainer will not be reviewed, approved, or merged.

If you want to inspect or evaluate the project, use a GitHub fork as permitted by GitHub's service terms or clone the repository for the limited purposes and 30-day Evaluation Period stated in [`LICENSE`](LICENSE). Local modifications are permitted only for that evaluation. Do not publish, distribute, or submit the modified work with an expectation that it will be incorporated into this repository.

## Maintainer submissions

Only designated project maintainers are eligible to submit work for inclusion in the official repository. Maintainers must have the right to submit all included material and must identify any third-party material and required notices.

See [`LICENSE`](LICENSE) for the proprietary source-inspection and evaluation terms and [`NOTICE`](NOTICE) for the repository notice.

## Attribution and identity

This repository enforces a **no tool-origin attribution** rule for commits,
authors, paths, pull request text, and source content. Maintainers must not
credit assistive tooling as author of the work.

Enforcement:

- GitHub Actions workflow **Provenance Guard** (`.github/workflows/provenance-guard.yml`)
- Local hooks via `scripts/install-hooks.sh` and `.githooks/`
