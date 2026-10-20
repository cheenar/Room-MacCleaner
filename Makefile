# Room — native app, stable local signing and a read-only CLI.
PREFIX      ?= $(HOME)/.local
INSTALL_DIR ?= $(HOME)/Applications
SIGN_ID     ?= auto

.PHONY: build app signing-identity install uninstall test test-packaging lint clean

build:
	swift build -c release

app:
	@SIGN_ID="$(SIGN_ID)" scripts/build.sh

signing-identity:
	@scripts/signing-identity.sh --create

install: app
	@PREFIX="$(PREFIX)" INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh

uninstall:
	@PREFIX="$(PREFIX)" INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh --uninstall

test:
	swift test
	@bash -n scripts/build.sh scripts/install.sh scripts/signing-identity.sh scripts/test-packaging.sh

test-packaging: app
	@scripts/test-packaging.sh

lint:
	xcrun swift-format lint --strict --recursive Sources Tests scripts/icon.swift Package.swift
	@bash -n scripts/build.sh scripts/install.sh scripts/signing-identity.sh scripts/test-packaging.sh

clean:
	swift package clean
	rm -rf dist
