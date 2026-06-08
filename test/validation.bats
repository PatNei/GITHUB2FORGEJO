#!/usr/bin/env bats
# validation.bats — Test input validation and settings summary of the migration script.
# These tests do NOT need Docker or a Forgejo instance.
# They use a fake token so the script will fail at the GitHub API call,
# but that's after all validation — we check the output regardless.

SCRIPT="$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"

# Common env vars. The fake token means the GitHub API call will fail,
# but validation happens before that. We check output + early-exit code
# for reject cases, and just output for accept cases.
setup() {
	export GITHUB_USER=testuser
	export GITHUB_TOKEN=faketoken
	export FORGEJO_URL=http://localhost:3000
	export FORGEJO_USER=testuser
	export FORGEJO_TOKEN=faketoken
	export DRY_RUN=Yes
	export STRATEGY=clone
	export MIRROR_DIRECTION=pull
	export VISIBILITY=both
	export SORT=pushed
	export SORT_DIRECTION=desc
	export FORCE_SYNC=No
	export MIGRATE_ARCHIVE_STATUS=Yes
	export MIGRATE_FORKS=Yes
	export PUSH_MIRROR_INTERVAL=8h
	export PUSH_MIRROR_SYNC_ON_COMMIT=Yes
}

# ---- STRATEGY validation ----

@test "rejects invalid STRATEGY" {
	export STRATEGY=invalid
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Strategy must be either 'mirror' or 'clone'"* ]]
}

@test "accepts STRATEGY=mirror (passes validation)" {
	export STRATEGY=mirror MIRROR_DIRECTION=pull
	run bash "$SCRIPT"
	# May fail later at GitHub API, but should NOT have strategy error
	[[ "$output" != *"Strategy must be either 'mirror' or 'clone'"* ]]
}

@test "accepts STRATEGY=clone (passes validation)" {
	export STRATEGY=clone
	run bash "$SCRIPT"
	[[ "$output" != *"Strategy must be either 'mirror' or 'clone'"* ]]
}

@test "STRATEGY is case-insensitive (MIRROR)" {
	export STRATEGY=MIRROR MIRROR_DIRECTION=pull
	run bash "$SCRIPT"
	[[ "$output" != *"Strategy must be either 'mirror' or 'clone'"* ]]
}

# ---- MIRROR_DIRECTION validation ----

@test "rejects invalid MIRROR_DIRECTION" {
	export STRATEGY=mirror MIRROR_DIRECTION=sideways
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"MIRROR_DIRECTION must be either 'pull' or 'push'"* ]]
}

@test "accepts MIRROR_DIRECTION=pull" {
	export STRATEGY=mirror MIRROR_DIRECTION=pull
	run bash "$SCRIPT"
	[[ "$output" != *"MIRROR_DIRECTION must be either 'pull' or 'push'"* ]]
}

@test "accepts MIRROR_DIRECTION=push" {
	export STRATEGY=mirror MIRROR_DIRECTION=push
	run bash "$SCRIPT"
	[[ "$output" != *"MIRROR_DIRECTION must be either 'pull' or 'push'"* ]]
}

@test "MIRROR_DIRECTION defaults to pull when unset" {
	export STRATEGY=mirror
	unset MIRROR_DIRECTION
	run bash "$SCRIPT"
	[[ "$output" == *"Mirror direction is set to: pull"* ]]
}

@test "MIRROR_DIRECTION is case-insensitive (PULL)" {
	export STRATEGY=mirror MIRROR_DIRECTION=PULL
	run bash "$SCRIPT"
	[[ "$output" != *"MIRROR_DIRECTION must be either 'pull' or 'push'"* ]]
}

# ---- MIRROR_DIRECTION=push requires GITHUB_TOKEN ----

@test "MIRROR_DIRECTION=push fails without GITHUB_TOKEN" {
	export STRATEGY=mirror MIRROR_DIRECTION=push GITHUB_TOKEN=""
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"MIRROR_DIRECTION=push requires GITHUB_TOKEN"* ]]
}

# ---- VISIBILITY validation ----

@test "rejects invalid VISIBILITY" {
	export VISIBILITY=everything
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"VISIBILITY must be 'private', 'public', or 'both'"* ]]
}

