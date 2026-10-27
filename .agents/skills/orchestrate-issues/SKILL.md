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
- For a bug about a value the app receives (scanner, API, sync), trace the value to where it is produced before scoping. The file named in the issue is a starting point, not the scope (#222/PR #226: `NutritionLabelScanDraft.Create` rejected 0 kcal before the app saw it).
- Check an `agent-retro` proposal before you adopt it or put it in a brief; do not copy it verbatim. Check its values against the code it names (e.g. a harness timeout against the script's own timeout) and put each sentence in the section where it is acted on (e.g. planning in 2, agent rules in the brief list in 3, verification in 4, PR and merge steps in 5).
- Docs or skill changes of up to about ten lines in one file you make yourself; a subagent costs more than the change. Longer docs and skill texts go to a `haiku` subagent. OpenSpec changes always go to a `sonnet` subagent, whatever their size (see Model).
  - Same steps as the brief in section 3: `git fetch origin`, `git switch -c fix/issue-<n>-<slug> origin/main`, Conventional Commit with `Fixes #<n>` and Co-Authored-By, `git push -u origin <branch>`.
  - Not while a subagent edits the same file. Note your own Umwege for the retro.
  - Then switch back to your planning branch and continue with section 5.
- Disjoint files: run in parallel.
- Same file, different places: run in parallel, but give each agent an exact anchor ("insert directly after the bullet starting with …") several lines apart. Check later with `git merge-tree`.
- Same lines or one issue depends on another: run sequentially, or stack branch B on branch A.
- Shared building blocks (a new component, helper or parameter) you build first on main, then brief the agents.
- Large features that touch backend, sync and app: plan stacked subtasks, not one agent. Example: agent A for backend and protocol, agent B for the app on branch A. Each agent keeps a small context.
- Model: set `model` explicitly on every Agent call. Without it the agent inherits the orchestrator's model (Opus) and burns quota.
  - Default `sonnet`.
  - `haiku` for docs and skill texts, not for OpenSpec changes.
  - `sonnet` for OpenSpec changes (delta, validate, archive, code check); `haiku` struggled with the archive step (PR #227, 69 turns).
  - `opus` only for the sync protocol, migrations with a data-model decision, native code and Pigeon.
  - At most two Opus agents at once. Work further Opus issues one after another.
- At most four agents at once in total. More parallel agents do not lower the total, but they hit the 5-hour quota sooner and slow the host's test runs.
- An issue with more than about three independent points goes to several agents, not one. Give Opus only the native or sync part. One Opus agent for five points of #166 reached 258k context and 16 % of a whole round.
- Sonar or analyzer cleanups: at most about 20 findings or 10 files per agent.

## 3. Brief

Every prompt contains:

- the issue number and `gh api …/issues/<n>` to read it; for an `agent-retro` issue also the checked text from section 2, with the note that it replaces the issue's Vorschlag,
- "Read `docs/agent-lessons-learned.md` first",
- `git fetch origin`, then as a separate command `git switch -c fix/issue-<n>-<slug> origin/main`; if the fetch fails, stop and report instead of branching from a stale `origin/main` (worktrees do not start on main),
- the graphify rule: if `graphify-out/graph.json` is missing run `graphify update .`, then `graphify query` before grep,
- no `git restore`, `git stash`, `git reset --hard`; no pull request; no push to main,
- file edits go through the Read, Edit and Write tools, never through a script: no `sed -i`, heredocs, `cat >` and no Python or other script that writes files, because worktree isolation blocks those and the diff is unreviewed (#274, #270); probe scripts that only read may be written with Write and executed; exception: formatters and generators may write files (`dart format`, `dotnet format`, Pigeon, `dotnet ef migrations add`, `tool/preview_goldens.sh`),
- the shell rules for isolated worktrees from `docs/agent-lessons-learned.md` section 1 (separate git setup commands, no `git -C` outside the worktree, `cd apps/mobile && <check>` for app checks),
- "the repository is public: no secrets, personal data or content about other private projects",
- the exact scope and anchors, and which files not to touch,
- for every change: new or changed methods keep cognitive complexity ≤ 12 (Sonar S3776, limit 15; the manual count runs low) and at most 7 parameters, constructors included (Sonar S107); group extra parameters in a small class or a scoped helper (PR #282 `CoachRequestBudget`, PR #284 `_RecipeEditorState`),
- the checks to run (format, analyzer, tests, golden preview) for the touched area; name the exact commands from the instructions (`mobile.instructions.md`, `backend.instructions.md`, section "Prüfen" and "Tests"): only the touched folders, quiet reporters, `flutter pub get` first in a fresh worktree, never the whole suite (CI runs it); do not return unfiltered test output,
- for a bug fix: show that the new test fails without the fix (undo the fix temporarily with Edit, run the test, redo it; no `git stash`/`git restore`) and put the red line in the report,
- before the push: commit, then run the skill `code-review` on the own diff against `origin/main` (`code-review low`, diff `origin/main...HEAD`, not the local `main`) and fix the findings (amend the commit, so `Fixes #<n>` stays in it) or state why not,
- the commit: Conventional Commits, body ends with `Fixes #<n>` and the Co-Authored-By line,
- `git push -u origin <branch>`,
- the report: branch, SHA, what changed, check output, the red test line for a bug fix, and **Umwege** (anything done differently than expected, missing or wrong skills and rules, failed commands; "keine" if none).

Start agents in the background with worktree isolation. Do not touch their files while they run.

## 4. Verify each result

"Done" is not verified. For every branch:

- `git diff origin/main origin/<branch> --stat` matches the scope; read the diff.
- Run the relevant checks yourself if the area has any.
- For a bug fix: the report contains the red test line; without it, ask for it.
- `git merge-tree --write-tree origin/<a> origin/<b>` for every pair of branches that touch the same file.
- Fix small gaps yourself (amend and `git push --force-with-lease`); send larger ones back to the agent (how: section 5, review findings).

## 5. Pull requests and merge

- Open one PR per issue with `gh pr create`, body via the `pr` skill, `Fixes #<n>` in the body. Register it with T3 if `link_pull_request` exists.
- Review right after `gh pr create`: run `code-review <PR>`.
  - First review of a fresh PR: `medium --max-findings 5`. After a rework: `low --max-findings 3` on the new state. Sync protocol or migrations: full review (`high`).
  - Triage before sending anything back: only correctness bugs inside the issue's scope. Extensions, refactorings and style hints are rejected with a reason or filed as a new issue. Rework rounds were about 30 % of a round's quota when every finding was fixed.
  - Send findings back via `SendMessage` to the same agent only if its context is small: under about 150k tokens and at most one review round so far. Otherwise start a fresh agent with a compact brief: branch, list of findings, checks. The branch holds the state, the old transcript is not needed.
    - Setup for an existing branch: `git fetch origin`, then `git switch -c <helper-name> origin/<branch>`, then `git merge --no-edit origin/main` (stop and report if the fetch fails; resolve conflicts and commit the merge, or `git merge --abort` and report); push with `git push origin HEAD:<branch>` (no force). The local branch is still checked out in the first agent's worktree.
  - Pure style or refactoring hints from follow-up rounds may stay open, so the loop ends.
- Watch checks with `scripts/pr-wait.sh --timeout 110 <prs…>` via Bash `run_in_background` with `timeout: 7200000`: the default background limit of 30 minutes ends it before the iOS job finishes, and 110 minutes lets the script report pending PRs before the harness stops it. It stays silent and exits when all given PRs are final (checks done, merged, closed, conflict), so the harness wakes you once. For PRs you want to merge independently, start one process per PR. Start it only after the review is done. `watch_pull_request` is only a fallback. Answer wake-ups for already merged PRs and Sonar "Quality Gate Passed" with one line and no tool call.
- Handover: when your own context exceeds about 150k, all agents are done and only CI and merges are left, write a handover (open PRs with state, rejected findings, follow-up issues) and continue merging in a new thread. Each wake-up re-reads the whole context.
- Sonar cleanups: open the PR right after the push and read its Sonar findings before merging, even when the gate passed (calls in `docs/agent-lessons-learned.md`, section 4). The refactor can add new findings (e.g. dart:S7112 `const`).
- Merge only when all checks are green, `mergeable_state` is `clean` and the review findings are fixed or rejected with a reason: `gh pr merge <n> --merge`.
- After each merge, check the remaining PRs. On a conflict, merge `origin/main` into the branch and push.
- Confirm the issues closed: `gh api repos/PlaySkyHD/Gainer/issues/<n> --jq .state`.

## 6. Retro once at the end

The retro hook fires after every `gh pr create`. In an orchestration run, run the `retro` skill once after the last PR. Feed it the agents' Umwege plus your own observations. Do not file what the merged PRs already fix.

## 7. Report

Tell the user per issue: PR, merge commit, what changed, and any Umwege that became new issues.
