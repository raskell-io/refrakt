#!/bin/bash
# Build a refrakt wrapper script for convenience.
#
# This creates a `refrakt` script in the current directory that
# delegates to `gleam run -m refrakt/cli`.
#
# Usage:
#   ./bin/build-cli.sh
#   ./refrakt new my_app
#
set -euo pipefail

gleam build

cat > refrakt <<'SCRIPT'
#!/bin/bash
# Refrakt CLI wrapper — delegates to gleam run -m refrakt/cli
gleam run -m refrakt/cli -- "$@"
SCRIPT

chmod +x refrakt
echo "Created ./refrakt wrapper script"
echo "Run: ./refrakt new my_app"
