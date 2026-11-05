PYTHON ?= python3.14
.PHONY: test check play demo
test check play demo:
	$(PYTHON) scripts/check.py $@
