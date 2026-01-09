---
allowed-tools: Bash(git status:*), Bash(git branch:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(cd:*), Bash(pwd:*), Bash(gleam build:*), Bash(gleam test:*), Bash(gleam format:*)
description: Iteratively fix all Gleam build/test issues until everything passes
---

# Your Task

Iteratively fix all issues shown by `gleam build` and `gleam test` one at a time until everything passes.

## Instructions

You are fixing build and test failures in the Gleam codebase. Your job is to:

1. **Run `gleam build`** from `packages/deep_heating` to identify compile errors
2. **Fix the first error** - focus on one issue at a time
3. **Run `gleam test`** to identify test failures
4. **Fix any test failures** one at a time
5. **Commit the changes** after each successful fix
6. **Repeat** until both `gleam build` and `gleam test` pass

## Critical Rules

### Scope

- Fix ONLY the specific issue in front of you
- Do NOT refactor unrelated code
- If fixing one issue reveals another, report it but stay focused

### Gleam-Specific Guidelines

- Follow the existing code patterns in the codebase
- Use pipe operators (`|>`) for function composition
- Prefer pattern matching over conditionals
- Keep functions pure where possible
- Actor messages should be descriptive domain concepts

### Verification

- Run `gleam build` and `gleam test` after each fix
- Ensure format is correct with `gleam format --check src test`
- The goal is a clean build with all tests passing

### Testing

- Tests live in the `test/` directory mirroring `src/` structure
- Run specific tests with `gleam test -- --filter=test_name`
- Never delete a failing test without explicit permission
- If a test is wrong, fix the test to match correct behaviour

## Progress Tracking

Use the TodoWrite tool to track:

- Which files have been fixed
- Which issues remain
- Overall progress toward clean build

## Exit Condition

Stop when:

1. `gleam build` completes with no errors
2. `gleam test` completes with all tests passing
3. `gleam format --check src test` shows no formatting issues

Report the final state to the user.
