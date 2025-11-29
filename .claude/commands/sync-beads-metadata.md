---
allowed-tools: Bash(git fetch:*), Bash(git merge:*), Bash(git push:*), Bash(git log:*), Bash(git status:*), Bash(gh pr:*), Bash(cd:*), Bash(pwd:*)
description: Merge latest origin/main into beads-metadata branch and create automerging PR
---

## Your task

Sync the beads-metadata branch with main and create a PR to merge beads changes back.

The beads-metadata branch lives in a worktree at `.git/beads-worktrees/beads-metadata/` and contains only the `.beads/` directory. The bd daemon pushes beads changes there, but it can't push to main due to branch protection. This command bridges that gap.

### Steps

1. **Fetch latest from origin**

   ```bash
   git fetch origin main beads-metadata
   ```

2. **Check if there are beads changes to merge**

   ```bash
   git log --oneline origin/main..origin/beads-metadata
   ```

   - If no commits, report "beads-metadata is already in sync with main" and exit

3. **Update beads-metadata with latest main** (in the worktree)

   ```bash
   cd .git/beads-worktrees/beads-metadata
   git merge origin/main --no-edit
   ```

   - The `bd merge` driver (configured in .gitattributes) handles issues.jsonl merges automatically
   - It intelligently merges issues by ID, combining changes and preferring closed status
   - If true conflicts occur (conflict markers in output), the merge driver couldn't resolve them - stop and report

4. **Push beads-metadata**

   ```bash
   git push origin beads-metadata
   ```

5. **Check for existing PR**

   ```bash
   gh pr list --head beads-metadata --state open
   ```

6. **Create or update PR**
   - If no open PR exists, create one:
     ```bash
     gh pr create --base main --head beads-metadata \
       --title "chore: sync beads metadata" \
       --body "Automated sync of beads issue tracking data from the beads-metadata branch."
     ```
   - If PR already exists, it will automatically have the new commits

7. **Enable automerge**

   ```bash
   gh pr merge --auto --squash beads-metadata
   ```

8. **Monitor until merged**

   ```bash
   gh pr checks beads-metadata --watch
   ```

   - After checks pass, verify merge completed
   - Report success or failure

9. **Return to original directory**
   - Make sure to cd back to the repo root before finishing

### Important notes

- The worktree path is `.git/beads-worktrees/beads-metadata/`
- beads-metadata only contains `.beads/` - conflicts are handled by the `bd merge` driver
- The `bd merge` driver does intelligent 3-way merging (closed wins, max updated_at, combine deps)
- True conflicts (with markers) are rare - they indicate genuinely incompatible field changes
- The PR should be squash-merged to keep main history clean
