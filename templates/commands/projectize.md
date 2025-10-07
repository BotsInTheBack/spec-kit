---
description: >
  Initialize a GitHub project based on task specifications from the `/tasks` command.
  This command creates a project board with tasks automatically populated from the
  current feature's `tasks.md` file, creating a seamless workflow from specification to project management.

  ## Typical Workflow
  1. `/specify` - Define feature requirements
  2. `/plan` - Create technical implementation plan
  3. `/tasks` - Generate detailed tasks
  4. `/projectize` - Create project board with tasks

  ## Key Features
  - Creates a GitHub project board from your `tasks.md`
  - Imports tasks with their hierarchy and checklists
  - Sets up standard columns (To Do, In Progress, Done)
  - Configures repository settings and branch protection
  - Integrates with CI/CD workflows

# GitHub Project Creation Command
# =============================
#
# The `/projectize` command automates the setup of new GitHub projects with best practices.
# It creates a fully configured repository with standard files, branch protection, and automation.
#
# Features:
# - 🚀 One-command project initialization
# - 🔒 Automatic branch protection
# - 📋 Standard project files (README, LICENSE, .gitignore)
# - 🏗️ Project board setup with tasks from feature specifications
# - 🔄 CI/CD workflow configuration
# - 🔍 Code quality and security scanning
# - 📝 Issue and PR templates
# - 🔄 Automated dependency updates
#

## Command Parameters

### Required
- `--name`, `-n` <name>        Project name (defaults to current directory name)

### Optional
- `--tasks-md` <file>          Path to tasks markdown file (default: .specify/features/current/tasks.md)
- `--description`, `-d` <text>  Project description
- `--private`, `-p`             Make repository private (default: true)
- `--public`                    Make repository public
- `--org`, `-o` <org>           Organization/username (default: current user)
- `--template`, `-t` <type>     Project template (kanban, table, default: kanban)
- `--branch`, `-b` <name>       Default branch name (default: main)
- `--team` <team>               Grant access to a team (can be specified multiple times)
- `--json`                      Output in JSON format for programmatic use
- `--help`, `-h`                Show help message

> **Note:** The `--tasks-md` parameter is typically not needed as the command will automatically
> look for `tasks.md` in the current feature directory (`.specify/features/current/`).

> **Note:** The `--tasks-md` parameter is typically not needed as the command will automatically
> look for `tasks.md` in the current feature directory (`.specify/features/current/`).

## Examples

### Basic Usage
After running `/tasks`, create a project with the generated tasks:
```
/projectize --name my-feature
```

### With Custom Tasks File
```
/projectize --name my-feature --tasks-md path/to/tasks.md
```

### Organization Project with Team Access
```
/projectize --name api-service --org myorg --team "@myorg/developers"
```

### Using Table View Instead of Kanban
```
/projectize --name my-feature --template table
```

### Auto-detect from Current Repository
```
# Run from within a git repository
/projectize
```
#   /projectize --name api-service --template node --auto-merge --no-wiki

# Implementation Details
# ====================
#
# The command performs the following actions:
#
# 1. Repository Setup:
#    - Creates a new git repository or uses existing one
#    - Initializes with a template-based project structure
#    - Sets up standard files (README.md, .gitignore, LICENSE)
#    - Configures repository settings (wiki, issues, projects)
#    - Sets up team access and permissions
#
# 2. GitHub Configuration:
#    - Creates repository on GitHub (if not exists)
#    - Sets up branch protection rules
#    - Configures default branch
#    - Creates project board
#
# 3. Workflow Automation:
#    - Sets up CI/CD workflows based on template
#    - Configures code quality and security scanning
#    - Enables automated dependency updates
#    - Configures auto-merge for PRs if enabled
#    - Sets up branch protection rules
#
# 4. Project Management:
#    - Creates issue and PR templates
#    - Sets up project board (Kanban by default)
#    - Configures code owners and teams
#    - Adds contribution guidelines and code of conduct
#    - Sets up security policies
#
# 5. Documentation:
#    - Generates initial README with badges
#    - Adds development setup instructions
#    - Includes contribution guidelines
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - GitHub API error
#   4 - File system error
#
# Environment Variables:
#   GITHUB_TOKEN    - Required for GitHub API access
#   GIT_AUTHOR_NAME - Used for git configuration
#   GIT_AUTHOR_EMAIL - Used for git configuration

scripts:
  sh: scripts/bash/create-github-project.sh --json "{ARGS}"
  ps: scripts/powershell/create-github-project.ps1 -Json "{ARGS}"
---

The user input to you can be provided directly by the agent or as a command argument - you **MUST** consider it before proceeding with the prompt (if not empty).

User input:

$ARGUMENTS

The text the user typed after `/projectize` in the triggering message **is** the project description or requirements. Assume you always have it available in this conversation even if `{ARGS}` appears literally below. Do not ask the user to repeat it unless they provided an empty command.

Given that project description, do this:

## How It Works

### 1. Task Parsing
- Reads the `tasks.md` file generated by `/tasks`
- Preserves task hierarchy and checklists
- Converts markdown tasks to GitHub project items

### 2. Project Board Setup
- Creates a new GitHub project (or updates existing)
- Configures columns based on the selected template
- Sets up workflow automation rules

### 3. Task Import
- Creates cards for top-level tasks
- Adds subtasks as checklist items
- Preserves task relationships and priorities

## Integration with Other Commands

### /specify → /projectize
- Feature specifications inform project structure
- Requirements are mapped to project epics
- Acceptance criteria become task checklists

### /plan → /projectize
- Technical decisions inform project templates
- Architecture diagrams can be linked to tasks
- Dependencies between tasks are preserved

### /tasks → /projectize
- Tasks are imported directly from `tasks.md`
- Task priorities and assignments are preserved
- Progress tracking is automatically set up

### /implement → /projectize
- Tracks implementation progress
- Updates task status based on branch activity
- Links pull requests to project cards
5. Report completion with branch name, project configuration, and next steps.

Note: The script creates and checks out the new branch and initializes the project configuration before setup.
