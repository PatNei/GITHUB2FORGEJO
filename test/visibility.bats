#!/usr/bin/env bats
# visibility.bats — E2E tests for VISIBILITY filtering
#
# Requires: GITHUB_USER, GITHUB_TOKEN, Docker
# Assumes: test user has both public and private repos

setup_file() {
	source "$BATS_TEST_DIRNAME/helpers/forgejo.bash"
	forgejo_start
}

teardown_file() {
	source "$BATS_TEST_DIRNAME/helpers/forgejo.bash"
	forgejo_stop
}

migrate_env() {
	export STRATEGY=clone
	export MIRROR_DIRECTION=pull
	export DRY_RUN=No
	export FORCE_SYNC=No
	export MIGRATE_ARCHIVE_STATUS=No
	export MIGRATE_FORKS=No
	export VISIBILITY="${VISIBILITY:-public}"
	export SORT=pushed
	export SORT_DIRECTION=desc
	export PUSH_MIRROR_INTERVAL=8h
	export PUSH_MIRROR_SYNC_ON_COMMIT=Yes
}

@test "visibility=public: only migrates public repos" {
	forgejo_cleanup_repos
	migrate_env
	export VISIBILITY=public

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	count=$(forgejo_repo_count)
	[ "$count" -ge 1 ]

	# Every migrated repo must be public
	while IFS= read -r name; do
		private=$(forgejo_repo_field "$name" '.private')
		[ "$private" = "false" ]
	done < <(forgejo_repo_names)
}

@test "visibility=private: only migrates private repos" {
	forgejo_cleanup_repos
	migrate_env
	export VISIBILITY=private

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	count=$(forgejo_repo_count)
	[ "$count" -ge 1 ]

	# Every migrated repo must be private
	while IFS= read -r name; do
		private=$(forgejo_repo_field "$name" '.private')
		[ "$private" = "true" ]
	done < <(forgejo_repo_names)
}

@test "visibility=both: migrates public and private repos" {
	forgejo_cleanup_repos
	migrate_env
	export VISIBILITY=both

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	count=$(forgejo_repo_count)
	[ "$count" -ge 2 ]

	# Should have at least one public and one private repo
	found_public=false
	found_private=false
	while IFS= read -r name; do
		private=$(forgejo_repo_field "$name" '.private')
		if [ "$private" = "true" ]; then found_private=true
		else found_public=true
		fi
	done < <(forgejo_repo_names)

	[ "$found_public" = "true" ]
	[ "$found_private" = "true" ]
}
