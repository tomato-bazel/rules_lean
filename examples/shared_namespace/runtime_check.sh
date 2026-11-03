#!/usr/bin/env bash
set -euo pipefail
actual="$("$1" "value with spaces")"
expected="pg_catalog:graph|value with spaces"
if [[ "$actual" != "$expected" ]]; then
  printf 'Unexpected runtime output: %s\n' "$actual" >&2
  exit 1
fi
