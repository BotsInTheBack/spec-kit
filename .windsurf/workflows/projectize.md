---
description: Initialize a GitHub project with best practices, including repository setup, project boards, and task tracking.
scripts:
  sh: scripts/bash/create-github-project.sh
  ps: scripts/powershell/create-github-project.ps1
---

The user input to you can be provided directly by the agent or as a command argument - you **MUST** consider it before proceeding with the prompt (if not empty).

User input:

$ARGUMENTS

## Overview
Initialize a GitHub project with best practices, including:
- Repository setup
- Project boards
- Task tracking
- Standard files and workflows

## Usage
`/projectize [project-name] [options]`

## Options
- `--template [template-name]`: Use a specific template (default: basic)
- `--private`: Create a private repository
- `--org [org-name]`: Create under a specific organization

## Examples
- `/projectize my-project`
- `/projectize my-org/my-project --template nodejs --private`

## Workflow
1. Creates a new GitHub repository
2. Sets up a project board with standard columns
3. Initializes with recommended files (README, LICENSE, etc.)
4. Configures branch protection rules
5. Sets up GitHub Actions workflows
