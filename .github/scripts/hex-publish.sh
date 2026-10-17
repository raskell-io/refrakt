#!/usr/bin/env bash
# Publish the Gleam package in the current directory to Hex, non-interactively.
#
# `gleam publish --yes` still asks for a typed confirmation on 0.x versions
# and, without one, prints "Not publishing." and exits 0. Feed it the phrase
# and fail loudly if Gleam refuses for any reason.
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

printf 'I am not using semantic versioning\n' \
  | gleam publish --yes 2>&1 | tee "$log"

if grep -q "Not publishing" "$log"; then
  echo "::error::gleam publish did not publish $(basename "$PWD")"
  exit 1
fi
