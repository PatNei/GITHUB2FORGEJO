#!/usr/bin/env bash
# setup_and_test.sh — Run the full test suite
#
# Usage:
#   ./setup_and_test.sh                                         # validation only
#   GITHUB_USER=you GITHUB_TOKEN=ghp_xxx ./setup_and_test.sh   # all tests
#
# Individual test files:
#   bats test/validation.bats    # input validation, no Docker
#   bats test/strategy.bats      # clone, mirror pull, mirror push
#   bats test/visibility.bats    # public, private, both
#   bats test/options.bats       # dry-run, forks, archive, sort, force-sync

set -e

echo "=== Validation tests (no Docker) ==="
bats test/validation.bats

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
	echo ""
	echo "GITHUB_USER or GITHUB_TOKEN not set — skipping E2E tests."
	echo "To run all tests: GITHUB_USER=you GITHUB_TOKEN=ghp_xxx $0"
	exit 0
fi

echo ""
echo "=== E2E: strategy ==="
bats test/strategy.bats

echo ""
echo "=== E2E: visibility ==="
bats test/visibility.bats

echo ""
echo "=== E2E: options ==="
bats test/options.bats

echo ""
echo "=== All tests passed ==="
