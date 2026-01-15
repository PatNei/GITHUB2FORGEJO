> This script is inspired by and based on
> [RGBCube's original version](https://github.com/RGBCube/GitHub2Forgejo),
> rewritten in Bash.

# GitHub ➡️ Forgejo Migration Script in Bash

This is a Bash script for migrating repositories from a GitHub user or
organization account to a specified Forgejo instance. By default, it migrates
**all repositories**, but you can filter them by using a fine-grained GitHub
token with specific repository access. It supports **mirroring** or one-time
**cloning** and includes a cleanup feature for removing repositories on Forgejo
that no longer exist on GitHub.

## Features

- Migrates all (or selected) repositories for a GitHub user or organization.
- **Smart Detection**: Automatically detects if the account is a User or
  Organization.
- Supports both **public** and **private** repositories.
- **Mirror mode**: repositories stay in sync with GitHub.
- **Clone mode**: one-time copy without ongoing sync.
- **Archive Transfer**: Optionally transfers the archived status so archived
  repos remain read-only on Forgejo.
- Optional cleanup of outdated mirrors on Forgejo.
- Fully terminal-interactive or configurable via environment variables.

## Requirements

- `bash`
- `curl`
- `jq`
- `docker` (optional, for development environment)
- `direnv` (optional, for automated configuration)

## Usage

### 1. Manual Approach

You can run the script directly:

```bash
./github-forgejo-migrate.sh
```

You will be prompted for required values unless you provide them via environment
variables:

| Variable                 | Description                                                             |
| ------------------------ | ----------------------------------------------------------------------- |
| `GITHUB_USER`            | GitHub username or organization name                                    |
| `GITHUB_IS_ORG`          | (Optional) Force account type (`Yes`/`No`). Auto-detected if omitted.   |
| `GITHUB_TOKEN`           | GitHub access token. **Required for private repos or Organizations.**   |
| `FORGEJO_URL`            | Full URL to your Forgejo instance (e.g., `https://forgejo.example.com`) |
| `FORGEJO_USER`           | Forgejo username or organization to own the migrated repos              |
| `FORGEJO_TOKEN`          | Forgejo personal access token                                           |
| `STRATEGY`               | Either `mirror` (default) or `clone`                                    |
| `FORCE_SYNC`             | Set to `Yes` to delete Forgejo repos that no longer exist on GitHub     |
| `MIGRATE_ARCHIVE_STATUS` | Set to `Yes` (default) to transfer the archived status of repositories  |

### 2. Automated Development & Testing Environment

If you want to test the script without setting up a real Forgejo instance, you
can use the provided Docker environment.

1. **Configure Environment**: Create a `.env` file (or use `direnv` with the
   provided `.envrc`):
   ```bash
   cp .envrc.example .env
   # Edit .env and add your GITHUB_USER and GITHUB_TOKEN
   ```

2. **Launch Environment and Run Migration**:
   ```bash
   ./setup_and_test.sh
   ```
   This script will:
   - Launch a Forgejo container on `http://localhost:3000`.
   - Create an admin user (`testuser`).
   - Generate a Forgejo token and save it to your `.env`.
   - Automatically execute the migration script.

3. **Inspect Results**: Visit `http://localhost:3000` and log in with:
   - **User**: `testuser`
   - **Password**: `Password123!`

### Generate `GITHUB_TOKEN`

You can use either a **Fine-grained token** (recommended) or a **Classic
token**.

> [!IMPORTANT]
> **For Organizations**: To migrate private repositories belonging to an
> organization, your token must have sufficient permissions. For Fine-grained
> tokens, ensure the **Resource owner** is set to the specific organization if
> your personal token doesn't grant access.

#### Fine-grained Token (Recommended)

1. Go to `Settings` -> `Developer settings` -> `Personal access tokens` ->
   `Fine-grained tokens`.
2. Click `Generate new token`.
3. Set **Resource owner** to your account.
4. Set **Repository access** to `All repositories` (or select specific ones).
5. Set **Permissions**:
   - `Contents`: Read-only
   - `Metadata`: Read-only
6. Click `Generate token`.

#### Classic Token

1. Go to `Settings` -> `Developer settings` -> `Personal access tokens` ->
   `Tokens (classic)`.
2. Click `Generate new token (classic)`.
3. Select scope: `repo`.
4. Click `Generate token`.

### Generate `FORGEJO_TOKEN`

1. Navigate to Forgejo
2. Click your profile at the top right
3. Click `Settings`
4. Click `Applications` on the left
5. Generate a token 5a. Expand the select permissions 5b. Set `repository` to
   `Read and Write`
6. Either enter when prompted or save to FORGEJO_TOKEN w/
   `export FORGEJO_TOKEN=<Your token here>`

## What It Does

1. **Account Auto-Detection**: Checks if the specified GitHub account is a User
   or an Organization (can be overridden via `GITHUB_IS_ORG`).
2. **Repository Discovery**: Fetches all repositories (or specific ones if using
   a restricted token) belonging to the target account.
3. **Cleanup (Optional)**: Deletes any Forgejo mirrored repositories that no
   longer have a source on GitHub.
4. **Migration**: Migrates each repository to Forgejo using the selected
   strategy (`mirror` or `clone`).
5. **Archive Status (Optional)**: If enabled, ensures repositories archived on
   GitHub are also archived (read-only) on Forgejo after migration.
   - **Note**: This currently only applies to the `clone` strategy. Forgejo
     mirrors cannot be manually archived via the API.

## FAQ

### ❓ What is the difference between mirroring and cloning?

- **Mirroring**: Keeps the Forgejo repository in sync with the GitHub source.
- **Cloning**: Copies the repo once. No updates will occur after that.

### ❓ Can I migrate specific repositories?

Yes! While the script defaults to migrating all accessible repositories, you can
limit the scope by using a **GitHub Fine-grained Personal Access Token**. When
creating the token, select **"Only select repositories"** instead of "All
repositories". The script will then only see and migrate the repositories you
explicitly selected.

## License

```
GPL-3.0

Copyright (C) 2024-present

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```
