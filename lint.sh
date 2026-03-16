#!/bin/bash
# Lint shell scripts with shfmt and shellcheck

set -e

SCRIPT="${1:-./github-forgejo-migrate.sh}"

echo "Formatting $SCRIPT with shfmt..."
shfmt -w "$SCRIPT"

echo "Checking $SCRIPT with shellcheck..."
shellcheck "$SCRIPT"

echo "✓ All checks passed!"