#!/usr/bin/env bash
# Run headless Redot checks for CI. Each check gets its own process, log file,
# and timeout; failures are collected so one run reports every broken check.
#
# Usage:
#   CHECK_SHARD="Worldgen core" bash .github/scripts/run_checks.sh \
#     tools/worldgen_verify.gd tools/player_target_verify.tscn
#
# A `.gd` argument runs as `redot --headless --path . --script res://<arg>`;
# a `.tscn` argument runs as `redot --headless --path . res://<arg>`.
# Logs land in $RUNNER_TEMP/redot-checks for the caller to upload.
set -uo pipefail

repo_root="${GITHUB_WORKSPACE:-$(pwd)}"
log_dir="${RUNNER_TEMP:-/tmp}/redot-checks"
timeout_seconds="${CHECK_TIMEOUT_SECONDS:-900}"
shard_name="${CHECK_SHARD:-Checks}"
mkdir -p "$log_dir"

failed=()
summary=""

for check in "$@"; do
	label="$(basename "$check")"
	label="${label%.*}"
	log="$log_dir/$label.log"
	args=(--headless --path "$repo_root")
	if [[ "$check" == *.tscn ]]; then
		args+=("res://$check")
	else
		args+=(--script "res://$check")
	fi

	start=$SECONDS
	timeout --kill-after=30s "$timeout_seconds" redot "${args[@]}" >"$log" 2>&1
	exit_code=$?
	elapsed=$((SECONDS - start))

	if [[ $exit_code -eq 0 ]]; then
		echo "PASS $label (${elapsed}s)"
		summary+="| $label | pass | ${elapsed}s |\n"
	else
		echo "FAIL $label (exit $exit_code, ${elapsed}s)"
		echo "::error title=$label failed::$label exited $exit_code after ${elapsed}s; see the check-logs artifact"
		tail -n 40 "$log" || true
		failed+=("$label")
		summary+="| $label | **fail** (exit $exit_code) | ${elapsed}s |\n"
	fi
done

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	{
		echo "## $shard_name"
		echo
		echo "| Check | Result | Time |"
		echo "|---|---|---|"
		printf "%b" "$summary"
		echo
		echo "Full logs: \`$log_dir\`"
	} >>"$GITHUB_STEP_SUMMARY"
fi

if [[ ${#failed[@]} -gt 0 ]]; then
	echo "${#failed[@]} check(s) failed: ${failed[*]}"
	exit 1
fi
echo "All checks passed."
