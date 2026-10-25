---
name: orchestrate-issues
description: Work several GitHub issues of this repo through subagents until their pull requests are merged. Use when the user asks to fix issues "per subagent", to work off agent-retro issues, or to orchestrate parallel fixes.
---

# Orchestrate Issues

You plan, brief, verify, open the pull requests and merge. Subagents only implement, commit and push a branch.

## 1. Read the issues

- `gh issue view` fails here (Projects classic). Use `gh api repos/PlaySkyHD/Gainer/issues/<n> --jq '.title, .body'` or `gh issue list --json number,title,body`.
- Read `docs/agent-lessons-learned.md` before planning.

## 2. Plan

- Map each issue to the files it changes.
- Docs or skill changes of a few lines you make yourself: branch from `origin/main`, commit with `Fixes #<n>`, continue with section 5. A subagent costs more than the change.
- Disjoint files: run in parallel.
- Same file, different places: run in parallel, but give each agent an exact anchor ("insert directly after the bullet starting with …") several lines apart. Check later with `git merge-tree`.
- Same lines or one issue depends on another: run sequentially, or stack branch B on branch A.
- Shared building blocks (a new component, helper or parameter) you build first on main, then brief the agents.
- Large features that touch backend, sync and app: plan stacked subtasks, not one agent. Example: agent A for backend and protocol, agent B for the app on branch A. Each agent keeps a small context.
- Model: set `model` explicitly on every Agent call. Without it the agent inherits the orchestrator's model (Opus) and burns quota.
  - Default `sonnet`.
  - `haiku` for docs and skill texts.
  - `opus` only for the sync protocol, migrations with a data-model decision, native code and Pigeon.
  - At most two Opus agents at once. Work further Opus issues one after another.

## 3. Brief

Every prompt contains:

- the issue number and `gh api …/issues/<n>` to read it,
- "Read `docs/agent-lessons-learned.md` first",
- `git fetch origin`, then as a separate command `git switch -c fix/issue-<n>-<slug> origin/main`; if the fetch fails, stop and report instead of branching from a stale `origin/main` (worktrees do not start on main),
- the graphify rule: if `graphify-out/graph.json` is missing run `graphify update .`, then `graphify query` before grep,
- no `git restore`, `git stash`, `git reset --hard`; no pull request; no push to main,
- file edits go through the Read, Edit and Write tools, not `sed -i`, heredocs or `cat >` in Bash, because worktree isolation blocks those; longer probe scripts are written with Write and then executed,
- the shell rules for isolated worktrees from `docs/agent-lessons-learned.md` section 1 (separate git setup commands, no `git -C` outside the worktree, `cd apps/mobile && <check>` for app checks),
- "the repository is public: no secrets, personal data or content about other private projects",
- the exact scope and anchors, and which files not to touch,
- the checks to run (format, analyzer, tests, golden preview) for the touched area; name the exact commands from the instructions (`mobile.instructions.md`, `backend.instructions.md`, section "Prüfen" and "Tests"): only the touched folders, quiet reporters, `flutter pub get` first in a fresh worktree, never the whole suite (CI runs it); do not return unfiltered test output,
- before the push: run the skill `code-review` on the own diff (`code-review low`) and fix the findings or state why not,
- the commit: Conventional Commits, body ends with `Fixes #<n>` and the Co-Authored-By line,
- `git push -u origin <branch>`,
- the report: branch, SHA, what changed, check output, and **Umwege** (anything done differently than expected, missing or wrong skills and rules, failed commands; "keine" if none).

Start agents in the background with worktree isolation. Do not touch their files while they run.

## 4. Verify each result

"Done" is not verified. For every branch:

- `git diff origin/main origin/<branch> --stat` matches the scope; read the diff.
- Run the relevant checks yourself if the area has any.
- `git merge-tree --write-tree origin/<a> origin/<b>` for every pair of branches that touch the same file.
- Fix small gaps yourself (amend and `git push --force-with-lease`); send larger ones back to the agent (how: section 5, review findings).

## 5. Pull requests and merge

- Open one PR per issue with `gh pr create`, body via the `pr` skill, `Fixes #<n>` in the body. Register it with T3 if `link_pull_request` exists.
- Review right after `gh pr create`: run `code-review <PR>`.
  - First review of a fresh PR: `medium`. After a rework: `low` on the new state. Sync protocol or migrations: full review (`high`).
  - Send findings back via `SendMessage` to the same agent only if its context is small: under about 150k tokens and at most one review round so far. Otherwise start a fresh agent with a compact brief: branch, list of findings, checks. The branch holds the state, the old transcript is not needed.
  - Pure style or refactoring hints from follow-up rounds may stay open, so the loop ends.
- Watch checks (`watch_pull_request` if available, otherwise `gh pr checks <n>`). Never poll in a sleep loop.
- Merge only when all checks are green, `mergeable_state` is `clean` and the review findings are fixed or rejected with a reason: `gh pr merge <n> --merge`.
- After each merge, check the remaining PRs. On a conflict, merge `origin/main` into the branch and push.
- Confirm the issues closed: `gh api repos/PlaySkyHD/Gainer/issues/<n> --jq .state`.

## 6. Retro once at the end

The retro hook fires after every `gh pr create`. In an orchestration run, run the `retro` skill once after the last PR. Feed it the agents' Umwege plus your own observations. Do not file what the merged PRs already fix.

## 7. Report

Tell the user per issue: PR, merge commit, what changed, and any Umwege that became new issues.
