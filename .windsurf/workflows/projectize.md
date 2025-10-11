---
description: Interactive GitHub project board management with task import from .specify/features
scripts:
  # These scripts should be called without interactive flags to use their default behavior
  sh: scripts/bash/github-project.sh
  ps: scripts/powershell/github-project.ps1
---

# GitHub Project Board Manager

An interactive tool for creating and managing GitHub project boards with seamless task import from `.specify/features`.

## ✨ Features

- **Interactive CLI** with intuitive prompts and menus
- **Multiple Templates**: Kanban, Basic, and Bug Triage workflows
- **Flexible Scope**: Create projects in personal accounts or organizations
- **Task Import**: Automatically import tasks from `.specify/features`
- **Smart Defaults**: Suggests names and configurations based on your repository

## 🚀 Getting Started

### Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated
- [jq](https://stedolan.github.io/jq/) for JSON processing
- Git repository with a remote origin
- (Optional) PowerShell 7.0+ for Windows users

### Quick Start

```bash
# Start interactive mode (recommended)
/projectize

# Or use the underlying script directly
./scripts/bash/github-project.sh --interactive
```

## 🖥️ Interactive Mode

The interactive mode will guide you through the entire process:

1. **Authentication**
   - Verifies GitHub CLI authentication
   - Checks for required tools
   - Detects repository information

2. **Project Scope**
   - Choose between personal account or organization
   - Lists available organizations with pagination
   - Shows current repository context

3. **Board Management**
   - View existing project boards with details
   - Create new boards with custom templates
   - Import tasks from `.specify/features`

4. **Project Board Configuration**
   - Customize board name (with smart defaults)
   - Select from streamlined project board templates:
     - **Basic Kanban**: Simple To Do, In Progress, Done workflow
     - **Feature Development**: Backlog, Ready, In Progress, Review, Done
     - **Agile Sprint**: Sprint Backlog, In Progress, Review, Done
     - **Bug Triage**: Triage, In Progress, Needs Review, Done
     - **DevOps**: To Do, Development, Staging, Production, Done

## 🛠️ Non-Interactive Usage

For scripting and automation, use these flags:

```bash
# Basic usage with required fields
./github-project.sh --name "My Project" --template kanban

# Create in an organization
./github-project.sh --name "Team Project" --org myorg --scope org

# Import tasks from .specify/features
./github-project.sh --import-tasks --name "Feature Tasks"

# Skip all confirmation prompts
./github-project.sh --name "Quick Project" --yes
```

### Available Options

```
  -n, --name NAME        Project board name (default: auto-generated)
  -t, --template TPL     Template (kanban, basic, bug-triage)
  -s, --scope SCOPE      Project scope: user, org, or auto (default)
  -o, --org ORG          Organization name (required for org scope)
  -y, --yes              Skip all confirmation prompts
  -i, --interactive      Enable interactive mode
      --import-tasks     Import tasks from .specify/features
  -v, --verbose          Enable verbose output
  -h, --help             Show this help message
```

## 🔍 Task Import

The tool provides a streamlined task import process from `.specify/features`:

1. Scans for `.md` files in `.specify/features/`
2. Shows a preview of each task with the first few lines
3. Displays the total number of tasks found
4. Asks for confirmation before importing
5. Creates GitHub issues for each task
6. Adds them to your project board

### Task File Format

```markdown
# Task Title

## Description
Detailed description of the task

## Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2
```

## 🛡️ Error Handling & Validation

- Validates inputs at each step
- Provides clear, actionable error messages
- Suggests fixes for common issues
- Graceful exit on user cancellation

## 🔄 Automation & CI/CD

Example GitHub Actions workflow:

```yaml
name: Create Project Board

on:
  workflow_dispatch:
    inputs:
      project_name:
        description: 'Project name'
        required: true

defaults:
  run:
    working-directory: ./your-repo

jobs:
  create-project:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up GitHub CLI
        uses: actions/setup-go@v3
        with:
          go-version: '1.19'
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq
      
      - name: Create project board
        run: |
          ./scripts/bash/github-project.sh \
            --name "${{ github.event.inputs.project_name }}" \
            --template kanban \
            --yes
```

## 📝 Notes

- Project boards are created with appropriate permissions
- Organization projects require admin access
- Interactive mode provides the best user experience
- Use `Ctrl+C` to cancel at any time

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request
  - In Progress
  - In Review
  - Done
- [ ] Show each major step with success/failure
- [ ] Provide clear error messages if any step fails
- [ ] Import tasks from `.specify/features`
- [ ] Set up basic GitHub Actions workflow for CI/CD

### 4. Verification Phase
- [ ] Validate all resources were created
- [ ] Generate summary of changes including:
  - Project board URL
  - Number of tasks imported
  - Columns created
  - Any warnings or important notes
- [ ] Provide next steps for the user

## Available Templates
- `kanban`: Backlog, To Do, In Progress, In Review, Done
- `basic`: To Do, In Progress, Done
- `bug-triage`: Reported, Needs Triage, In Progress, Needs Fix, Resolved

## Requirements
- Must be run from within a git repository
- GitHub CLI (`gh`) installed and authenticated
- jq (for JSON processing)

## Usage Examples

```bash
# Basic usage (interactive)
/projectize "Feature 123"

# Dry run (no changes)
/projectize "Feature 123" --dry-run

# Non-interactive (fails if any validation fails)
/projectize "Feature 123" --yes
```

## Output Rules

### Success Case (Non-verbose)
```
✅ Project created successfully!
📋 Project Board: https://github.com/org/repo/projects/1
📊 Tasks imported: 15
📌 Columns: To Do, In Progress, In Review, Done

🔗 Quick Links:
- [View Board](https://github.com/org/repo/projects/1)
- [Add Team Members](https://github.com/org/repo/settings/access)
```

### Success Case (Verbose)
```
✅ Project created successfully!

📋 Project Details:
- Project Board: https://github.com/org/repo/projects/1
- Tasks Imported: 15 from .specify/features/
- Template: Kanban
- Columns: To Do, In Progress, In Review, Done

🔍 Verification:
✓ Project board created successfully
✓ All tasks imported without errors
✓ GitHub Actions workflow configured
✓ Repository permissions verified

📌 Next Steps:
1. Review the project board: [Open Board](https://github.com/org/repo/projects/1)
2. Add team members: [Manage Access](https://github.com/org/repo/settings/access)
3. Set up branch protection if needed
4. Push your first commit to trigger CI/CD

💡 Pro Tip: Use 'gh project edit 1 --add-issue <issue-number>' to add existing issues
```

### Error Case
```
❌ Project creation failed:
  - GitHub CLI not authenticated
  - .specify/features directory not found

💡 To fix:
1. Run: gh auth login
2. Create .specify/features directory
3. Try again
```

## Agent Instructions

1. **ESSENTIAL FEEDBACK**
   - Show progress for each major phase
   - Include clear status messages
   - Show success/failure for critical operations
   - Keep output concise but informative

2. **ERROR HANDLING**
   - Catch and handle all errors silently
   - Only show error messages to the user
   - Always include a suggested fix for errors

3. **VERBOSE MODE**
   - Only show detailed output when --verbose flag is used
   - In verbose mode, include step-by-step progress
   - Always prefer less output over more

## Notes
- The script will automatically detect the current repository
- All actions are logged for reference
- No repository will be created - this only works with existing repositories
- The project board will be populated from the `.specify/features` directory
- Each feature spec will be converted into project board items
- Tasks will be extracted from the spec files and added as checkable items
