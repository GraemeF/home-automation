---
allowed-tools: Bash(git worktree:*), Bash(git fetch:*), Bash(git status:*), Bash(git branch:*), Bash(bun install:*), Bash(pwd:*), Bash(git pull:*), Bash(git checkout:*), Bash(ls:*)
description: Start a new piece of work using git worktree
---

## Your task

IMPORTANT: Do not discard any local changes. It is possible that the command is being run in order to prepare to commit them.

IMPORTANT: Always use worktrees for feature development to maintain clean separation from main.

1. **Navigate to main worktree and fetch latest:**
   - Navigate to the `main` worktree (sibling to current directory, or find via `git worktree list`)
   - Run `pwd` to confirm location
   - Run `git fetch origin` to get latest from remote

2. **Create new worktree for feature branch:**
   - Generate appropriate branch name based on the work:
     - Features: `feature/<descriptive-name>`
     - Bug fixes: `fix/<descriptive-name>`
     - Docs: `docs/<descriptive-name>`
     - Chores: `chore/<descriptive-name>`
   - Run `git worktree add ../<worktree-name> -b <branch-name> origin/main`
   - This creates both the branch and isolated working directory

3. **Set up the new worktree:**
   - Change to the new worktree directory
   - Run `bun install` to set up dependencies
   - Run `git status` to confirm branch and clean state
   - Run `pwd` to show current worktree location

**Worktree Benefits:**

- Complete isolation from main branch
- Can work on multiple features simultaneously
- No risk of contaminating main with uncommitted changes
- Each worktree has its own node_modules and build artifacts
- Pre-commit hooks work correctly (requires `bun install`)

**Next Steps After Setup:**

1. Make your changes in the isolated worktree
2. Run `turbo build lint test` to verify changes
3. Commit with conventional format: "type(scope): description"
4. Push and create PR
5. After merge, clean up:
   - `cd` back to main worktree first
   - `git worktree remove ../<worktree-name>`
   - `git branch -d <branch-name>`
