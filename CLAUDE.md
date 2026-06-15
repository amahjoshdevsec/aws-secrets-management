# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository.

## Current state of the repository

This repository is in its initial/scaffold stage. As of now it contains only:

- `README.md` — placeholder, just the project title (`# aws-secrets-management`)
- `LICENSE` — MIT License
- `CLAUDE.md` — this file

There is **no application code, configuration, infrastructure-as-code, or
tests yet**. There is no defined language, framework, build system, or
package manager — do not assume one (e.g., don't assume Python/Node/Terraform
tooling exists, run linters, or invoke a test runner) until the relevant
files (e.g., `requirements.txt`, `package.json`, `*.tf`, `Makefile`, CI
config) are actually present in the repo.

## Inferred purpose

Based on the repository name, this project is intended to manage AWS secrets
— likely involving AWS Secrets Manager and/or AWS Systems Manager Parameter
Store, possibly with infrastructure-as-code (Terraform/CloudFormation/CDK)
and/or scripts/automation for creating, rotating, and accessing secrets.
Treat this as a working hypothesis, not a confirmed architecture — confirm
with the user before committing to a specific stack (e.g., Terraform vs CDK,
Python vs TypeScript) if it materially affects a task.

## Working in this repo

- Before adding new tooling or scaffolding (a language runtime, IaC
  framework, dependency manager, CI pipeline, etc.), check with the user if
  the choice isn't already implied by an explicit request — these decisions
  are foundational and hard to change later.
- When code/config is added, update this CLAUDE.md to describe:
  - The actual directory layout and what each top-level directory contains
  - How to install dependencies, build, lint, and run tests
  - Conventions for managing AWS credentials/secrets locally (never commit
    real secrets, `.env` files, AWS credentials, or state files)
  - Any IaC workflow (e.g., `terraform plan`/`apply` conventions, required
    backends/state storage, environment separation)
- Given the subject matter, be especially careful not to introduce, log, or
  commit real AWS credentials, secret values, ARNs tied to real accounts, or
  `.tfstate`/`.tfvars` files containing sensitive data. Use placeholders and
  `.gitignore` entries for anything sensitive.

## Git workflow

- Default branch: `main`
- Development for this task occurs on `claude/claude-md-docs-xesnue`
