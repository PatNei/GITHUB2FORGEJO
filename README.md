> This script is inspired by and based on [RGBCube's original version](https://github.com/RGBCube/GitHub2Forgejo), rewritten in Bash.

# GitHub ➡️ Forgejo Migration Script in Bash

This is a Bash script for migrating **all repositories** from a GitHub user account to a specified Forgejo instance.
It supports **mirroring** or one-time **cloning** and includes a cleanup feature for removing repositories on Forgejo that no longer exist on GitHub.

## Features

- Migrates all repositories for a GitHub user.
- Supports both **public** and **private** repositories.
- **Mirror mode**: repositories stay in sync with GitHub.
- **Clone mode**: one-time copy without ongoing sync.
- Optional cleanup of outdated mirrors on Forgejo.
- Fully terminal-interactive or configurable via environment variables.

## Requirements

- `bash`
- `curl`
- `jq`

## Usage

You can run the script directly:

```bash
./github-forgejo-migrate.sh
```

You will be prompted for required values unless you provide them via environment variables:

| Variable        | Description                                                                 |
|----------------|-----------------------------------------------------------------------------|
| `GITHUB_USER`   | GitHub username                                                             |
| `GITHUB_TOKEN`  | GitHub access token (required for private repos)                            |
| `FORGEJO_URL`   | Full URL to your Forgejo instance (e.g., `https://forgejo.example.com`)     |
| `FORGEJO_USER`  | Forgejo username or organization to own the migrated repos                  |
| `FORGEJO_TOKEN` | Forgejo personal access token                                               |
| `STRATEGY`      | Either `mirror` (default) or `clone`                                        |
| `FORCE_SYNC`    | Set to `Yes` to delete Forgejo repos that no longer exist on GitHub         |

### Generate `GITHUB_TOKEN`

1. Navigate to GitHub
2. Click your profile at the top right
3. Click `Settings`
4. Scroll down to the bottom of the left menu
5. Click `Developer settings`
6. Click `Tokens (classic)`
7. Click `Generate new token -> Generate new token(classic)`
8. Select scopes:
    repo: all
9. Either enter when prompted or save to GITHUB_TOKEN w/ `export GITHUB_TOKEN=<Your token here>`

### Generate `FORGEJO_TOKEN`

1. Navigate to Forgejo
2. Click your profile at the top right
3. Click `Settings`
4. Click `Applications` on the left
5. Generate a token
    5a. Expand the select permissions
    5b. Set `repository` to `Read and Write`
6. Either enter when prompted or save to FORGEJO_TOKEN w/ `export FORGEJO_TOKEN=<Your token here>`

## What It Does

1. Fetches all repositories belonging to the specified GitHub user.
2. (Optional) Deletes any Forgejo mirrored repositories that no longer have a source on GitHub.
3. Migrates each repository to Forgejo using the selected strategy (`mirror` or `clone`).

## FAQ

### ❓ What is the difference between mirroring and cloning?

- **Mirroring**: Keeps the Forgejo repository in sync with the GitHub source.
- **Cloning**: Copies the repo once. No updates will occur after that.

### ❓ Can I migrate specific repositories?

Nope. This script is all or nothing. For selective migration, please use the Forgejo web interface.


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
