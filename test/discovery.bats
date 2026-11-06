#!/usr/bin/env bats
# GitHub listing regression tests; no network or Forgejo instance required.

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../github-forgejo-migrate.sh"
	export GITHUB_USER=other GITHUB_IS_ORG=No GITHUB_TOKEN=fake-token
	export FORGEJO_URL=http://localhost:3000 FORGEJO_USER=backup FORGEJO_TOKEN=fake-token
	export STRATEGY=mirror MIRROR_DIRECTION=pull DRY_RUN=Yes FORCE_SYNC=No
	export MIGRATE_ARCHIVE_STATUS=No MIGRATE_FORKS=Yes VISIBILITY=both
	export SORT=pushed SORT_DIRECTION=desc

	# Emulate an authenticated account with one private collaboration and one
	# overlapping public repo, plus another public repo owned by `other`.
	curl() {
		case "${*: -1}" in
			*'/user/repos?'*)
				printf '%s\n' '[{"id":1,"name":"private","full_name":"other/private","html_url":"https://github.com/other/private","owner":{"login":"other"},"private":true,"archived":false,"fork":false},{"id":2,"name":"shared","full_name":"other/shared","html_url":"https://github.com/other/shared","owner":{"login":"other"},"private":false,"archived":false,"fork":false},{"id":4,"name":"mine","owner":{"login":"me"},"private":false}]'
				;;
			*'/users/other/repos?'*)
				printf '%s\n' '[{"id":2,"name":"shared","full_name":"other/shared","html_url":"https://github.com/other/shared","owner":{"login":"other"},"private":false,"archived":false,"fork":false},{"id":3,"name":"public","full_name":"other/public","html_url":"https://github.com/other/public","owner":{"login":"other"},"private":false,"archived":false,"fork":false}]'
				;;
			*) printf '[]\n' ;;
		esac
	}
	export -f curl
}

@test "authenticated listing includes another user's public and private repos without duplicates" {
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(grep -c '\[DRY RUN\] Would migrate:' <<< "$output")" -eq 3 ]
	[[ "$output" == *'Would migrate: private'* ]]
	[[ "$output" == *'Would migrate: shared'* ]]
	[[ "$output" == *'Would migrate: public'* ]]
	[[ "$output" != *'Would migrate: mine'* ]]
}

@test "sort order is preserved across both listings" {
	export SORT=full_name SORT_DIRECTION=asc
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	names=$(grep -oE 'Would migrate: [[:alnum:]_-]+' <<< "$output" | awk '{print $3}' | tr '\n' ' ')
	[ "$names" = 'private public shared ' ]
}

@test "visibility filters the combined listing" {
	export VISIBILITY=private
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(grep -c '\[DRY RUN\] Would migrate:' <<< "$output")" -eq 1 ]
	[[ "$output" == *'Would migrate: private'* ]]

	export VISIBILITY=public
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(grep -c '\[DRY RUN\] Would migrate:' <<< "$output")" -eq 2 ]
}

@test "without a token the public user listing still works" {
	export GITHUB_TOKEN=''
	run bash "$SCRIPT" </dev/null
	[ "$status" -eq 0 ]
	[ "$(grep -c '\[DRY RUN\] Would migrate:' <<< "$output")" -eq 2 ]
}
