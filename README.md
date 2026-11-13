# Parcel Relay

Dispatch parcels to two supervised courier processes. Deliver **four parcels by tick ten**.

- **1 / 2** sends an idle courier by the safe route (3 ticks).
- **1s / 2s** uses the shortcut (2 ticks). With the default seed **59**, the bridge closes at ticks **4 and 8**: a shortcut parcel still in transit is lost and its courier process restarts READY.
- **t** advances both couriers together. A busy courier keeps its parcel and route. Invalid commands cost no time. **q** or EOF exits during play or at a result.
- At a result, **r** retries the same seed, **n** starts the next seed, and **q** exits. A new round starts with empty counters and READY couriers, after stopping every old courier.

The result shows **delivered / late / lost**, plus the remaining goal shortfall. Late counts dispatched parcels still on the road at the tick-ten deadline; parcels never sent are not counted late or lost. Every failed parcel lists its courier, dispatch tick and the closure tick or remaining travel time. Losing a parcel does not stop play if there is still time.

Seeds choose three published bridge schedules: 59 → 4/8, 60 → 5/9, 61 → 3/7, then repeat. Retrying repeats the same challenge; choosing the next seed changes the closure timing. There is no random or real-time failure.

The screen shows closures before you choose. Avoid dispatching a shortcut across a closure; the safe route remains available. Each courier is a supervised GenServer. The restart budget covers both couriers at both scheduled closures. There is no background clock or network service.

![Actual CLI output](docs/images/play.png)

Captured from the real CLI failure/retry smoke on 2026-11-13; its stdout is rendered in a monospace viewer for the image. The game runs in a terminal.

**Theory handbook**: [docs/theory/](docs/theory/README.md) — 11 statements (couriers, routes, ticks, closures, supervision, results, seed selection and round ownership), each with its rule, assumptions, derivation, code, tests and a figure. `make theory-figs` regenerates the figures and the measured values by playing the real game; `make theory-check` checks the coverage table.

## Install and play

Linux x86-64, no sudo or containers. Install the current stable runtime as checked on 2026-11-06 ([Elixir installation](https://elixir-lang.org/install/)).

```sh
curl -fsSLo install.sh https://elixir-lang.org/install.sh
sh install.sh elixir@1.20.5 otp@29.1
export PATH="$HOME/.elixir-install/installs/otp/29.1/bin:$HOME/.elixir-install/installs/elixir/1.20.5-otp-29/bin:$PATH"
mix local.hex --force
MIX_ENV=test mix deps.get
```

Python 3.14 is required by the local report adapter. From this repository:

```sh
make play
make demo
make test
make check
```

`test` runs native unit tests; `check` also drives six real CLI scenarios: victory, repeated failure/retry/next/quit, lateness, quitting during play, and EOF during play and at a result. Each checks that the CLI leaves no live process in its OS process group (Linux). JUnit XML and schema-versioned summary JSON go to ignored `test-results/`. No test contacts a live service. PR CI runs unit checks only.

M3 is implemented. Terminal accessibility, Windows and macOS execution, long sessions and player enjoyment are unverified.

Verified on Linux: 19 ExUnit cases + 6 CLI scenarios, all passing. See [requirements](docs/requirements.md).
