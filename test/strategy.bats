#!/usr/bin/env bats
# strategy.bats — E2E tests for STRATEGY and MIRROR_DIRECTION
#
# Requires: GITHUB_USER, GITHUB_TOKEN, Docker
# Assumes: test user has at least one public repo

setup_file() {
	source "$BATS_TEST_DIRNAME/helpers/forgejo.bash"
	forgejo_start
}

teardown_file() {
	source "$BATS_TEST_DIRNAME/helpers/forgejo.bash"
	forgejo_stop
}

migrate_env() {
	export STRATEGY="${STRATEGY:-clone}"
	export MIRROR_DIRECTION="${MIRROR_DIRECTION:-pull}"
	export DRY_RUN=No
	export FORCE_SYNC=No
	export MIGRATE_ARCHIVE_STATUS=No
	export MIGRATE_FORKS=No
	export VISIBILITY=public
	export SORT=pushed
	export SORT_DIRECTION=desc
	export PUSH_MIRROR_INTERVAL=8h
	export PUSH_MIRROR_SYNC_ON_COMMIT=Yes
}

@test "clone: migrates repos as one-time copy (mirror=false)" {
	forgejo_cleanup_repos
	migrate_env
	export STRATEGY=clone

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	repo_name=$(forgejo_first_repo_name)
	[ -n "$repo_name" ] && [ "$repo_name" != "null" ]

	is_mirror=$(forgejo_repo_field "$repo_name" '.mirror')
	[ "$is_mirror" = "false" ]
}

@test "mirror pull: migrates repos as pull mirrors (mirror=true)" {
	forgejo_cleanup_repos
	migrate_env
	export STRATEGY=mirror MIRROR_DIRECTION=pull

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	repo_name=$(forgejo_first_repo_name)
	[ -n "$repo_name" ] && [ "$repo_name" != "null" ]

	is_mirror=$(forgejo_repo_field "$repo_name" '.mirror')
	[ "$is_mirror" = "true" ]
}

@test "mirror push: clones repo and sets up push mirror to GitHub" {
	forgejo_cleanup_repos
	migrate_env
	export STRATEGY=mirror MIRROR_DIRECTION=push

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	repo_name=$(forgejo_first_repo_name)
	[ -n "$repo_name" ] && [ "$repo_name" != "null" ]

	# Repo is NOT a pull mirror — it's writable
	is_mirror=$(forgejo_repo_field "$repo_name" '.mirror')
	[ "$is_mirror" = "false" ]

	# Push mirror is configured pointing back to GitHub
	push_mirrors=$(forgejo_push_mirrors "$repo_name")
	pm_count=$(echo "$push_mirrors" | jq 'length')
	[ "$pm_count" -ge 1 ]
}
