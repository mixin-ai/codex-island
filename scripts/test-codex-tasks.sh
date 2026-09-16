#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT
swiftc -parse-as-library -o "$OUT_DIR/tasks" Sources/Tasks/CodexTaskReader.swift Tests/CodexTaskTests.swift
"$OUT_DIR/tasks"
