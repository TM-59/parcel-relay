# M3 requirements

- REQ-input: invalid input and EOF must be safe.
- REQ-finish: win, loss and final state are deterministic.
- REQ-dispatch: two independent processes advance together.

- REQ-route: safe routes take three ticks, shortcuts two; default-seed closures at 4 and 8 affect shortcuts only.
- REQ-recovery: an outage kills the actual worker; supervision replaces it, loses its parcel, and quitting stops both workers.

`make test` runs the native unit suite. `make check` adds six real CLI scenarios, each with process-group cleanup verification.
Reports are ignored under `test-results/<run>/` with the latest summary at `test-results/summary.json`.
Network services, graphics, audio and persistence are outside M1.

- REQ-result: accepted parcels retain their outcome and tick; results show delivered, late and lost plus the goal shortfall. Each failure identifies the courier, dispatch tick and bridge closure/deadline cause.
- REQ-seed: the default seed is 59 with closures 4/8; seeds 60 and 61 select 5/9 and 3/7. The three schedules repeat; all are solvable using safe routes.
- REQ-session: at a result r retries the same seed, n increments it, q/EOF exits. Stop the old supervised tree before starting a completely empty round. Invalid result input preserves state; r/n during play do nothing.

Late means dispatched but still in transit at a losing deadline, not every missing delivery. The four-parcel goal is checked before the deadline, including arrivals on tick ten. These are parcel counts, with no weighted score.