@test "accepts VISIBILITY=private" {
	export VISIBILITY=private
	run bash "$SCRIPT"
	[[ "$output" != *"VISIBILITY must be"* ]]
}

@test "accepts VISIBILITY=public" {
	export VISIBILITY=public
	run bash "$SCRIPT"
	[[ "$output" != *"VISIBILITY must be"* ]]
}

@test "accepts VISIBILITY=both" {
	export VISIBILITY=both
	run bash "$SCRIPT"
	[[ "$output" != *"VISIBILITY must be"* ]]
}

# ---- SORT validation ----

@test "rejects invalid SORT" {
	export SORT=invalid
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"SORT must be 'created', 'updated', 'pushed', or 'full_name'"* ]]
}

@test "accepts SORT=created" {
	export SORT=created
	run bash "$SCRIPT"
	[[ "$output" != *"SORT must be one of"* ]]
}

@test "accepts SORT=updated" {
	export SORT=updated
	run bash "$SCRIPT"
	[[ "$output" != *"SORT must be one of"* ]]
}

@test "accepts SORT=pushed" {
	export SORT=pushed
	run bash "$SCRIPT"
	[[ "$output" != *"SORT must be one of"* ]]
}

@test "accepts SORT=full_name" {
	export SORT=full_name
	run bash "$SCRIPT"
	[[ "$output" != *"SORT must be one of"* ]]
}

# ---- SORT_DIRECTION validation ----

@test "rejects invalid SORT_DIRECTION" {
	export SORT_DIRECTION=sideways
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"SORT_DIRECTION must be 'asc' or 'desc'"* ]]
}

@test "accepts SORT_DIRECTION=asc" {
	export SORT_DIRECTION=asc
	run bash "$SCRIPT"
	[[ "$output" != *"SORT_DIRECTION must be either"* ]]
}

@test "accepts SORT_DIRECTION=desc" {
	export SORT_DIRECTION=desc
	run bash "$SCRIPT"
	[[ "$output" != *"SORT_DIRECTION must be either"* ]]
}

# ---- PUSH_MIRROR_SYNC_ON_COMMIT parsing ----

@test "PUSH_MIRROR_SYNC_ON_COMMIT=Yes maps to true" {
	export STRATEGY=mirror MIRROR_DIRECTION=push PUSH_MIRROR_SYNC_ON_COMMIT=Yes
	run bash "$SCRIPT"
	[[ "$output" == *"Push mirror sync on commit is set to: true"* ]]
}

@test "PUSH_MIRROR_SYNC_ON_COMMIT=No maps to false" {
	export STRATEGY=mirror MIRROR_DIRECTION=push PUSH_MIRROR_SYNC_ON_COMMIT=No
	run bash "$SCRIPT"
	[[ "$output" == *"Push mirror sync on commit is set to: false"* ]]
}

# ---- Settings echo summary ----

@test "echoes mirror direction for mirror pull" {
	export STRATEGY=mirror MIRROR_DIRECTION=pull
	run bash "$SCRIPT"
	[[ "$output" == *"Mirror direction is set to: pull"* ]]
}

@test "echoes mirror direction and interval for mirror push" {
	export STRATEGY=mirror MIRROR_DIRECTION=push PUSH_MIRROR_INTERVAL=1h
	run bash "$SCRIPT"
	[[ "$output" == *"Mirror direction is set to: push"* ]]
	[[ "$output" == *"Push mirror interval is set to: 1h"* ]]
}

@test "does not echo mirror direction for clone strategy" {
	export STRATEGY=clone
	run bash "$SCRIPT"
	[[ "$output" != *"Mirror direction is set to"* ]]
}

@test "warns when MIRROR_DIRECTION=push but STRATEGY=clone" {
	export STRATEGY=clone MIRROR_DIRECTION=push
	run bash "$SCRIPT"
	[[ "$output" == *"MIRROR_DIRECTION is ignored when STRATEGY is not 'mirror'"* ]]
}

# ---- Sort settings echo ----

@test "echoes sort setting with direction" {
	export SORT=updated SORT_DIRECTION=asc
	run bash "$SCRIPT"
	[[ "$output" == *"Sort is set to: updated (asc)"* ]]
}

@test "default sort is pushed desc" {
	unset SORT SORT_DIRECTION
	run bash "$SCRIPT"
	[[ "$output" == *"Sort is set to: pushed (desc)"* ]]
}
