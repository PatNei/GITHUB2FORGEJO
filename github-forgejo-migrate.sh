#!/bin/bash
# This script migrates a GitHub user's repositories to a Forgejo instance.
# It requires curl and jq to be installed.
# Environment variables (if not provided, you will be prompted):
#   GITHUB_USER: The GitHub username.
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
        printf "${green}Checking Prerequisite: $1 is: Installed!\n"
    else
        printf "${yellow}%b$1 is not installed...%b\n"
        exit 1
    fi
}

command_exists bash
command_exists curl
command_exists jq

# Function: if the passed variable is empty, prompt the user.
# The function trims white space from the input.
# Two display strings are provided:
#   prompt_msg: The prompt to display (this can include color codes)
#   default_value: A plain default value that will be used if the user enters nothing.
or_default() {
    local current_val="$1"
    local prompt_msg="$2"
    local default_value="$3"
    local input_val

    # If the variable is already set, notify the user and return that value.
    if [ -n "$current_val" ]; then
    printf "%b found in environment, using: %s%b\n" "${cyan}${prompt_msg}" "$current_val" "${reset}" >&2
    echo "$current_val"
    return
    fi

    # Prompt the user.
    read -r -p "$prompt_msg " input_val
    # Trim any extraneous whitespace.
    input_val="$(echo "$input_val" | xargs)"

    if [ -z "$input_val" ] && [ -n "$default_value" ]; then
    input_val="$default_value"
    printf "%bNo input provided. Using default: %s%b\n" "${cyan}" "$default_value" "${reset}" >&2
    fi

    echo "$input_val"
}

# Get configuration from the environment or via prompt.
GITHUB_USER=$(or_default "$GITHUB_USER" "${red}GitHub username:${reset}" "")
GITHUB_TOKEN=$(or_default "$GITHUB_TOKEN" "${red}GitHub access token (optional, only used for private repositories):${reset}" "")
FORGEJO_URL=$(or_default "$FORGEJO_URL" "${green}Forgejo instance URL (with https://):${reset}" "")
# Remove any trailing slash.
FORGEJO_URL="${FORGEJO_URL%/}"
FORGEJO_USER=$(or_default "$FORGEJO_USER" "${green}Forgejo username or organization to migrate to:${reset}" "")
FORGEJO_TOKEN=$(or_default "$FORGEJO_TOKEN" "${green}Forgejo access token:${reset}" "")
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

echo -e "${green}Force sync is set to: ${FORCE_SYNC}${reset}"
# -------------------------
# 1. Fetch GitHub Repositories via API (paginated)
# -------------------------
all_repos="[]"  # will hold a JSON array of repos
page=1

while true; do
  if [ -n "$GITHUB_TOKEN" ]; then
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=100&page=$page")
  else
    response=$(curl -s "https://api.github.com/users/$GITHUB_USER/repos?per_page=100&page=$page")
  fi

  # Filter repos so that only those whose owner.login matches GITHUB_USER are selected.
  filtered=$(echo "$response" | jq --arg gu "$GITHUB_USER" '[.[] | select(.owner.login == $gu)]')
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
  forgejo_response=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/user/repos")

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
        echo -ne "${red}Deleting ${yellow}$FORGEJO_URL/$full_name${red} because the mirror source doesn't exist on GitHub anymore...${reset}"
        curl -s -X DELETE -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/repos/$full_name" >/dev/null
        echo -e " ${green}Success!${reset}"
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
  full_name=$(echo "$repo" | jq -r '.full_name')

  # Prepare status message.
  # Capitalize the strategy for display.
  strategy_display="$(tr '[:lower:]' '[:upper:]' <<< "${STRATEGY:0:1}")${STRATEGY:1}"
  if [ "$private_flag" = "true" ]; then
    access_type="${red}private${reset}"
  else
    access_type="${green}public${reset}"
  fi
  echo -ne "${blue}${strategy_display}ing ${access_type} repository ${purple}$html_url${blue} to ${white}$FORGEJO_URL/$FORGEJO_USER/$repo_name${blue}...${reset}"

  # Determine which clone address to use.
  if [ "$private_flag" = "true" ]; then
    if [ -n "$GITHUB_TOKEN" ]; then
      github_repo_url="https://$GITHUB_TOKEN@github.com/$full_name"
    else
      echo -e " ${red}Error: Private repo but no GitHub token provided!${reset}"
      continue
    fi
  else
    github_repo_url="$html_url"
  fi

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
    '{clone_addr: $addr, mirror: $mirror, private: $private, repo_owner: $owner, repo_name: $repo}')

  # Send the POST request to the Forgejo migration endpoint.
  response=$(curl -s -H "Content-Type: application/json" -H "Authorization: token $FORGEJO_TOKEN" -d "$payload" "$FORGEJO_URL/api/v1/repos/migrate")
  error_message=$(echo "$response" | jq -r '.message // empty')

  if [[ "$error_message" == *"already exists"* ]]; then
    echo -e " ${yellow}Already mirrored!${reset}"
  elif [ -n "$error_message" ]; then
    echo -e " ${red}Unknown error: $error_message${reset}"
  else
    echo -e " ${green}Success!${reset}"
  fi
done
