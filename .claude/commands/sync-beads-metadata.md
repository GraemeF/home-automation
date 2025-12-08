---
allowed-tools: Bash(git fetch:*), Bash(git pull:*), Bash(git merge:*), Bash(git push:*), Bash(git log:*), Bash(git status:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*), Bash(bd merge:*), Bash(gh pr list:*), Bash(gh pr create:*), Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(gh pr view:*)
description: Merge latest origin/main into beads-metadata branch and create automerging PR
---

## Your task

Sync the beads-metadata branch with main and create a PR to merge beads changes back.

The beads-metadata branch lives in a worktree at `.git/beads-worktrees/beads-metadata/` and contains only the `.beads/` directory. The bd daemon pushes beads changes there, but it can't push to main due to branch protection. This command bridges that gap.

**IMPORTANT:** All git commands in this workflow must be run from the worktree directory:

```bash
cd /path/to/repo/.git/beads-worktrees/beads-metadata
```

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

3. **Update beads-metadata from remote**

   First, pull any daemon commits that may have been pushed since the worktree was last used:

   ```bash
   git pull origin beads-metadata --no-edit
   ```

4. **Merge origin/main into beads-metadata**

   ```bash
   git merge origin/main -m "chore: merge main into beads-metadata"
   ```

   The `bd merge` driver (configured in .gitattributes) handles issues.jsonl merges automatically.

   **If merge succeeds:** Continue to step 5.

   **If merge shows CONFLICT:** The driver couldn't fully resolve. Use manual resolution:

   ```bash
   # Extract the 3 versions
   git show :1:.beads/issues.jsonl > /tmp/issues.base.jsonl
   git show :2:.beads/issues.jsonl > /tmp/issues.ours.jsonl
   git show :3:.beads/issues.jsonl > /tmp/issues.theirs.jsonl

   # Run bd merge to resolve
   bd merge /tmp/issues.merged.jsonl /tmp/issues.base.jsonl /tmp/issues.ours.jsonl /tmp/issues.theirs.jsonl

   # Apply the merged result
   cp /tmp/issues.merged.jsonl .beads/issues.jsonl
   git add .beads/issues.jsonl
   git commit -m "chore: merge main into beads-metadata"

   # Clean up
   rm /tmp/issues.*.jsonl
   ```

5. **Push beads-metadata**

   ```bash
   git push origin beads-metadata
   ```

6. **Check for existing PR**

   ```bash
   gh pr list --head beads-metadata --state open
   ```

7. **Create or update PR**
   - If no open PR exists, create one:
     ```bash
     gh pr create --base main --head beads-metadata \
       --title "chore: sync beads metadata" \
       --body "Automated sync of beads issue tracking data from the beads-metadata branch."
     ```
   - If PR already exists, it will automatically have the new commits

8. **Enable automerge**

   ```bash
   gh pr merge --auto --squash beads-metadata
   ```

9. **Monitor until merged**

   ```bash
   gh pr checks beads-metadata --watch
   ```

   - After checks pass, verify merge completed
   - Report success or failure

### Important notes

- The worktree path is `.git/beads-worktrees/beads-metadata/`
- beads-metadata only contains `.beads/` (sparse checkout)
- The `bd merge` driver does intelligent 3-way JSONL merging:
  - Matches issues by ID
  - Takes max updated_at timestamp
  - Unions dependencies
  - Prefers closed status over open
- True conflicts (with markers) are rare - they indicate genuinely incompatible field changes
- The PR should be squash-merged to keep main history clean
