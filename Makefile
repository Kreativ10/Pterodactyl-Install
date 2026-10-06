SHELL := /usr/bin/env bash
SCRIPTS := install.sh panel.sh wings.sh phpmyadmin.sh uninstall.sh $(wildcard lib/*.sh) $(wildcard tests/*.sh)

.PHONY: check test lint integration
check: lint test

test:
	python3 -m unittest discover -s tests -v

lint:
	@for script in $(SCRIPTS); do bash -n "$$script" || exit; done
	@if command -v shellcheck >/dev/null; then \
		shellcheck -x -P . $(SCRIPTS); \
	else \
		docker run --rm -v "$(CURDIR):/repo:ro" -w /repo koalaman/shellcheck:stable -x -P . $(SCRIPTS); \
	fi

integration:
	bash tests/run-integration.sh
