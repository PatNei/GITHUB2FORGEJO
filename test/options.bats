#!/usr/bin/env bats
# options.bats — E2E tests for migration options
#
# Requires: GITHUB_USER, GITHUB_TOKEN, Docker
# Assumes: test user has public repos, forked repos, and archived repos

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
	export VISIBILITY=public
	export SORT=pushed
	export SORT_DIRECTION=desc
	export PUSH_MIRROR_INTERVAL=8h
	export PUSH_MIRROR_SYNC_ON_COMMIT=Yes
}

# ---- DRY_RUN ----

@test "dry run: previews migration without creating any repos" {
	forgejo_cleanup_repos
	migrate_env
	export DRY_RUN=Yes

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"[DRY RUN]"* ]]

	count=$(forgejo_repo_count)
	[ "$count" -eq 0 ]
}

# ---- MIGRATE_FORKS ----

@test "forks=No: skips forked repos" {
	forgejo_cleanup_repos
	migrate_env
	export MIGRATE_FORKS=No

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	# No migrated repo should be a fork
	while IFS= read -r name; do
		is_fork=$(forgejo_repo_field "$name" '.fork')
		[ "$is_fork" = "false" ]
	done < <(forgejo_repo_names)
}

@test "forks=Yes: includes forked repos" {
	forgejo_cleanup_repos
	migrate_env
	export MIGRATE_FORKS=Yes

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	# At least one repo should be a fork
	found_fork=false
	while IFS= read -r name; do
		is_fork=$(forgejo_repo_field "$name" '.fork')
		if [ "$is_fork" = "true" ]; then
			found_fork=true
			break
		fi
	done < <(forgejo_repo_names)
	[ "$found_fork" = "true" ]
}

# ---- MIGRATE_ARCHIVE_STATUS ----

@test "archive status=Yes: archived GitHub repos are archived on Forgejo" {
	forgejo_cleanup_repos
	migrate_env
	export MIGRATE_ARCHIVE_STATUS=Yes

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	# Each migrated repo's archived flag must match GitHub
	while IFS= read -r name; do
		gh_archived=$(curl -sf "https://api.github.com/repos/$GITHUB_USER/$name" | jq -r '.archived // false')
		fj_archived=$(forgejo_repo_field "$name" '.archived')
		[ "$gh_archived" = "$fj_archived" ]
	done < <(forgejo_repo_names)
}

# ---- SORT order ----

@test "sort=pushed desc: repos are migrated in pushed-descending order" {
	forgejo_cleanup_repos
	migrate_env
	export SORT=pushed SORT_DIRECTION=desc

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	# Get the order GitHub returns for pushed+desc
	mapfile -t gh_list < <(curl -sf \
		"https://api.github.com/users/$GITHUB_USER/repos?per_page=100&sort=pushed&direction=desc" \
		| jq -r '.[].name')

	mapfile -t migrated < <(forgejo_repo_names)

	# Migrated repos must appear in the same relative order as GitHub's pushed-desc
	prev_idx=-1
	for repo in "${migrated[@]}"; do
		for ((i = 0; i < ${#gh_list[@]}; i++)); do
			if [ "$repo" = "${gh_list[$i]}" ]; then
				[ "$i" -ge "$prev_idx" ]
				prev_idx=$i
				break
			fi
		done
	done
}

# ---- FORCE_SYNC ----

@test "force sync: deletes Forgejo repos that don't exist on GitHub" {
	# Seed a fake repo on Forgejo that has no GitHub counterpart
	forgejo_create_repo "force-sync-test-repo-not-on-github" false "test"
	forgejo_repo_exists "force-sync-test-repo-not-on-github"

	migrate_env
	export FORCE_SYNC=Yes

	run bash "$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	[ "$status" -eq 0 ]

	# The fake repo must have been deleted
	! forgejo_repo_exists "force-sync-test-repo-not-on-github"
}
