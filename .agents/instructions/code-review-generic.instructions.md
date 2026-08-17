---
description: 'Generic code review instructions that define the baseline review method, severity model, and output contract for repository-specific review files.'
applyTo: '**'
excludeAgent: ["coding-agent"]
---

# Generic Code Review Instructions

This file defines the baseline method for code reviews. Language-specific and repository-specific review instruction files are additive and take precedence whenever they narrow, specialize, or override a generic rule.

## Review Language

When performing a code review, respond in **English**.

## Layering Rules

When performing a code review:

- Use this file for review structure, severity, evidence standards, and general risk categories.
- Use language-specific review files for stack conventions, approved libraries, forbidden patterns, and test framework expectations.
- Use repository-specific instructions for architecture, naming, deployment, security, or business-domain constraints.
- If two instructions conflict, follow the most specific one.
- Do not recommend patterns, frameworks, or refactors that conflict with the active language-specific review file.

## Review Goal

When performing a code review:

- Prioritize defects, regressions, vulnerabilities, and missing coverage over style commentary.
- Review changed code first, then inspect adjacent and impacted code as needed to validate behavior.
- Focus on merge-relevant risk, not hypothetical cleanup.
- Keep comments specific, concise, and evidence-based.

## General Review Principles

When performing a code review, follow these principles:

- Be specific: reference exact files, lines, and provide concrete examples.
- Provide context: explain WHY something is an issue and the potential impact.
- Suggest solutions: show the corrected approach when it is obvious, not just what is wrong.
- Be constructive: focus on improving the code, not criticizing the author.
- Group related comments: avoid multiple comments about the same recurring concern.
- Recognize good practices: briefly acknowledge well-written code only when doing so directly supports a finding or reinforces a codebase convention.

## Review Output Contract

When performing a code review:

1. Start with findings. Order them by severity, highest first.
2. For each finding, include the severity, category, affected file and location, the concrete risk, and a fix direction when it is obvious.
3. Use file and line references whenever possible.
4. If no findings are identified, state that explicitly.
5. After findings, optionally include open questions, assumptions, residual risks, or testing gaps.
6. Keep summaries brief and secondary to the findings.

## Severity Model

When performing a code review, classify findings as follows:

- Critical: likely security issue, correctness bug, contract break, privilege issue, data loss, or outage risk.
- Important: meaningful maintainability, testing, performance, concurrency, or architecture issue that can plausibly cause defects or operational pain.
- Suggestion: non-blocking improvement with clear value, but not required to merge safely.

## What Counts As A Finding

Treat the following as valid findings when supported by evidence:

- Correctness bugs and behavior regressions.
- Security vulnerabilities, insecure defaults, and secrets exposure.
- Data loss, corruption, idempotency, transaction, or consistency risks.
- Contract mismatches between API, UI, serialization, storage, or message schemas.
- Concurrency, resource lifetime, retry, timeout, or cancellation issues.
- Performance problems that are plausible and material for the affected path.
- Missing or inadequate tests for critical new behavior or bug fixes.
- Clear violations of repository architecture or required patterns that increase delivery or runtime risk.
- Missing or outdated documentation, ADRs, or README updates when the change is significant enough to warrant them.

## What Does Not Count As A Finding

Avoid reporting the following as findings unless they create concrete risk:

- Pure style preferences already enforced by formatter or linter.
- Broad refactor ideas without a specific bug, regression, or maintainability hazard.
- Speculative optimizations without a credible hot path or scale concern.
- Suggestions that contradict active language-specific or repository conventions.
- Comments that only restate what the code already does.

## Evidence Standards

When performing a code review:

- Explain why the issue matters in the context of the changed code.
- Prefer concrete trigger scenarios over generic rule citations.
- Distinguish confirmed defects from open questions or assumptions.
- Keep suggested fixes aligned with the repository's established stack and patterns.
- Reference neighboring code or existing patterns when that strengthens the recommendation.

## Review Areas

When performing a code review, inspect the following areas as applicable:

- Correctness and behavior:
  Inputs, outputs, control flow, edge cases, null handling, serialization, state transitions.
- Security and privacy:
  Authentication, authorization, validation, injection, SSRF, path traversal, secret handling, unsafe logging.
- Data and resilience:
  Transactions, retries, duplicate processing, partial failure handling, cancellation, timeouts, cleanup.
- Error handling:
  Proper error handling at appropriate levels, meaningful error messages, no silent failures, fail-fast input validation.
- Tests:
  Coverage of new behavior, failure modes, regression cases, and critical edge conditions.
  Descriptive test names, clear Arrange-Act-Assert structure, test independence, specific assertions, edge case coverage.
