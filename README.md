# Homebridge Dependency Bot

A GitHub composite action that automatically manages package.json dependencies for Homebridge release streams. This action creates pull requests with dependency updates and can automatically merge them when configured.

## Features

- 🔄 Automatic dependency updates for stable/beta/alpha release streams
- 🔧 Configurable package targeting with tags or version patterns
- 📝 Automatic pull request creation with detailed commit messages
- 🤖 Optional auto-merge functionality with PR approval
- 📁 Multi-directory support for monorepo structures
- 🔒 Secure token handling using GitHub's built-in authentication
- Leveraged by:
  * homebridge/homebridge-apt-pkg
  * homebridge/docker-image
  * homebridge/homebridge-vm-image

## Usage

### Basic Example

```yaml
name: Update Dependencies
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  update-dependencies:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Update Beta Dependencies
        uses: homebridge/dependency-bot@latest
        with:
          config_file: '.github/homebridge-dependency-bot.json'
          release_stream: 'beta'
```

### With Auto-merge (Two Token Approach)

```yaml
name: Update Dependencies with Auto-merge
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  update-dependencies:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      # Additional permissions needed for auto-merge
      metadata: read
      checks: read
    steps:
      - name: Update Beta Dependencies
        uses: homebridge/dependency-bot@latest
        with:
          config_file: '.github/homebridge-dependency-bot.json'
          release_stream: 'beta'
          GH_TOKEN: ${{ secrets.GH_TOKEN }}  # Separate token for PR approval
```

### Multiple Release Streams

```yaml
name: Update All Dependencies
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  update-beta:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Update Beta Dependencies
        uses: homebridge/dependency-bot@latest
        with:
          release_stream: 'beta'

  update-alpha:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Update Alpha Dependencies
        uses: homebridge/dependency-bot@latest
        with:
          release_stream: 'alpha'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `config_file` | Path to the dependency bot configuration file | No | `.github/homebridge-dependency-bot.json` |
| `release_stream` | Release stream to update (beta or alpha) | No | `beta` |
| `GH_TOKEN` | GitHub token with PR approval permissions (see Token Handling section). When empty, the approve step is skipped | No | - |
| `PUBLISH_TOKEN` | Token used to push (`update_method: push`), and in PR mode to push the PR branch and create the PR. Falls back to `GH_TOKEN` | No | - |
| `base_branch` | Branch to check out, open the PR against, or push to (e.g. `beta-5.30.2`). Empty keeps the default: the branch the workflow ran on | No | empty |
| `branch_pattern` | Glob for the branch to work on (e.g. `beta-*.*.*`). The highest matching branch by version is used; if none matches, the action does nothing and sets `skipped`. Cannot be combined with `base_branch` | No | empty |

## Outputs

| Output | Description |
|--------|-------------|
| `changes_detected` | Whether changes were detected in any directories (`true`/`false`) |
| `changed_dirs` | Comma-separated list of directories with changes |
| `auto_merge` | Whether changes land without review (`true`/`false`); always `true` with `update_method: push` |
| `update_method` | `pr` or `push` |
| `commit_sha` | The commit pushed to the base branch (`push` only) |
| `branch_name` | The name of the branch created (if changes detected) |
| `pr_number` | The number of the pull request created (if changes detected) |
| `base_branch` | The branch the action worked on (`base_branch`, the branch matched by `branch_pattern`, or empty for the default) |
| `skipped` | `true` when no branch matched `branch_pattern`, so nothing ran |

## Token Handling

This action supports two different approaches for token handling to work around GitHub's security restrictions:

### Single Token Approach (Basic)

For basic usage without auto-merge, the action uses GitHub's built-in `github.token` automatically:

```yaml
steps:
  - name: Update Dependencies
    uses: homebridge/dependency-bot@latest
    with:
      config_file: '.github/homebridge-dependency-bot.json'
      release_stream: 'beta'
```

### Two Token Approach (Auto-merge)

For auto-merge functionality, GitHub's security rules prevent a bot from creating a PR and then approving it with the same token. To work around this, use two different tokens:

```yaml
steps:
  - name: Update Dependencies with Auto-merge
    uses: homebridge/dependency-bot@latest
    with:
      config_file: '.github/homebridge-dependency-bot.json'
      release_stream: 'beta'
      GH_TOKEN: ${{ secrets.GH_TOKEN }}
