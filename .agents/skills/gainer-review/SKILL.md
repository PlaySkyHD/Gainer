---
name: gainer-review
description: Review rules of the Gainer repo. Use when reviewing a diff, branch or pull request in this repository, before writing review findings. Loads the generic review method plus the C# and OpenSpec checks that match the changed files.
---

# Gainer Review

The review instructions live in `.agents/instructions/` and are shared with other agents. Read them before reviewing; do not paraphrase them from memory.

1. Always read `.agents/instructions/code-review-generic.instructions.md`. It defines the method, the severity model and the output contract.
2. If the diff touches `*.cs`, also read `.agents/instructions/code-review-csharp.instructions.md`.
3. If the diff touches `openspec/**`, also read `.agents/instructions/code-review-openspec.instructions.md`.
4. Apply `docs/agent-lessons-learned.md` as repo-specific review knowledge.

When another review skill or command sets the output format (for example a findings tool), keep that format and use these files for what to check and how to rate severity.
