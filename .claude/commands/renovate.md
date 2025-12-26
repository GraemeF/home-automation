---
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(gh run:*), Bash(git checkout:*), Bash(git status:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git pull:*), Bash(git fetch:*), Bash(git diff:*), Bash(git worktree:*), Bash(bun install:*), Bash(bun pm:*), Bash(turbo:*), Read, Glob, Grep, Edit, Write, Task, WebFetch
description: Process open Renovate dependency update PRs
---

# Your Task

Process ONE open Renovate PR by reviewing changes, making necessary updates, and merging it. Run this command multiple times to process additional PRs.

## Workflow

### Step 1: Discover Renovate PRs

List all open PRs from Renovate:

```bash
gh pr list --author "renovate[bot]" --state open --json number,title,headRefName
```

If no PRs are found, report "No open Renovate PRs" and exit.

If multiple PRs exist, select the FIRST one and report how many others remain.

### Step 2: Process the Selected PR

#### 2.1 Fetch and View the PR

```bash
git fetch origin
gh pr view {PR_NUMBER} --json title,body,files,additions,deletions
```

#### 2.2 Analyse the Changes

Read the PR description and changed files to understand:

- Which packages are being updated
- What version changes are occurring (patch/minor/major)
- If there are any breaking changes mentioned

#### 2.3 Research Changes and New Features

For MINOR and MAJOR version bumps:

1. Use WebFetch to check the package's CHANGELOG or release notes
2. For major bumps: look for migration guides and breaking changes
3. For minor bumps: look for new features we could leverage
4. Identify any code changes required or recommended

#### 2.4 Work on the Branch

Follow the project's branch workflow (see CLAUDE.md) to work on the Renovate branch. Ensure you have the latest changes from origin.

#### 2.5 Update Lock Files

Ensure lock files are fresh and consistent:

```bash
bun install
```

If `bun.lock` changes, commit and push. The `sync-bun-nix.yml` workflow will automatically regenerate `bun-deep-heating.nix` and commit it to the branch. Wait for that workflow to complete before proceeding.

**Note:** If Renovate updated `flake.lock` (Nix inputs), no additional regeneration is needed.

#### 2.6 Run Full Build and Tests

```bash
turbo all
```

If this fails:

- Analyse the failures
- Make necessary code changes to fix compatibility issues
- Commit the fixes with a clear message explaining what changed

#### 2.7 Leverage New Features

Based on your research from Step 2.3, look for opportunities to use new features:

1. Search the codebase for patterns that could benefit from new APIs
2. Check build output for deprecation warnings related to updated packages
3. Look for places using workarounds that new versions might solve natively

Make changes if they're straightforward and improve the codebase. For complex refactors, note them for future work but don't implement them now.

#### 2.8 Final Verification

Run the full build again to ensure everything passes:

```bash
turbo all
```

#### 2.9 Push Changes (if any)

If you made any changes beyond Renovate's original updates:

```bash
git add -A
git commit -m "chore: update code for dependency changes"
git push origin {BRANCH_NAME}
```

#### 2.10 Merge the PR

Wait for CI to pass, then merge:

```bash
gh pr checks {PR_NUMBER} --watch
gh pr merge {PR_NUMBER} --squash --auto
```

### Step 3: Clean Up

After the PR is merged, clean up according to the project's branch workflow (see CLAUDE.md).

Report how many Renovate PRs remain (if any). The user can run `/renovate` again to process the next one.

## Important Rules

### Lock File Hygiene

- ALWAYS run `bun install` on each Renovate branch to ensure lock files are consistent
- If `bun.lock` changes, push and wait for `sync-bun-nix.yml` workflow to regenerate `bun-deep-heating.nix`
- Pull after the workflow completes to get the regenerated file
- Commit lock file changes separately from code changes when possible

### Avoiding Scope Creep

- Only fix what's necessary for the dependency update to work
- Don't refactor unrelated code
- Note opportunities for improvement but don't implement them unless trivial

### Version Bump Protocol

**For major version bumps:**

1. Read the migration guide thoroughly
2. Apply only the minimum changes needed
3. Test comprehensively
4. If changes are extensive, stop and report to the user

**For minor version bumps:**

1. Check the changelog for new features
2. Search the codebase for opportunities to use them
3. Apply straightforward improvements only

### Merge Strategy

- Use squash merge to keep history clean
- If multiple Renovate PRs touch similar dependencies, consider whether order matters
- Don't force merge if checks are failing

## Progress Tracking

Use TodoWrite to track progress through the steps for this single PR.

## Exit Conditions

### Success

The Renovate PR has been merged successfully. Report:

- What was updated
- Any code changes made
- New features leveraged (if any)
- How many Renovate PRs remain

### Needs Manual Intervention

Stop and report to the user if:

- Tests are failing and you cannot determine the fix
- The update requires extensive breaking change migrations
- You're unsure whether a code change is appropriate
