---
applyTo: '.github/workflows/*.yml,.github/workflows/*.yaml'
description: 'Best practices for GitHub Actions CI/CD workflows covering structure, security, caching, and deployment.'
---

# GitHub Actions CI/CD Best Practices

## Workflow Structure

- Use consistent, descriptive names for workflow files (e.g., `cicd.yml`, `release.yml`).
- Use appropriate `on` triggers with granular `branches` and `paths` filters.
- Use `concurrency` with per-environment groups to prevent parallel deploys to the same target.
- Define `permissions` at the workflow level for least privilege, override at the job level only when needed.
- Use reusable workflows (`workflow_call`) and composite actions from the `action-templates` repository to reduce duplication.

## Jobs

- Give each job a clear `name` representing a distinct pipeline phase (build, test, deploy).
- Use `needs` to define dependencies between jobs.
- Use `outputs` to pass data between jobs instead of rebuilding artifacts.
- Use `(!failed() && !cancelled())` to conditionally run steps or jobs based on the failure status of previous jobs, if needed.
- Use `if` conditions for conditional execution based on branches or other output (e.g., deploy only on `main`).
- Set `timeout-minutes` on long-running jobs to prevent hung workflows.

## Actions and Steps

- Pin third-party actions to a full-length commit SHA for security and immutability.
- For internal composite actions from `GWS-CloudSolutions/action-templates`, using `@main` is the established convention; SHA pinning is not required for these.
- Use descriptive `name` values on every step.
- Prefer multi-line `run` scripts with `|` for complex commands.
- Audit marketplace actions before adoption; prefer actions from the `actions/` organization.

## Security

### Secret Management

- Store all sensitive values in GitHub Secrets; access via `${{ secrets.SECRET_NAME }}`.
- Use environment-specific secrets with protection rules and manual approvals for production.
- Never construct secrets dynamically or print them to logs.

### OIDC Authentication

- Use OpenID Connect for Azure, AWS, and GCP authentication instead of long-lived credentials.
- Configure trust policies in the cloud provider to trust GitHub's OIDC issuer.

### GITHUB_TOKEN Permissions

- Default to `contents: read` at the workflow level.
- Grant `write` scopes only on jobs that need them (e.g., `packages: write` for publishing).

## Caching and Performance

- Cache package manager dependencies with `actions/cache` using `hashFiles` for cache keys.
- Use `restore-keys` for graceful fallback to older compatible caches.
- Use `actions/checkout` with `fetch-depth: 1` unless full history is needed.
- Use `strategy.matrix` to parallelize tests across environments or configurations.
- Upload test reports, coverage, and scan results as artifacts with appropriate `retention-days`.

## Testing

- Run unit tests early in the pipeline on every push and PR.
- Run integration tests after unit tests, using `services` for database or queue dependencies.
- Collect and publish test results (e.g., JUnit XML) as artifacts or GitHub Checks annotations.
- Track code coverage and enforce minimum thresholds.

## Deployment

- Use GitHub `environment` protection rules with required reviewers and branch restrictions.
- Deploy to staging automatically on merges to development branches.
- Keep previous successful artifacts and images available for fast rollback.

## Workflow Review Checklist

- [ ] Workflow `name` is descriptive and `on` triggers are scoped appropriately.
- [ ] `permissions` are set to least privilege at both workflow and job levels.
- [ ] `concurrency` is configured for deployment workflows.
- [ ] All `uses` actions are pinned to a full commit SHA.
- [ ] Secrets are accessed via `${{ secrets.* }}`; no hardcoded values.
- [ ] OIDC is used for cloud authentication where possible.
- [ ] Caching is configured for dependencies and build outputs.
- [ ] `fetch-depth: 1` is used for checkout unless full history is needed.
- [ ] Test results are published as artifacts or check annotations.
- [ ] Deployment environments have appropriate protection rules.
- [ ] `timeout-minutes` is set on long-running jobs.

---