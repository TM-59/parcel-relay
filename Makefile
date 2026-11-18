PYTHON ?= uv run --locked python
.PHONY: test check play demo theory-figs theory-check fmt lint typecheck check-style
test check play demo:
	$(PYTHON) scripts/check.py $@

# Regenerates the drawn figures and the measured-values table of docs/theory by playing the real game (one command).
theory-figs:
	mix run scripts/theory_figs.exs docs/theory/figures

# Fails when a statement of docs/theory has no figure, a link is broken, or a referenced function or test is gone.
theory-check:
	$(PYTHON) scripts/theory-check.py

# Formatter, linter and type checker for Elixir (mix format, Credo strict, Dialyzer) and for the
# Python scripts (Ruff with every rule, mypy strict). Versions are pinned by mix.lock and uv.lock; no ignores.
fmt:
	mix format
	uv run --locked ruff format scripts
	uv run --locked ruff check --fix scripts
lint:
	mix format --check-formatted
	mix credo --strict --all
	uv run --locked ruff format --check scripts
	uv run --locked ruff check scripts
typecheck:
	mix compile --force --warnings-as-errors
	mix dialyzer --format short
	uv run --locked mypy
check-style: lint typecheck
