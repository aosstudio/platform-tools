PYTHON ?= python3
BUILD_JOBS ?= 8
LLVM_ROOT ?= /usr
export PYTHON BUILD_JOBS LLVM_ROOT

.PHONY: check fetch build verify

check:
	shellcheck scripts/*.sh
	$(PYTHON) -m ruff format --check scripts
	$(PYTHON) -m ruff check scripts
	$(PYTHON) -m mypy --strict scripts/*.py

fetch:
	mkdir -p out
	flock out/build.lock $(PYTHON) scripts/inputs.py

build:
	mkdir -p out
	flock out/build.lock bash scripts/build.sh

verify:
	flock --shared out/build.lock bash scripts/verify.sh
