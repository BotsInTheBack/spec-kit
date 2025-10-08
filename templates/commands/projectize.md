---
description: Interactively manage GitHub project boards with task import from .specify/features
scripts:
  # These scripts MUST be used - they enforce interactive mode
  sh: scripts/bash/github-project.sh --interactive
  ps: scripts/powershell/github-project.ps1 -Interactive
---

## MANDATORY EXECUTION RULES

### INTERACTIVE MODE REQUIRED
- This command MUST be run in interactive mode
- The `--interactive` flag is automatically enforced
- Any attempt to bypass interactive mode will result in an error

### USAGE
Simply run:
```
/projectize
```

### INTERACTIVE WORKFLOW
1. The script will guide you through:
   - Creating a new project board OR selecting an existing one
   - Choosing a template (kanban, bug-triage, or basic)
   - Importing tasks from `.specify/features`
   - Configuring project settings

2. Required Inputs:
   - Project name
   - Project scope (user/org)
   - Template selection
   - Task import confirmation

### VALIDATION CHECKS
- [ ] GitHub CLI authentication
- [ ] Repository access
- [ ] `.specify/features` directory
- [ ] Project board permissions

### NEXT STEPS
After project creation:
1. Review the imported tasks
2. Customize columns if needed
3. Set up automation rules
4. Share with your team

### GETTING HELP
- Type `?` at any prompt for help
- Use arrow keys to navigate menus
- Press Enter to confirm selections
- Ctrl+C to cancel at any time
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
