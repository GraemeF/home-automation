# Changesets

## Adding a changeset

Create a markdown file here (e.g., `fix-temperature-bug.md`):

```markdown
---
'@home-automation/deep-heating-rx': patch
---

Brief description of what changed
```

Bump types: `patch`, `minor`, `major`

## Pre-releases

Enter pre-release mode:

```bash
bun changeset pre enter beta  # or alpha, rc
```

Exit when ready for stable release:

```bash
bun changeset pre exit
```
