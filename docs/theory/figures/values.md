# Measured values

Written by `make theory-figs` (scripts/theory_figs.exs) by playing the real game with its supervised processes. Do not edit by hand.
The last column is the relative error; where the theory column is 0 it is the absolute value.

| id | what is measured | measured | theory | error |
|---|---|---|---|---|
| `route-safe` | ticks for a SAFE parcel dispatched at tick 0 (theory 3) | 3 | 3 | 0.0e+0 |
| `route-short` | ticks for a SHORT parcel dispatched at tick 0 (theory 2) | 2 | 2 | 0.0e+0 |
| `busy-refused` | a second dispatch to a courier already on the road is answered busy (1 = yes) | 1 | 1 | 0.0e+0 |
| `busy-keeps-route` | ticks left on the first parcel after that refused dispatch (theory 2: SAFE, one tick gone) | 2 | 2 | 0.0e+0 |
| `tick-both` | couriers that moved on one t after both were dispatched SAFE (theory 2) | 2 | 2 | 0.0e+0 |
| `closure-short-lost` | of nine dispatch ticks 0..8, SHORT parcels lost to a closure (theory 4: dispatched after 2, 3, 6 or 7 ticks) | 4 | 4 | 0.0e+0 |
| `closure-first-lost` | earliest dispatch tick whose SHORT parcel is lost (theory 2) | 2 | 2 | 0.0e+0 |
| `closure-safe-lost` | of nine dispatch ticks, SAFE parcels lost (theory 0) | 0 | 0 | 0.0e+0 |
| `restart-new-pids` | couriers whose process identifier changed after a closure killed both (theory 2) | 2 | 2 | 0.0e+0 |
| `restart-alive` | courier processes alive after that closure (theory 2) | 2 | 2 | 0.0e+0 |
| `restart-ready` | of those, READY with no parcel (theory 2) | 2 | 2 | 0.0e+0 |
| `restart-four` | parcels lost when both closures kill both couriers in one game (theory 4) | 4 | 4 | 0.0e+0 |
| `restart-supervisor` | the supervisor is still alive after those four restarts (1 = yes) | 1 | 1 | 0.0e+0 |
| `win-safe-tick` | tick on which two SAFE rounds by both couriers win (theory 6) | 6 | 6 | 0.0e+0 |
| `frozen-ticks` | tick counter after three more commands on that won game (theory 6: unchanged) | 6 | 6 | 0.0e+0 |
| `frozen-delivered` | deliveries after those commands (theory 4) | 4 | 4 | 0.0e+0 |
| `idle-lost-tick` | tick on which a game with no dispatch is lost; further t does nothing (theory 10) | 10 | 10 | 0.0e+0 |
| `invalid-ticks` | ticks used by five invalid commands (theory 0) | 0 | 0 | 0.0e+0 |
| `plans-tried` | route lists tried: four routes, SAFE or SHORT each (theory 16) | 16 | 16 | 0.0e+0 |
| `plans-won` | of those, lists that win by tick 10 (reported) | 16 | 16 | 0.0e+0 |
| `plans-best-tick` | earliest winning tick over all sixteen (reported) | 5 | 5 | 0.0e+0 |
| `plans-best-count` | lists that reach it (reported) | 4 | 4 | 0.0e+0 |
| `plans-all-safe` | winning tick of SAFE, SAFE, SAFE, SAFE (theory 6) | 6 | 6 | 0.0e+0 |
| `plans-all-short-lost` | parcels lost by SHORT, SHORT, SHORT, SHORT (reported) | 2 | 2 | 0.0e+0 |
| `plans-all-short-tick` | tick on which SHORT, SHORT, SHORT, SHORT ends (reported) | 6 | 6 | 0.0e+0 |
