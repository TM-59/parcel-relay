# M2 requirements

- REQ-input: invalid input and EOF must be safe.
- REQ-finish: win, loss and final state are deterministic.
- REQ-dispatch: two independent processes advance together.

- REQ-route: safe routes take three ticks, shortcuts two; closures at 4 and 8 affect shortcuts only.
- REQ-recovery: an outage kills the actual worker; supervision replaces it, loses its parcel, and quitting stops both workers.

`make test` runs the native unit suite. `make check` adds a real command-line victory.
Reports are ignored under `test-results/<run>/` with the latest summary at `test-results/summary.json`.
Network services, graphics, audio and persistence are outside M1.
