#!/bin/bash
# This script migrates a GitHub user's repositories to a Forgejo instance.
# It requires curl and jq to be installed.
# Environment variables (if not provided, you will be prompted):
#   GITHUB_USER: The GitHub username.
#   GITHUB_IS_ORG: Whether the GitHub user is an organization (Yes/No).
#   GITHUB_TOKEN: An access token for private GitHub repositories (optional).
#   FORGEJO_URL: The Forgejo instance URL (include the protocol, e.g. https://forgejo.example.com).
#   FORGEJO_USER: The Forgejo user/organization to migrate to.
#   FORGEJO_TOKEN: A Forgejo access token.
#   STRATEGY: Either "mirror" or "clone". "mirrored" will create a mirror (which Forgejo will update periodically),
#             "clone" will only clone once.
#   FORCE_SYNC: Whether to delete repositories on Forgejo that no longer exist on GitHub.
#              Answer Yes (to delete) or No.

# Define some color codes for output.
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 6)
purple=$(tput setaf 5)
white=$(tput setaf 7)
reset=$(tput sgr0)

# Additional check to verify commands are installed as described in the documentation.
command_exists() {
	if command -v "$1" >/dev/null 2>&1; then
		printf "%sChecking Prerequisite: %s is: Installed!\n" "$green" "$1"
	else
		printf "${yellow}%b$1 is not installed...%b\n"
		exit 1
	fi
}

# Function: Wraps curl to validate exit code and non-empty response.
# Parameters:
#   $@ - All arguments are passed to curl
# Output: curl stdout (response body)
# Returns 0 on success (prints response to stdout), 1 on failure. Caller prints error message.
safe_curl() {
	local response
	local curl_exit_code

	response=$(curl -sS "$@")
	curl_exit_code=$?

	if [ $curl_exit_code -ne 0 ]; then
		return 1
	fi

	if [ -z "$response" ]; then
		return 1
	fi

	echo "$response"
}

command_exists bash
command_exists curl
command_exists jq

