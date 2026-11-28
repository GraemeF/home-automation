---
allowed-tools: Bash(git status:*), Bash(git branch:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git pull:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr checks:*), Bash(gh pr ready:*), Bash(gh pr edit:*), Bash(cd:*), Bash(pwd:*)
description: Commit changes, create/update PR, wait for checks, and mark it ready for review
---

## Your task

This command takes changes to a pull request that is ready for a maintainer to review and merge:

1. **Check current git status** - Determine if there are uncommitted changes
2. **Handle uncommitted changes** (if any):
   - Check if already on a feature branch, if not create one
3. **Run checks**
   - Run `bun run build && bun run test && bun run lint` to ensure all tests and checks pass before proceeding
   - Fix any issues if checks fail
   - Assume all failures are due to your changes, not external factors
4. **Create a changeset file** (if changes affect packages)
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
   - If a check fails, fix it, push, and wait again
8. **Mark the PR ready for review** with `gh pr ready` once every check is green
9. **Report** the PR's URL and say it is ready for a maintainer to merge

## Important notes

- If on main branch with uncommitted changes, create a feature branch first
- Use conventional commit format for commit messages
- PR title should follow conventional commits format
- Monitor and report PR check statuses while waiting
- Never merge the PR or set it to merge itself. A maintainer merges it.
- Leave the branch in place, because the PR still needs it