- Performance and scalability:
  Query shape, allocation patterns, blocking behavior, batching, caching, concurrency limits.
- Architecture and maintainability:
  Layer boundaries, dependency direction, duplication, coupling, public contract drift.
- Operability:
  Logging, metrics, tracing, health signals, diagnostics, and rollback safety.
- Documentation and ADRs:
  Significant behavioral, architectural, or API changes must be reflected in documentation (README, ADRs, runbooks, API docs).
  If no documentation update accompanies a significant change, flag it as a finding.
  New architectural decisions must have a corresponding ADR created or an existing ADR updated.
  Breaking changes must be documented clearly for consumers.

## Comment Template

Use this shape when reporting a finding:

```markdown
**[Severity] | [Category] | path/to/file.ext:line**

Short statement of the issue.

Why it matters: explain the concrete failure mode, exploit path, or regression risk.

Suggested fix: describe the smallest safe correction, aligned with repository conventions.

Reference: link to relevant documentation, standard, or prior pattern (when applicable).
```

### Example Comments

#### Critical Finding

```markdown
**Critical | Security | src/Controllers/UserController.cs:45**

The query concatenates user input directly into the SQL string, creating a SQL injection vulnerability.

Why it matters: an attacker could manipulate the parameter to execute arbitrary SQL commands, potentially exposing or deleting database data.

Suggested fix: use parameterized queries or the ORM's built-in query builder instead of string concatenation.

Reference: OWASP SQL Injection Prevention Cheat Sheet.
```

#### Important Finding

```markdown
**Important | Testing | src/Services/PaymentService.cs:120**

The refund path in ProcessPayment has no test coverage.

Why it matters: refunds involve financial transactions and should be tested to prevent data inconsistencies or incorrect amounts.

Suggested fix: add a test case covering the full refund scenario with assertion on the refund amount and resulting status.
```

#### Suggestion Finding

```markdown
**Suggestion | Readability | src/Handlers/OrderHandler.cs:30-40**

The nested conditionals make the logic hard to follow.

Why it matters: simpler code is easier to maintain, debug, and test.

Suggested fix: consider using guard clauses to flatten the nesting.
```

## Review Checklist

When performing a code review, systematically verify:

### Code Quality

- [ ] Code follows consistent style and naming conventions.
- [ ] Functions and methods are small and focused.
- [ ] No code duplication or dead code.
- [ ] Error handling is appropriate with meaningful messages.
- [ ] No commented-out code without a tracked issue.

### Security

- [ ] No sensitive data (passwords, tokens, PII) in code or logs.
- [ ] All user inputs are validated and sanitized.
- [ ] No injection vulnerabilities (SQL, command, XSS).
- [ ] Authentication and authorization are properly enforced.
- [ ] Dependencies are current and free of known vulnerabilities.

### Testing

- [ ] New and changed behavior has appropriate test coverage.
- [ ] Tests are well-named, independent, and deterministic.
- [ ] Tests cover edge cases and error scenarios.
- [ ] No tests that always pass or are commented out.

### Performance

- [ ] No obvious performance issues (N+1 queries, memory leaks, blocking I/O).
- [ ] Appropriate use of caching and batching.
- [ ] Proper resource cleanup (connections, streams, handles).

### Architecture

- [ ] Follows established patterns and layer boundaries.
- [ ] Dependencies flow in the correct direction.
- [ ] No architectural violations or unintended coupling.

### Documentation and ADRs

- [ ] Significant behavioral or API changes are reflected in documentation.
- [ ] New architectural decisions have a corresponding ADR.
- [ ] Existing ADRs are updated if the change modifies a prior decision.
- [ ] README is updated if the change affects setup, configuration, or usage.
- [ ] Breaking changes are documented for consumers.

## No-Findings Contract

If no findings are identified:

- State explicitly that no material findings were found.
- Mention residual risks, limited context, or testing gaps if they exist.
- Do not pad the response with non-actionable praise.

## Maintenance Guidance

If a repository needs additional review rules, add them in a language-specific or repository-specific review file instead of weakening or overloading this baseline.

Keep this file generic. Keep stack, framework, and project-specific constraints in the specialized review files.

### Extending This Baseline

To customize for your project, create additional review files for:

- **Language and framework checks**: e.g., "verify ASP.NET controllers use proper model validation."
- **Build and deployment**: e.g., "verify database migrations are reversible."
- **Business logic rules**: e.g., "verify pricing calculations include all applicable taxes."
- **Team conventions**: e.g., "verify commit messages follow conventional commits format."