```

**Token Setup:**
- `secrets.GITHUB_TOKEN` (automatic): Used for repository operations (checkout, push, create PR)
- `secrets.GH_TOKEN` (manual): A separate token with only PR approval permissions

**How to create the approval token:**
1. Create a Personal Access Token (classic) or Fine-grained token
2. Grant only the minimum permissions needed: `pull_requests: write`
3. Add it as a repository secret named `GH_TOKEN`

**⚠️ Security Note:** Always pass `GH_TOKEN` as a secret (`${{ secrets.GH_TOKEN }}`) in your workflow. Never expose token values directly in your workflow files.

### Token Usage Summary

The action uses tokens for different operations:
- **Checkout**: Always uses `github.token`
- **PR mode, push of the PR branch and PR creation**: Uses `PUBLISH_TOKEN` (or `GH_TOKEN` if that is empty) when either is provided, so the PR's CI runs and a merge triggers downstream workflows. GitHub does not trigger workflows for events made with `github.token`. With neither provided, `github.token` is used as before
- **PR approval**: Uses `GH_TOKEN`; the step is skipped when `GH_TOKEN` is empty
- **PR merge**: Uses `GH_TOKEN` (with `merge_when_green`: `PUBLISH_TOKEN`, falling back to `GH_TOKEN`)

### Required Permissions

Your workflow must include the following permissions:

```yaml
permissions:
  contents: write        # Required for creating branches and commits
  pull-requests: write   # Required for creating and managing PRs
  metadata: read         # Required for auto-merge functionality
  checks: read           # Required for auto-merge functionality
