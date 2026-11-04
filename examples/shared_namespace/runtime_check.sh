#!/usr/bin/env bash
set -euo pipefail
rc=0
actual="$("$1" "value with spaces" 2>&1)" || rc=$?
if (( rc != 0 )); then
  printf '%s\n' "$actual" >&2
  exit "$rc"
fi
expected="pg_catalog:graph|value with spaces"
if [[ "$actual" != "$expected" ]]; then
  printf 'Unexpected runtime output: %s\n' "$actual" >&2
  exit 1
fi
