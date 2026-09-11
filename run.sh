#!/usr/bin/env bash
# Run RedotCraft. Pass through any Redot flags, e.g. ./run.sh --editor
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if ! command -v redot >/dev/null 2>&1; then
	echo "error: redot not found on PATH (install Redot 26.2 or set PATH)" >&2
	exit 1
fi

exec redot --path . "$@"
