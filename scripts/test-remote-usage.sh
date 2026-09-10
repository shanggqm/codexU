#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc Sources/CodexUsageWidget/Services/RemoteUsageReader.swift tests/RemoteUsageTests.swift -o build/test-remote-usage
build/test-remote-usage
