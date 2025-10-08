---
description: Create a GitHub project board from existing specs and tasks
scripts:
  # The agent will automatically select the appropriate script based on OS
  sh: scripts/bash/github-project.sh
  ps: scripts/powershell/github-project.ps1
---

## Execution Rules
- The agent will automatically detect the OS and use the appropriate script
- On Windows: PowerShell script will be used
- On Unix-like (Linux, macOS): Bash script will be used
- No additional wrapper scripts are needed
- Follow the agent's standard behavior for script execution
- DO NOT create a new repository - only work with existing ones
- Source all tasks from the `specify/Features` directory

## Usage

```
# Create a kanban board for the current repository (default)
/projectize add-board --name "Project Board" --template kanban
```

## Available Templates
- `kanban`: Backlog, To Do, In Progress, In Review, Done
- `basic`: To Do, In Progress, Done
- `bug-triage`: Reported, Needs Triage, In Progress, Needs Fix, Resolved

## Available Templates
- `kanban`: Backlog, To Do, In Progress, In Review, Done
- `basic`: To Do, In Progress, Done
- `bug-triage`: Reported, Needs Triage, In Progress, Needs Fix, Resolved

## Requirements
- Must be run from within a git repository
- GitHub CLI (`gh`) installed and authenticated
- jq (for JSON processing)

## Notes
- The script will automatically detect the current repository
- All actions are logged for reference
- No repository will be created - this only works with existing repositories
- The project board will be populated from the `specify/Features` directory
- Each feature spec will be converted into project board items
- Tasks will be extracted from the spec files and added as checkable items
