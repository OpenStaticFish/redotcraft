#!/usr/bin/env bash
# Fail unless the installed Redot reports the expected version prefix.
# Usage: verify-redot.sh <expected-version-prefix>
set -euo pipefail

expected="$1"
installed="$(redot --version)"
echo "$installed"
if [[ "$installed" != "${expected}"* ]]; then
	echo "::error::Expected Redot ${expected}, got: $installed"
	exit 1
fi
