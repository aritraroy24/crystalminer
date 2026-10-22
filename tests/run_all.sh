#!/bin/sh
# Runs every test: the pure-Lua unit tests (if luajit or lua5.1 is installed), then the
# in-server self-test. Usage: tests/run_all.sh [path-to-luanti-binary]
set -e
cd "$(dirname "$0")/.."
LUA="$(command -v luajit || command -v lua5.1 || true)"
if [ -n "$LUA" ]; then
	for t in tests/test_*.lua; do "$LUA" "$t"; done
else
	echo "Skipping unit tests: install luajit (macOS: brew install luajit) to run them."
fi
# The web version (web/) against the Lua engine, if Node.js and Lua are installed.
if [ -n "$LUA" ] && command -v node >/dev/null 2>&1; then
	node tests/test_web.mjs
else
	echo "Skipping the web version's tests: they need Node.js and luajit."
fi
tests/run_server_test.sh "$@"
