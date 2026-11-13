# Development rules

Use the native package manager and test framework.
Keep each milestone small and covered by meaningful tests.
Run make test and make check locally; never use containers.
Keep generated test reports, dependencies and secrets out of Git.
Use only original terminal text; no imported art, audio or fonts.
Public commits and pull requests must have no generated author trailers.
Run light unit checks only on pull requests, with paths and concurrency filters.
Keep docs/theory in step with the code: a new rule gets a page section, a figure and a table row in the same pull request; make theory-figs and make theory-check must pass, and the README's statement count (11) must match the table.