# Function: if the passed variable is empty, prompt the user.
# The function trims white space from the input.
# Two display strings are provided:
#   prompt_msg: The prompt to display (this can include color codes)
#   default_value: A plain default value that will be used if the user enters nothing.
#   is_secret: (Optional) If set to true/yes, the input will be hidden and the output masked.
or_default() {
	local current_val="$1"
	local prompt_msg="$2"
	local default_value="$3"
	local is_secret="$4"
	local input_val

	# Normalize is_secret
	if [[ "$is_secret" =~ ^[Yy] ]]; then
		is_secret=true
	else
		is_secret=false
	fi

	# If the variable is already set, notify the user and return that value.
	if [ -n "$current_val" ]; then
		local display_val="$current_val"
		if [ "$is_secret" = true ]; then
			if [ ${#current_val} -gt 5 ]; then
				display_val="...${current_val: -5}"
			else
				display_val="*****"
			fi
		fi
		printf "%b found in environment, using: %s%b\n" "${cyan}${prompt_msg}" "$display_val" "${reset}" >&2
		echo "$current_val"
		return
	fi

	# Prompt the user.
	if [ "$is_secret" = true ]; then
		# Silent input for secrets
		printf "%s " "$prompt_msg" >&2
		read -r -s input_val
		echo "" >&2 # Newline after silent input
	else
		read -r -p "$prompt_msg " input_val
	fi

	# Trim any extraneous whitespace.
	input_val="$(echo "$input_val" | xargs)"

	if [ -z "$input_val" ] && [ -n "$default_value" ]; then
		input_val="$default_value"
		local display_default="$default_value"
		if [ "$is_secret" = true ]; then
			if [ ${#default_value} -gt 5 ]; then
				display_default="...${default_value: -5}"
			else
				display_default="*****"
			fi
		fi
		printf "%bNo input provided. Using default: %s%b\n" "${cyan}" "$display_default" "${reset}" >&2
	fi

	echo "$input_val"
}

# Get configuration from the environment or via prompt.
GITHUB_USER=$(or_default "$GITHUB_USER" "${red}GitHub username:${reset}" "")
if [ -z "$GITHUB_USER" ]; then
	echo -e "${red}Error: GITHUB_USER is required.${reset}" >&2
	exit 1
fi

# Auto-detect GITHUB_IS_ORG if not provided
if [ -z "$GITHUB_IS_ORG" ]; then
	echo -ne "${cyan}Checking account type for $GITHUB_USER...${reset}"
	# Use token if available to avoid rate limits
	curl_args=()
	if [ -n "$GITHUB_TOKEN" ]; then
		curl_args+=(-H "Authorization: token $GITHUB_TOKEN")
	fi

	api_response=$(safe_curl "${curl_args[@]}" "https://api.github.com/users/$GITHUB_USER") || {
		echo -e " ${red}Failed to reach GitHub API. Check network connectivity.${reset}" >&2
		exit 1
	}
	account_type=$(echo "$api_response" | jq -r '.type')

	if [[ "$account_type" == "Organization" ]]; then
		GITHUB_IS_ORG=true
		echo -e " ${green}Organization detected.${reset}"
	else
		GITHUB_IS_ORG=false
		echo -e " ${green}User detected.${reset}"
	fi
else
	printf "%b found in environment, using: %s%b\n" "${cyan}Is the GitHub user an organization? (Yes/No):${reset}" "$GITHUB_IS_ORG" "${reset}" >&2
	# Clean up user input if provided manually
	GITHUB_IS_ORG="$(echo "$GITHUB_IS_ORG" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
	if [[ "$GITHUB_IS_ORG" =~ ^y(es)?$ ]] || [[ "$GITHUB_IS_ORG" == "true" ]]; then
		GITHUB_IS_ORG=true
	else
		GITHUB_IS_ORG=false
	fi
fi

GITHUB_TOKEN=$(or_default "$GITHUB_TOKEN" "${red}GitHub access token (optional, only used for private repositories):${reset}" "" "yes")
FORGEJO_URL=$(or_default "$FORGEJO_URL" "${green}Forgejo instance URL (with https://):${reset}" "")
# Remove any trailing slash.
FORGEJO_URL="${FORGEJO_URL%/}"
FORGEJO_USER=$(or_default "$FORGEJO_USER" "${green}Forgejo username or organization to migrate to:${reset}" "")
FORGEJO_TOKEN=$(or_default "$FORGEJO_TOKEN" "${green}Forgejo access token:${reset}" "" "yes")
STRATEGY=$(or_default "$STRATEGY" "${cyan}Strategy (mirror/clone):${reset}" "mirror")

# Convert STRATEGY to lowercase so input variations are handled.
STRATEGY="$(echo "$STRATEGY" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"

# Validate STRATEGY input.
if [[ "$STRATEGY" != "mirror" && "$STRATEGY" != "clone" ]]; then
	echo -e "${red}Error: Strategy must be either 'mirror' or 'clone'.${reset}" >&2
	exit 1
fi
# Get the FORCE_SYNC setting from the environment or via prompt.
FORCE_SYNC=$(or_default "$FORCE_SYNC" "${yellow}Should mirrored repos that don't have a GitHub source anymore be deleted? (Yes/No):${reset}" "No")

# Clean up FORCE_SYNC input by removing newlines and converting to lowercase.
FORCE_SYNC="$(echo "$FORCE_SYNC" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"

# Convert response to a boolean: true if the answer is yes (starting with "y"), false otherwise.
if [[ "$FORCE_SYNC" =~ ^y(es)?$ ]]; then
	FORCE_SYNC=true
else
	FORCE_SYNC=false
fi

# Get the MIGRATE_ARCHIVE_STATUS setting from the environment or via prompt.
MIGRATE_ARCHIVE_STATUS=$(or_default "$MIGRATE_ARCHIVE_STATUS" "${yellow}Should the archive status of repositories be transferred? (Yes/No):${reset}" "Yes")

# Clean up MIGRATE_ARCHIVE_STATUS input.
MIGRATE_ARCHIVE_STATUS="$(echo "$MIGRATE_ARCHIVE_STATUS" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"

if [[ "$MIGRATE_ARCHIVE_STATUS" =~ ^y(es)?$ ]]; then
	MIGRATE_ARCHIVE_STATUS=true
else
	MIGRATE_ARCHIVE_STATUS=false
fi

# Get the MIGRATE_FORKS setting from the environment or via prompt.
MIGRATE_FORKS=$(or_default "$MIGRATE_FORKS" "${yellow}Should fork repositories be migrated? (Yes/No):${reset}" "Yes")

# Clean up MIGRATE_FORKS input.
MIGRATE_FORKS="$(echo "$MIGRATE_FORKS" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"

if [[ "$MIGRATE_FORKS" =~ ^y(es)?$ ]]; then
	MIGRATE_FORKS=true
else
	MIGRATE_FORKS=false
fi

# Get the DRY_RUN setting from the environment or via prompt.
DRY_RUN=$(or_default "$DRY_RUN" "${yellow}Preview actions without executing (dry run)? (Yes/No):${reset}" "No")

# Clean up DRY_RUN input.
DRY_RUN="$(echo "$DRY_RUN" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"

if [[ "$DRY_RUN" =~ ^y(es)?$ ]]; then
	DRY_RUN=true
else
	DRY_RUN=false
fi

echo -e "${green}Force sync is set to: ${FORCE_SYNC}${reset}"
echo -e "${green}Migrate archive status is set to: ${MIGRATE_ARCHIVE_STATUS}${reset}"
echo -e "${green}Migrate forks is set to: ${MIGRATE_FORKS}${reset}"
echo -e "${green}Dry run is set to: ${DRY_RUN}${reset}"

if $DRY_RUN; then
	echo -e "${cyan}=== DRY RUN MODE ===${reset}"
	echo -e "${cyan}No changes will be made. Previewing actions only.${reset}"
fi

# -------------------------
# 1. Fetch GitHub Repositories via API (paginated)
# -------------------------
all_repos="[]" # will hold a JSON array of repos
page=1

# Determine API endpoint and headers once
repo_base_url="https://api.github.com/users/$GITHUB_USER/repos"
curl_opts=()

# Use authenticated user endpoint if token exists (and not overridden by Org)
if [ -n "$GITHUB_TOKEN" ]; then
	curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
	repo_base_url="https://api.github.com/user/repos"
fi

# If Organization, force Org endpoint
if $GITHUB_IS_ORG; then
	repo_base_url="https://api.github.com/orgs/$GITHUB_USER/repos"
fi

while true; do
	response=$(safe_curl "${curl_opts[@]}" "$repo_base_url?per_page=100&page=$page") || {
		echo -e "${red}Failed to fetch GitHub repositories. Check network connectivity.${reset}" >&2
		exit 1
	}

	# Check for API error messages
	if echo "$response" | jq -e 'if type == "object" and .message then true else false end' >/dev/null; then
		err_msg=$(echo "$response" | jq -r '.message')
		echo -e "${red}GitHub API Error: $err_msg${reset}" >&2
		exit 1
	fi

	# Filter repos so that only those whose owner.login matches GITHUB_USER are selected.
	filtered=$(echo "$response" | jq --arg gu "$GITHUB_USER" 'if type == "array" then [.[] | select(.owner.login == $gu)] else [] end')
	count=$(echo "$filtered" | jq 'length')
	if [ "$count" -eq 0 ]; then
		break
	fi
	# Merge this page with the existing JSON array:
	all_repos=$(echo "$all_repos" "$filtered" | jq -s 'add')
	# If we received less than 100 repos, we're done.
	if [ "$count" -lt 100 ]; then
		break
	fi
	page=$((page + 1))
done

# -------------------------
# 2. (Optional) Force sync: Delete Forgejo repos that are mirrored but no longer exist on GitHub.
# -------------------------
if $FORCE_SYNC; then
	# Get GitHub repo names into a plain list.
	github_repo_names=$(echo "$all_repos" | jq -r '.[].name')

	# Fetch Forgejo repos.
	forgejo_response=$(safe_curl -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/user/repos") || {
		echo -e "${red}Failed to fetch Forgejo repositories. Check FORGEJO_URL and network connectivity.${reset}" >&2
		exit 1
	}

	# Filter to only those repos created via mirror; if no GitHub token provided, also filter out private repos.
	if [ -z "$GITHUB_TOKEN" ]; then
		forgejo_mirrored=$(echo "$forgejo_response" | jq '[.[] | select(.mirror == true and .private == false)]')
	else
		forgejo_mirrored=$(echo "$forgejo_response" | jq '[.[] | select(.mirror == true)]')
	fi

	count_forgejo=$(echo "$forgejo_mirrored" | jq 'length')
	if [ "$count_forgejo" -gt 0 ]; then
		# Iterate over each Forgejo mirrored repo.
		echo "$forgejo_mirrored" | jq -c '.[]' | while read -r repo; do
			repo_name=$(echo "$repo" | jq -r '.name')
			full_name=$(echo "$repo" | jq -r '.full_name')
			# If this repo name is not present in the GitHub repos list, delete it.
			if ! echo "$github_repo_names" | grep -Fxq "$repo_name"; then
				if ! $DRY_RUN; then
					echo -ne "${red}Deleting ${yellow}$FORGEJO_URL/$full_name${red} because the mirror source doesn't exist on GitHub anymore...${reset}"
					delete_response=$(curl -sS -w "%{http_code}" -o /dev/null -X DELETE -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/repos/$full_name")
					delete_exit_code=$?
					if [ $delete_exit_code -ne 0 ]; then
						echo -e " ${red}Failed (network error, curl exit code $delete_exit_code).${reset}"
					elif [ "$delete_response" -ge 200 ] && [ "$delete_response" -lt 300 ]; then
						echo -e " ${green}Success!${reset}"
					else
						echo -e " ${red}Failed (HTTP $delete_response).${reset}"
					fi
				else
					echo -e "${cyan}[DRY RUN] Would delete: $FORGEJO_URL/$full_name${reset}"
				fi
			fi
		done
	fi
fi

# -------------------------
# 3. Migrate each GitHub repository to Forgejo.
# -------------------------
repo_count=$(echo "$all_repos" | jq 'length')
if [ "$repo_count" -eq 0 ]; then
	echo "No repositories found for user $GITHUB_USER."
	exit 0
fi

# Process each GitHub repo
echo "$all_repos" | jq -c '.[]' | while read -r repo; do
	repo_name=$(echo "$repo" | jq -r '.name')
	html_url=$(echo "$repo" | jq -r '.html_url')
	private_flag=$(echo "$repo" | jq -r '.private')
	archived_flag=$(echo "$repo" | jq -r '.archived')
	full_name=$(echo "$repo" | jq -r '.full_name')
	fork_flag=$(echo "$repo" | jq -r '.fork')

	# Skip forked repos if MIGRATE_FORKS is false
	if [ "$fork_flag" = "true" ] && [ "$MIGRATE_FORKS" = false ]; then
		echo -e "${yellow}Skipping fork: ${white}$repo_name${reset}"
		continue
	fi

	# Prepare status message.
	# Capitalize the strategy for display.
	strategy_display="$(tr '[:lower:]' '[:upper:]' <<<"${STRATEGY:0:1}")${STRATEGY:1}"
	if [ "$private_flag" = "true" ]; then
		access_type="${red}private${reset}"
	else
		access_type="${green}public${reset}"
	fi
	echo -ne "${blue}${strategy_display}ing ${access_type} repository ${purple}$html_url${blue} to ${white}$FORGEJO_URL/$FORGEJO_USER/$repo_name${blue}...${reset}"

	# Determine which clone address to use.
	if [ "$private_flag" = "true" ]; then
		if [ -z "$GITHUB_TOKEN" ]; then
			echo -e " ${red}Error: Private repo but no GitHub token provided!${reset}"
			continue
		fi
	fi
	# Always use the standard URL; authentication is passed via auth_token in the payload.
	github_repo_url="$html_url"

	# Set mirror flag for the migration API:
	if [ "$STRATEGY" = "clone" ]; then
		mirror=false
	else
		mirror=true
	fi

	# Build the JSON payload.
	payload=$(jq -n \
		--arg addr "$github_repo_url" \
		--argjson mirror "$mirror" \
		--argjson private "$private_flag" \
		--arg owner "$FORGEJO_USER" \
		--arg repo "$repo_name" \
		--arg auth_token "$GITHUB_TOKEN" \
		'{clone_addr: $addr, mirror: $mirror, private: $private, repo_owner: $owner, repo_name: $repo, auth_token: (if $auth_token != "" then $auth_token else null end)}')

	if ! $DRY_RUN; then
		# Send the POST request to the Forgejo migration endpoint.
		response=$(safe_curl -H "Content-Type: application/json" -H "Authorization: token $FORGEJO_TOKEN" -d "$payload" "$FORGEJO_URL/api/v1/repos/migrate") || {
			echo -e " ${red}Migration request failed.${reset}"
			continue
		}
		error_message=$(echo "$response" | jq -r '.message // empty')

		success=false
		if [[ "$error_message" == *"already exists"* ]]; then
			echo -e " ${yellow}Already exists!${reset}"
			success=true
		elif [ -n "$error_message" ]; then
			echo -e " ${red}Unknown error: $error_message${reset}"
		else
			echo -e " ${green}Success!${reset}"
			success=true
		fi
	else
		echo -e "\n${cyan}[DRY RUN] Would migrate: $repo_name${reset}"
		success=true
	fi

	# If migration succeeded (or already existed) and the repo is archived on GitHub,
	# and the user wants to transfer archive status, patch the Forgejo repo.
	if [ "$success" = true ] && [ "$archived_flag" = "true" ] && [ "$MIGRATE_ARCHIVE_STATUS" = true ]; then
		if [ "$mirror" = true ]; then
			echo -e "  ${yellow}Skipping archive status transfer (not supported for mirrors).${reset}"
		else
			if ! $DRY_RUN; then
				echo -ne "  ${yellow}Archiving repository on Forgejo...${reset}"
				patch_payload='{"archived": true}'
				if ! patch_response=$(safe_curl -X PATCH -H "Content-Type: application/json" -H "Authorization: token $FORGEJO_TOKEN" -d "$patch_payload" "$FORGEJO_URL/api/v1/repos/$FORGEJO_USER/$repo_name"); then
					echo -e " ${red}Archive request failed.${reset}"
				else
					patch_error=$(echo "$patch_response" | jq -r '.message // empty')
					if [ -n "$patch_error" ]; then
						echo -e " ${red}Error: $patch_error${reset}"
					else
						echo -e " ${green}Done!${reset}"
					fi
				fi
			else
				echo -e " ${cyan}[DRY RUN] Would archive: $repo_name${reset}"
			fi
		fi
	fi
done
