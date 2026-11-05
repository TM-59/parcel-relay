# Parcel Relay

Dispatch parcels to two independent courier processes. Press **1** and **2** to load idle couriers, then **t** to advance both. Deliver four parcels by tick ten. A busy courier keeps its parcel; invalid commands cost no time. **q** or EOF exits.

Each courier is a supervised GenServer. Concurrent requests advance both on each player-controlled tick; there is no timer race or network service.

![Actual CLI output](docs/images/play.png)

Captured from the real CLI demo on 2026-11-06; its stdout is rendered in a monospace viewer for the image. The game runs in a terminal.

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

`test` runs native unit tests; `check` also drives a real CLI victory. JUnit XML and schema-versioned summary JSON go to ignored `test-results/`. No test contacts a live service. PR CI runs unit checks only.

M2 and M3 are separate milestones. Terminal accessibility, Windows and macOS execution, long sessions and player enjoyment are unverified.

Verified on Linux: 5 ExUnit cases + 1 CLI smoke, all passing. See [requirements](docs/requirements.md).
