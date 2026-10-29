#!/usr/bin/env bash
# Build the application jar. Runtime dependencies are copied to ./libs and
# referenced through the jar manifest Class-Path.
set -euo pipefail
cd "$(dirname "$0")"

./gradlew clean build "$@"

echo
echo "Build finished."
echo "Jar:  build/libs/solon-read-1.0-SNAPSHOT.jar"
echo "Deps: libs/"
echo "Run:  java -jar build/libs/solon-read-1.0-SNAPSHOT.jar"
