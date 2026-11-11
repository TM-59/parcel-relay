PYTHON ?= python3.14
.PHONY: test check play demo theory-figs theory-check
test check play demo:
	$(PYTHON) scripts/check.py $@

# Regenerates the drawn figures and the measured-values table of docs/theory by playing the real game (one command).
theory-figs:
	mix run scripts/theory_figs.exs docs/theory/figures

# Fails when a statement of docs/theory has no figure, a link is broken, or a referenced function or test is gone.
theory-check:
	$(PYTHON) scripts/theory-check.py