```

## Configuration File

Create a configuration file (default: `.github/homebridge-dependency-bot.json`) in your repository:

### Basic Configuration

```json
{
  "git_user": {
    "name": "Homebridge Dependency Bot",
    "email": "actions@github.com"
  },
  "auto_merge": false,
  "directories": [
    {
      "directory": ".",
      "packages": [
        {
          "name": "homebridge",
          "tag": "beta"
        }
      ]
    }
  ]
}
```

### Advanced Configuration with Patterns

```json
{
  "git_user": {
    "name": "My Dependency Bot",
    "email": "bot@example.com"
  },
  "auto_merge": true,
  "directories": [
    {
      "directory": ".",
      "packages": [
        {
          "name": "homebridge",
          "tag": "beta"
        },
        {
          "name": "@homebridge/plugin-ui-utils",
          "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+-beta\\.[0-9]+$"
        }
      ]
    },
    {
      "directory": "sub-project",
      "packages": [
        {
          "name": "homebridge",
          "tag": "alpha"
        }
      ]
    }
  ]
}
```

### Configuration Options

| Field | Description | Required | Default |
|-------|-------------|----------|---------|
| `git_user.name` | Name for Git commits | No | `"Homebridge Dependency Bot"` |
| `git_user.email` | Email for Git commits | No | `"actions@github.com"` |
| `auto_merge` | Enable automatic PR approval and merge | No | `false` |
| `merge_when_green` | With `auto_merge`, enable GitHub auto-merge (`gh pr merge --auto --squash`) instead of merging immediately, so the PR merges once required checks pass. The repo needs auto-merge enabled and branch protection with required checks | No | `false` |
| `update_lockfile` | After installing packages in a directory that has a `package-lock.json`, run `npm install --package-lock-only --ignore-scripts` and commit the lockfile with `package.json`. May be set at top level or per entry in `directories[]` | No | `false` |
| `update_method` | `"pr"` opens a pull request (merged automatically if `auto_merge` is true). `"push"` commits straight to the checked-out branch with `GH_TOKEN`, with no PR; the `auto_merge` output is then `true` | No | `"pr"` |
| `directories` | Array of directories to process | Yes | - |
| `directories[].directory` | Path to directory containing package.json | Yes | - |
| `directories[].packages` | Array of packages to update | Yes | - |
| `directories[].packages[].name` | NPM package name | Yes | - |
| `directories[].packages[].tag` | NPM dist-tag or version range to install (e.g., "beta", "^26.x.x"), or a list of them (e.g., `["alpha", "beta"]`) to install whichever resolves to the highest version | No* | - |
| `directories[].packages[].pattern` | Regex pattern to match versions | No* | - |

*Note: Each package must specify either `tag` OR `pattern`, but not both.

### Direct Push

Set `"update_method": "push"` to commit updates straight to the branch the workflow checked out
(normally the default branch) instead of opening a pull request. This avoids a PR, an approval
and a merge for every update, and the notifications that come with them.

- `GH_TOKEN` must be allowed to push to that branch. If it is protected, the token's owner (or
  app) needs to be able to bypass the protection.
- If the push is rejected because the branch moved, the bot rebases and retries, up to 3 times.
- The `auto_merge` output is `true`, so workflows that trigger a build on `auto_merge` keep working.
- The commit message is `<STREAM>: Update <stream> dependencies in <dirs>`.

### Prerelease Branches in PR Mode

Set `branch_pattern` (e.g. `beta-*.*.*`) to run against the highest matching branch, such as
`beta-5.30.2`: the action checks it out and opens the PR against it. If no branch matches, it
does nothing, so a scheduled run is harmless between releases and never touches the default
branch. To name a branch instead, set `base_branch`. Use an App token as `PUBLISH_TOKEN` so the
PR's CI runs, and set `auto_merge` and `merge_when_green` in the config to merge once required
checks pass. `GH_TOKEN` is optional; leave it out and the approve step is skipped (use this when
the branch needs no review). Branch names are passed to the scripts through `env`, never
interpolated into them.

The bot keeps one PR per base branch, on `update/<release_stream>-<base>`. Each run force-pushes
fresh updates to that branch and edits the open PR instead of opening another. If someone else
pushed their own commits to that branch, the bot leaves the branch and its PR alone and warns in
the log.

```yaml
name: Update Prerelease Dependencies
on:
  schedule:
    - cron: '0 9 * * *'
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        stream: [beta, alpha]
    steps:
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          app-id: ${{ secrets.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}
          permission-contents: write
          permission-pull-requests: write

      - uses: homebridge/dependency-bot@v2.0.0
        with:
          config_file: .github/homebridge-dependency-bot-${{ matrix.stream }}.json
          release_stream: ${{ matrix.stream }}
          branch_pattern: ${{ matrix.stream }}-*.*.*
          PUBLISH_TOKEN: ${{ steps.app-token.outputs.token }}
```

with a config like:

```json
{
  "update_method": "pr",
  "auto_merge": true,
  "merge_when_green": true,
  "directories": [
    {
      "directory": ".",
      "update_lockfile": true,
      "packages": [{ "name": "@homebridge/node-pty-prebuilt-multiarch", "tag": "beta" }]
    }
  ]
}
```

### Job Summary

Every run writes a table to the GitHub job summary: each dependency or devDependency whose version changed, its
old and new version, and where the new version came from (for a tag list, which tag won). It
ends with the outcome: no changes, PR merged (or auto-merge enabled), or the pushed commit.

### Tag Lists

Give `tag` a list to follow several tags and take the newest. Each entry is resolved with
`npm view`, and the highest version by semver is installed, so a stable release beats an
older prerelease (`2.5.0` over `2.5.0-beta.3`). If any entry doesn't resolve (a typo, a removed
tag, or npm being unavailable), the run fails rather than picking from the rest, so a bad lookup
can never install an older version.

A single tag works the same way: it's resolved with `npm view` and the exact version is
installed. The bot never runs `npm install` on a range, because npm skips versions whose
`engines` field leaves out the Node.js running the bot (on Node 26, `homebridge@^1.x.x` would
install 1.6.1 instead of 1.11.4).

```json
{
  "name": "homebridge-config-ui-x",
  "tag": ["alpha", "beta"]
}
```

### Pattern Examples

For beta versions: `^[0-9]+\\.[0-9]+\\.[0-9]+-beta\\.[0-9]+$`
For alpha versions: `^[0-9]+\\.[0-9]+\\.[0-9]+-alpha\\.[0-9]+$`
For release candidates: `^[0-9]+\\.[0-9]+\\.[0-9]+-rc\\.[0-9]+$`

## Example Workflow Output

When the action runs successfully, you'll see output like:

```
🤖 homebridge beta Dependency Bot - Update Dependencies
Config file loaded: /github/workspace/.github/homebridge-dependency-bot.json
Git identity configured: Homebridge Dependency Bot <actions@github.com>
Found 1 directories in config
Processing directory: .
Found 1 packages in .
Installing homebridge@1.6.0-beta.1 in .
Changes detected in .
Branch pushed: update/beta-1693920000
Pull request created: #123 (https://github.com/owner/repo/pull/123)
```

## Security Considerations

- **Two-token security**: For auto-merge functionality, use separate tokens to prevent bot self-approval security issues
- **Minimal permissions**: Grant only the minimum required permissions to each token
- Repository operations use the standard `github.token` automatically
- PR approval operations can use a separate `GH_TOKEN` with limited permissions
- Tokens are handled securely and never exposed in logs or environment variables
- Consider using branch protection rules for additional security

## Troubleshooting

### Common Issues

**Config file not found**: Ensure your config file exists at the specified path (default: `.github/homebridge-dependency-bot.json`)

**Permission denied**: Verify your workflow has the required permissions (see Token Handling section)

**Package not found**: Check that the package name is correct and the tag/pattern matches available versions

**Auto-merge fails**: For auto-merge functionality, ensure you're using the two-token approach with a separate `GH_TOKEN` that has PR approval permissions. GitHub prevents bots from self-approving PRs with the same token used to create them.

**Token setup issues**: Create a Personal Access Token with `pull_requests: write` permission and add it as a repository secret named `GH_TOKEN`

### Debug Mode

Add `ACTIONS_STEP_DEBUG: true` to your workflow environment variables for detailed debugging output:

```yaml
env:
  ACTIONS_STEP_DEBUG: true
```

## Contributing

This action is used by homebridge-apt-pkg and docker-homebridge projects. Feel free to submit issues or pull requests.

## License

This project is licensed under the same terms as the Homebridge project.