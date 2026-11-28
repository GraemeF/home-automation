---
allowed-tools: Bash(git status:*), Bash(git branch:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git pull:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr create:*), Bash(gh pr edit:*), Bash(gh pr checks:*), Bash(gh pr ready:*), Bash(cd:*), Bash(pwd:*), Bash(gleam build:*), Bash(gleam test:*), Bash(gleam format:*)
description: Commit changes, create/update PR, wait for checks, and mark it ready for review
---

## Your task

This command takes the current changes to a pull request that is ready for review:

1. **Check current git status** - Determine if there are uncommitted changes
2. **Handle uncommitted changes** (if any):
   - Check if already on a feature branch, if not create one
3. **Run checks**
   - Run `gleam build && gleam test` from `packages/deep_heating` to ensure all tests pass before proceeding
   - Fix any issues if checks fail
   - Assume all failures are due to your changes, not external factors
4. **Create a changeset file** (if changes affect the package)
   - Manually create a new changeset file in `.changeset/` with a summary of changes and type of release (patch or minor only, because we are still pre-1.0.0)
   - Changes must be described from the perspective of a user of the package, not internal implementation details
   - Skip this step if changes don't affect published packages (e.g., CI/workflow changes only)
5. **Commit and push changes** to the feature branch
   - Stage and commit all relevant changes (ignoring unrelated changes) with an appropriate commit message
   - Push the branch to origin
6. **Check for existing PR**:
   - If PR already exists for current branch, ensure it's up to date
   - If no PR exists, create one as a draft with a descriptive title and body
7. **Wait for checks** with `gh pr checks --watch`
   - If a check fails, fix it, push, and watch again
8. **Mark the PR ready for review** with `gh pr ready` once every check passes
9. **Report** the PR's URL. Leave the branch in place, because the PR is not merged yet.

## Important notes

- If on main branch with uncommitted changes, create a feature branch first
- Use conventional commit format for commit messages
- PR title should follow conventional commits format
- Monitor and report PR check statuses while waiting
- Stop once the PR is ready for review. A maintainer reviews and merges it.
