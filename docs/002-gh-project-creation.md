# GitHub Project Setup Guide

This guide will help you set up and manage GitHub Projects for your repository.

## Prerequisites

1. GitHub CLI (`gh`) installed and authenticated
2. Owner or admin access to the repository
3. Fine-grained Personal Access Token (PAT) with appropriate permissions

## 1. Initial Setup

### Install GitHub CLI

```bash
# On Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh
```

### Authenticate with GitHub

```bash
gh auth login
# Follow the prompts to authenticate
```

## 2. Create a New Project

### Create Project via CLI

```bash
# Navigate to your repository
cd /path/to/your/repository

# Create a new project
gh project create --title "Project Name" \
  --description "Project description" \
  --visibility PRIVATE \
  --format json
```

### Or Create via Web UI

1. Go to your repository on GitHub
2. Click on "Projects" in the top navigation
3. Click "New project"
4. Choose a template or start from scratch
5. Configure project settings and click "Create"

## 3. Configure Project Automation

### Create Automation Workflow

Create `.github/workflows/project-automation.yml`:

```yaml
name: Project Automation

on:
  issues:
    types: [opened, labeled, closed, reopened]
  pull_request:
    types: [opened, closed, labeled, unlabeled]

jobs:
  sync-to-project:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/add-to-project@v0.5.0
        with:
          project-url: "https://github.com/orgs/your-org/projects/YOUR_PROJECT_NUMBER"
          github-token: ${{ secrets.GITHUB_TOKEN }}
          labeled: ""
          label-operator: OR
```

## 4. Initialize Project Structure

### Add Columns to Project

```bash
# Get project ID
PROJECT_ID=$(gh project list --json id,title -q '.[] | select(.name=="Project Name") | .id')

# Add columns
gh project column-create $PROJECT_ID --name "To Do"
gh project column-create $PROJECT_ID --name "In Progress"
gh project column-create $PROJECT_ID --name "In Review"
gh project column-create $PROJECT_ID --name "Done"
```

## 5. Working with Issues and Tasks

### Create a New Task

```bash
gh issue create --title "Task title" \
  --body "Detailed description of the task" \
  --label "enhancement" \
  --project "Project Name"
```

### Move an Issue to a Column

```bash
# Get column ID
COLUMN_ID=$(gh project column-list $PROJECT_ID --json id,name -q '.[] | select(.name=="In Progress") | .id')

# Move issue to column
gh project item-edit --id ISSUE_ID --column-id $COLUMN_ID
```

## 6. Useful Commands

### List Projects

```bash
gh project list
```

### View Project Details

```bash
gh project view PROJECT_NUMBER
```

### List Issues in Project

```bash
gh issue list --project "Project Name"
```

### Open Project in Browser

```bash
gh project view --web
```

## 7. Best Practices

1. **Branch Naming**: Use consistent naming (e.g., `feature/001-description`)
2. **Issue Templates**: Create issue templates for different task types
3. **Labels**: Use labels consistently for categorization
4. **Milestones**: Group related issues into milestones
5. **Automation**: Use GitHub Actions to automate workflows

## 8. Troubleshooting

### Common Issues

- **Permission denied**: Ensure your PAT has the correct permissions
- **Project not found**: Verify the project name and your access level
- **Sync issues**: Check GitHub Actions workflow runs for errors

### View Logs

```bash
gh run list --workflow=project-automation.yml
gh run view RUN_ID --log
```

## Additional Resources

- [GitHub Projects Documentation](https://docs.github.com/en/issues/planning-and-tracking-with-projects)
- [GitHub CLI Reference](https://cli.github.com/manual/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
