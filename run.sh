#!/usr/bin/env bash
# Start the server with the Gradle application plugin.
set -euo pipefail
cd "$(dirname "$0")"

exec ./gradlew run "$@"
