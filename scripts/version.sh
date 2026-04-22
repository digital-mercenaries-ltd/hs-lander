#!/usr/bin/env bash
# version.sh — Print the hs-lander framework version from the VERSION file
# at the repo/install root. Single source of truth; every other script and
# the skill should use this rather than grepping the file themselves.
#
# Usage:   bash scripts/version.sh
# Output:  FRAMEWORK_VERSION=<value>     (or FRAMEWORK_VERSION=unknown)
# Exit:    0 always — absence of VERSION is not fatal, just unknown.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version_file="$(dirname "$script_dir")/VERSION"

if [[ -f "$version_file" ]]; then
  # Strip any trailing newline / whitespace so downstream consumers don't
  # need to normalise.
  version=$(tr -d '[:space:]' < "$version_file")
else
  version="unknown"
fi

echo "FRAMEWORK_VERSION=${version:-unknown}"
