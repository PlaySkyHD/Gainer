#!/usr/bin/env bash
# PostToolUse hook: after `gh pr create` printed a pull request URL, remind the agent to run the retro skill.
input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")
[[ "$command" =~ gh[[:space:]]+pr[[:space:]]+create ]] || exit 0
jq -e '.tool_response | tostring | test("github\\.com/[^/]+/[^/]+/pull/[0-9]+")' <<<"$input" >/dev/null || exit 0
jq -n '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: "A pull request was just created. Run the retro skill now and file its findings as agent-retro issues before you continue or hand back to the user."}}'
