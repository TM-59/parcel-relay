# M1 requirements

- REQ-input: invalid input and EOF must be safe.
- REQ-finish: win, loss and final state are deterministic.
- REQ-dispatch: two independent processes advance together.

`make test` runs the native unit suite. `make check` adds a real command-line victory.
Reports are ignored under `test-results/<run>/` with the latest summary at `test-results/summary.json`.
Network services, graphics, audio and persistence are outside M1.
