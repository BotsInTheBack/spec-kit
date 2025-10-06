#!/usr/bin/env bash
#
# GitHub Project Creation Script
# =============================
#
# This script automates the setup of a new GitHub project with best practices.
# It's designed to be called by the /projectize slash command.
#
# Features:
# - Create repositories from GitHub templates
# - Auto-detect existing repositories
# - Create GitHub Projects with templates (kanban/table)
# - Set up branch protection rules
# - Configure standard files and workflows
# - Support for organizations and teams

set -euo pipefail

# Load common functions and variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
DEFAULT_BRANCH="main"
DEFAULT_LICENSE="MIT"
DEFAULT_PRIVACY="private"
DEFAULT_PROJECT_TEMPLATE="kanban"
AUTO_DETECT=true
FORCE=false
JSON_OUTPUT=false

# GitHub API configuration
GITHUB_API="https://api.github.com"

# Project templates
PROJECT_TEMPLATES=(
    "kanban" "Kanban board with To Do, In Progress, Done columns"
    "table" "Table view with status, priority, and assignee fields"
)

# Common repository templates
REPO_TEMPLATES=(
    "node" "Node.js with GitHub Actions"
    "python" "Python with pytest and GitHub Actions"
    "react" "React application with Vite"
    "nextjs" "Next.js application"
    "typescript" "TypeScript project"
    "go" "Go module"
    "rust" "Rust project with Cargo"
    "terraform" "Terraform module"
    "docker" "Docker project"
)

# Show help message
show_help() {
    cat <<EOF
GitHub Project Creation Tool (Internal Use)
=========================================

IMPORTANT: This script is designed to be used internally by the '/projectize' command
in the GitHub Spec Kit. Please use the '/projectize' command from your IDE's chat interface
for the best experience.

For end users, the recommended way to use this functionality is via the '/projectize' command:

  /projectize --name my-project --description "Project description"

Internal Documentation (for development purposes only):
----------------------------------------------------
This script automates the creation of GitHub projects with best practices,
including repository setup, project boards, and task tracking.

Internal Usage: $0 [options] [project-name]

Options:
  --name <name>            Project name (default: current directory name)
  --description <text>     Project description
  --private                Make repository private (default)
  --public                 Make repository public
  --org <org>              Organization name (default: current user)
  --repo-template <repo>   GitHub repo to use as template (owner/repo)
  --project-template <type> Project type (kanban/table, default: kanban)
  --feature-md <file>      Path to feature markdown file (default: .specify/features/current/feature.md)
  --license <license>      License type (MIT, Apache-2.0, etc.)
  --branch <name>          Default branch name (default: main)
  --team <team>            Grant access to a team (can be specified multiple times)
  --force                  Override auto-detection
  --no-auto-detect         Disable auto-detection
  --json                   Output in JSON format
  -h, --help               Show this help message

Project Templates:
  kanban                   Kanban board with To Do, In Progress, Done columns
  table                    Table view with status, priority, and assignee fields

Feature Markdown:
  The --feature-md option allows you to specify a markdown file containing
  tasks in checklist format. These tasks will be automatically added to your
  project board. Example:
    - [ ] Task 1
    - [ ] Task 2
    - [x] Completed task

Internal Examples (for development only):
  # Create a new project with Kanban board and tasks from feature.md
  $0 --name my-project --project-template kanban --feature-md .specify/features/current/feature.md

  # Create a public project in an organization with a team
  $0 --name our-app --org myorg --public --team @myorg/developers

  # Auto-detect existing repo and create a project
  $0  # Must be run from within a git repository

  # Create a project from a repository template
  $0 --name api-service --repo-template org/template-repo

  # Output in JSON format for programmatic use
  $0 --name my-project --json
EOF
}

# Parse command line arguments
parse_args() {
    TEAMS=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) PROJECT_NAME="$2"; shift 2 ;;
            --description) DESCRIPTION="$2"; shift 2 ;;
            --private) PRIVATE=true; shift ;;
            --public) PRIVATE=false; shift ;;
            --org) ORG="$2"; shift 2 ;;
            --repo-template) REPO_TEMPLATE="$2"; shift 2 ;;
            --project-template) PROJECT_TEMPLATE="$2"; shift 2 ;;
            --license) LICENSE="$2"; shift 2 ;;
            --branch) DEFAULT_BRANCH="$2"; shift 2 ;;
            --team) TEAMS+=("$2"); shift 2 ;;
            --feature-md) FEATURE_MD="$2"; shift 2 ;;
            --force) FORCE=true; shift ;;
            --no-auto-detect) AUTO_DETECT=false; shift ;;
            --json) JSON_OUTPUT=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) 
                # If the argument doesn't start with --, treat it as the project name
                if [[ "$1" != --* ]]; then
                    PROJECT_NAME="$1"
                    shift
                else
                    echo "Unknown option: $1"
                    show_help
                    exit 1
                fi
                ;;
        esac
    done
}

# List available templates
list_templates() {
    echo "Available repository templates:"
    echo ""
    for ((i=0; i<${#REPO_TEMPLATES[@]}; i+=2)); do
        printf "  %-15s %s\n" "${REPO_TEMPLATES[i]}" "${REPO_TEMPLATES[i+1]}"
    done
    echo ""
    
    echo "Available project templates:"
    echo ""
    for ((i=0; i<${#PROJECT_TEMPLATES[@]}; i+=2)); do
        printf "  %-15s %s\n" "${PROJECT_TEMPLATES[i]}" "${PROJECT_TEMPLATES[i+1]}"
    done
    echo ""
}

# Detect existing git repository
detect_git_repo() {
    if [ -d .git ]; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ $REMOTE_URL =~ github.com[/:]([^/]+)/([^/]+?)(\.git)?$ ]]; then
            REPO_OWNER=${BASH_REMATCH[1]}
            REPO_NAME=${BASH_REMATCH[2]%.git}
            echo "Detected GitHub repository: $REPO_OWNER/$REPO_NAME"
            return 0
        fi
    fi
    return 1
}

# Create repository from template
create_repo_from_template() {
    local template_owner=$(echo "$REPO_TEMPLATE" | cut -d/ -f1)
    local template_repo=$(echo "$REPO_TEMPLATE" | cut -d/ -f2)
    
    if [ -z "$ORG" ]; then
        gh repo create "$PROJECT_NAME" --template "$REPO_TEMPLATE" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --clone
        cd "$PROJECT_NAME" || exit 1
    else
        gh repo create "$ORG/$PROJECT_NAME" --template "$REPO_TEMPLATE" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --clone
        cd "$PROJECT_NAME" || exit 1
    fi
}

# Initialize a new git repository
init_repo() {
    if [ "$FORCE" = true ] || [ ! -d .git ]; then
        echo "Initializing git repository..."
        git init
        git checkout -b "${DEFAULT_BRANCH}"
        
        # Create basic README
        echo "# ${PROJECT_NAME}" > README.md
        
        # Add default .gitignore if it doesn't exist
        if [ ! -f .gitignore ]; then
            curl -s https://www.toptal.com/developers/gitignore/api/node > .gitignore 2>/dev/null || \
            echo "# Project files" > .gitignore
        fi
        
        # Add default LICENSE if specified
        if [ -n "${LICENSE}" ] && [ ! -f LICENSE ]; then
            curl -s -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/licenses/${LICENSE}" | \
                jq -r '.body' > LICENSE 2>/dev/null || \
                echo "# ${LICENSE} License" > LICENSE
        fi
        
        # Initial commit
        git add .
        git commit -m "Initial commit"
    fi
}

# Parse feature markdown and extract tasks
parse_feature_markdown() {
    local markdown_file="$1"
    local tasks=()
    
    if [ ! -f "$markdown_file" ]; then
        echo "Feature markdown file not found: $markdown_file"
        return 1
    fi
    
    # Extract tasks from markdown checklist items
    while IFS= read -r line; do
        if [[ "$line" =~ ^-\s*\[.\]\s*(.*) ]]; then
            tasks+=("${BASH_REMATCH[1]}")
        fi
    done < "$markdown_file"
    
    printf '%s\n' "${tasks[@]}"
}

# Create GitHub project with tasks from feature markdown
create_github_project() {
    local project_template="${PROJECT_TEMPLATE:-$DEFAULT_PROJECT_TEMPLATE}"
    local project_name="${PROJECT_NAME} Project"
    local repo_full_name="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
    local feature_md="${FEATURE_MD:-.specify/features/current/feature.md}"
    
    if [ -z "$repo_full_name" ]; then
        echo "Error: Not in a GitHub repository"
        return 1
    fi

    echo "Creating $project_template project: $project_name"
    
    # Create the project
    local project_output
    case $project_template in
        kanban)
            project_output=$(gh project create "$project_name" \
                --format json \
                --owner "$(echo $repo_full_name | cut -d/ -f1)" \
                --source "$repo_full_name" \
                --template "https://github.com/orgs/github/projects/1")
            ;;
        table)
            project_output=$(gh project create "$project_name" \
                --format json \
                --owner "$(echo $repo_full_name | cut -d/ -f1)" \
                --source "$repo_full_name" \
                --format table)
            ;;
        *)
            echo "Unknown project template: $project_template"
            return 1
            ;;
    esac
    
    # Extract project ID from output
    local project_id=$(echo "$project_output" | jq -r '.id' 2>/dev/null)
    
    if [ -n "$project_id" ] && [ -f "$feature_md" ]; then
        echo "Adding tasks from feature markdown..."
        
        # Create columns if needed (for kanban)
        local todo_column_id=""
        if [ "$project_template" = "kanban" ]; then
            todo_column_id=$(gh project column list $project_id --json id,name --jq '.[] | select(.name == "To do") | .id' 2>/dev/null)
            if [ -z "$todo_column_id" ]; then
                todo_column_id=$(gh project column create --project-id $project_id --name "To do" --format json | jq -r '.id')
            fi
        fi
        
        # Add tasks from markdown
        local task
        while IFS= read -r task; do
            if [ -n "$task" ]; then
                echo "Adding task: $task"
                if [ "$project_template" = "kanban" ] && [ -n "$todo_column_id" ]; then
                    gh project item-add $todo_column_id --title "$task"
                else
                    gh project item-create $project_id --title "$task"
                fi
            fi
        done < <(parse_feature_markdown "$feature_md")
    fi
    
    echo "$project_output"
}

# Set up team access
setup_team_access() {
    local repo_full_name="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
    
    if [ -z "$repo_full_name" ]; then
        echo "Error: Not in a GitHub repository"
        return 1
    fi
    
    for team in "${TEAMS[@]}"; do
        echo "Adding team '$team' to repository"
        gh api -X PUT \
            -H "Accept: application/vnd.github.v3+json" \
            "/orgs/$(echo $repo_full_name | cut -d/ -f1)/teams/$team/repos/$repo_full_name" \
            -f "permission=push"
    done
}

# Set up GitHub repository
setup_github_repo() {
    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) is required. Please install it first."
        exit 1
    fi
    
    # Check if we're already in a git repo with GitHub remote
    if [ "$AUTO_DETECT" = true ] && detect_git_repo; then
        echo "Using existing repository: $REPO_OWNER/$REPO_NAME"
        PROJECT_NAME=$REPO_NAME
        [ -z "$ORG" ] && ORG=$REPO_OWNER
        return 0
    fi
    
    # Create new repository from template if specified
    if [ -n "${REPO_TEMPLATE:-}" ]; then
        create_repo_from_template
        return $?
    fi
    
    # Create new repository
    if [ -n "${ORG:-}" ]; then
        gh repo create "${ORG}/${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    else
        gh repo create "${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    fi
    
    # Set branch protection rules if not from template
    if [ -z "${REPO_TEMPLATE:-}" ]; then
        gh api -X PUT \
            "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/${DEFAULT_BRANCH}/protection" \
            --input - << EOF
        {
            "required_status_checks": {
                "strict": true,
                "checks": ["build"]
            },
            "enforce_admins": true,
            "required_pull_request_reviews": {
                "required_approving_review_count": 1
            },
            "restrictions": null
        }
EOF
    fi
    if [ -n "${ORG:-}" ]; then
        gh repo create "${ORG}/${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    else
        gh repo create "${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    fi

    # Set branch protection rules (only if not using a template that might have its own rules)
    if [ -z "${TEMPLATE:-}" ] || [ "$TEMPLATE" = "none" ]; then
        gh api -X PUT \
            "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/${DEFAULT_BRANCH}/protection" \
            --input - << EOF
        {
            "required_status_checks": {
                "strict": true,
                "checks": ["build"]
            },
            "enforce_admins": true,
            "required_pull_request_reviews": {
                "required_approving_review_count": 1
            },
            "restrictions": null
        }
EOF
    fi

    # Create project board (skip if using a template that might create its own)
    if [ -z "${TEMPLATE:-}" ] || [ "$TEMPLATE" = "none" ]; then
        gh project create "${PROJECT_NAME} Project" \
            --format json \
            --owner "$(gh repo view --json owner -q .owner.login)" \
            --source "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
            --template "https://github.com/orgs/github/projects/1"
    fi
}

# Main function
main() {
    # Default values
    AUTO_DETECT=true
    FORCE=false
    JSON_OUTPUT=false
    PRIVATE=true
    
    parse_args "$@"
    
    # Set default project name to current directory name if not provided
    if [ -z "${PROJECT_NAME:-}" ]; then
        PROJECT_NAME=$(basename "$(pwd)")
    fi
    
    # Auto-detect repository if enabled
    if [ "$AUTO_DETECT" = true ]; then
        if detect_git_repo; then
            echo "Auto-detected repository: $REPO_OWNER/$REPO_NAME"
            PROJECT_NAME=$REPO_NAME
            [ -z "$ORG" ] && ORG=$REPO_OWNER
        fi
    fi
    
    # Initialize repository if not using a template
    if [ -z "${REPO_TEMPLATE:-}" ]; then
        init_repo
        
        # Set up GitHub repository if not in CI
        if [ -z "${CI:-}" ]; then
            setup_github_repo
        fi
    fi
    
    # Create GitHub project if not in CI
    if [ -z "${CI:-}" ]; then
        create_github_project
        
        # Set up team access if specified
        if [ ${#TEAMS[@]} -gt 0 ]; then
            setup_team_access
        fi
    fi
    
    # Output success message
    if [ "${JSON_OUTPUT}" = true ]; then
        repo_url=$(gh repo view --json url -q .url 2>/dev/null || echo "")
        echo '{"status": "success", "message": "Project initialized successfully", "url": "'$repo_url'"}'
    else
        echo "✅ Project '${PROJECT_NAME}' has been successfully initialized!"
        if [ -z "${CI:-}" ]; then
            repo_url=$(gh repo view --json url -q .url 2>/dev/null || echo "Not pushed to GitHub")
            echo "🌍 View your repository at: $repo_url"
        fi
    fi
}

# Run the script
main "$@"

# Files Created:
# - .github/workflows/ - CI/CD workflows
# - .github/ISSUE_TEMPLATE/ - Issue templates
# - .github/PULL_REQUEST_TEMPLATE/ - PR templates
# - .github/projects/ - Project configurations
# - .gitignore - Project ignores
# - README.md - Project documentation
# - LICENSE - Project license
# - .github/workflows/project-automation.yml - GitHub Actions workflow
# - .github/scripts/project-automator.js - Project automation logic
#
# Usage:
#   ./create-project.sh "My new project description"
#   ./create-project.sh --json "My new project description"
#

set -e

# Parse command line arguments
JSON_MODE=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --help|-h) echo "Usage: $0 [--json] <project_description>"; exit 0 ;;
        *) ARGS+=("$arg") ;;
    esac
done

PROJECT_DESCRIPTION="${ARGS[*]}"
if [ -z "$PROJECT_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] <project_description>" >&2
    exit 1
fi

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialised with --no-git.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within the repository." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

# Create a unique project identifier using timestamp and description slug
PROJECT_ID=$(echo "$PROJECT_DESCRIPTION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//')
PROJECT_ID="project-$(date +%Y%m%d%H%M%S)-${PROJECT_ID:0:20}"

# Create new git branch for this project (if git repository detected)
if [ "$HAS_GIT" = true ]; then
    git checkout -b "$PROJECT_ID"
else
    >&2 echo "[projectize] Warning: Git repository not detected; skipped branch creation for $PROJECT_ID"
fi

# Create project configuration file with user-defined settings
PROJECT_DIR=".github/projects"
mkdir -p "$PROJECT_DIR"
PROJECT_FILE="$PROJECT_DIR/$PROJECT_ID.yml"

# Enhanced interactive project configuration
echo "🔧 GitHub Project Creation Setup"
echo "================================="
echo ""
echo "Project Description: $PROJECT_DESCRIPTION"
echo ""

# Ask for project configuration with sensible defaults
read -p "Project Name (default: derived from description): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-$(echo "$PROJECT_DESCRIPTION" | head -c 50 | sed 's/ $//')}
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="New Project"
fi

read -p "Project Visibility (public/private) [public]: " PROJECT_VISIBILITY
PROJECT_VISIBILITY=${PROJECT_VISIBILITY:-public}

read -p "Template Repository (or leave empty for default): " TEMPLATE_REPO

read -p "Default columns (comma-separated) [Backlog,In Progress,In Review,Done]: " COLUMNS
COLUMNS=${COLUMNS:-"Backlog,In Progress,In Review,Done"}

# Advanced project configuration
read -p "Enable issue automation? (y/n) [y]: " ENABLE_ISSUE_AUTOMATION
ENABLE_ISSUE_AUTOMATION=${ENABLE_ISSUE_AUTOMATION:-y}

read -p "Enable PR automation? (y/n) [y]: " ENABLE_PR_AUTOMATION
ENABLE_PR_AUTOMATION=${ENABLE_PR_AUTOMATION:-y}

read -p "Auto-assign issues to project? (y/n) [y]: " AUTO_ASSIGN_ISSUES
AUTO_ASSIGN_ISSUES=${AUTO_ASSIGN_ISSUES:-y}

read -p "Default issue labels (comma-separated) [enhancement,bug,documentation]: " DEFAULT_LABELS
DEFAULT_LABELS=${DEFAULT_LABELS:-"enhancement,bug,documentation"}

# Create comprehensive project configuration YAML file
cat > "$PROJECT_FILE" << PROJECT_EOF
---
project_name: "$PROJECT_NAME"
project_description: "$PROJECT_DESCRIPTION"
project_visibility: "$PROJECT_VISIBILITY"
template_repository: "$TEMPLATE_REPO"
columns:
$(echo "$COLUMNS" | tr ',' '\n' | sed 's/^/- /')
automation_enabled: true
issue_automation: $(echo "$ENABLE_ISSUE_AUTOMATION" | tr '[:upper:]' '[:lower:]')
pr_automation: $(echo "$ENABLE_PR_AUTOMATION" | tr '[:upper:]' '[:lower:]')
auto_assign_issues: $(echo "$AUTO_ASSIGN_ISSUES" | tr '[:upper:]' '[:lower:]')
default_labels:
$(echo "$DEFAULT_LABELS" | tr ',' '\n' | sed 's/^/- /')
created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
created_by: "projectize-command"
PROJECT_EOF

# Create GitHub Actions workflow for project automation
WORKFLOW_FILE=".github/workflows/project-automation.yml"
if [ ! -f "$WORKFLOW_FILE" ] || [ ! -s "$WORKFLOW_FILE" ]; then
    cat > "$WORKFLOW_FILE" << 'WORKFLOW_EOF'
name: Project Automation
# Workflow to automatically manage GitHub Projects based on repository events
# Triggers on issues, pull requests, and project card events
# Sets up automated project management and status updates

on:
  issues:
    types: [opened, labeled, assigned]
  pull_request:
    types: [opened, closed, merged]
  project_card:
    types: [created, moved]

jobs:
  automate-project:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'

    - name: Install dependencies
      run: npm install @octokit/rest js-yaml

    - name: Run project automation
      run: node .github/scripts/project-automator.js
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
WORKFLOW_EOF
fi

# Create enhanced project automator script for handling GitHub API interactions
AUTOMATOR_SCRIPT=".github/scripts/project-automator.js"
mkdir -p ".github/scripts"
cat > "$AUTOMATOR_SCRIPT" << 'SCRIPT_EOF'
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN
});

async function main() {
  try {
    // Get project configurations from .github/projects/ directory
    const projectsDir = path.join(process.cwd(), '.github', 'projects');
    if (!fs.existsSync(projectsDir)) {
      console.log('No project configurations found');
      return;
    }

    const projectFiles = fs.readdirSync(projectsDir)
      .filter(file => file.endsWith('.yml'));

    for (const projectFile of projectFiles) {
      const projectConfig = path.join(projectsDir, projectFile);
      const config = yaml.load(
        fs.readFileSync(projectConfig, 'utf8')
      );

      await processProject(config);
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

async function processProject(config) {
  console.log(`Processing project: ${config.project_name}`);

  try {
    // Get repository information
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) {
      console.log('Could not determine repository information');
      return;
    }

    // Create or update GitHub Project
    const project = await ensureProjectExists(config, repoInfo);
    if (!project) {
      console.log('Failed to create or find project');
      return;
    }

    // Set up project columns
    await setupProjectColumns(project.id, config.columns);

    // Set up automation rules
    await setupAutomationRules(project.id, config);

    // Process existing issues and PRs
    await processExistingIssues(project.id, config);
    await processExistingPRs(project.id, config);

    console.log(`✅ Project "${config.project_name}" is ready!`);
    console.log(`   Project URL: ${project.url}`);
    console.log(`   Columns: ${config.columns.join(', ')}`);

  } catch (error) {
    console.error(`Error processing project ${config.project_name}:`, error);
  }
}

async function getRepositoryInfo() {
  try {
    // Get repository information from git
    const { execSync } = require('child_process');
    const remoteUrl = execSync('git config --get remote.origin.url', { encoding: 'utf8' }).trim();
    const urlMatch = remoteUrl.match(/github\.com[:/]([^/]+)\/([^/.]+)/);
    if (!urlMatch) return null;

    const [, owner, repo] = urlMatch;
    return { owner, repo };
  } catch (error) {
    console.error('Error getting repository info:', error);
    return null;
  }
}

async function ensureProjectExists(config, repoInfo) {
  try {
    // Check if project already exists
    const { data: projects } = await octokit.projects.listForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo
    });

    // Look for existing project with matching name
    let existingProject = projects.find(p => p.name === config.project_name);

    if (existingProject) {
      console.log(`Found existing project: ${existingProject.name}`);
      return existingProject;
    }

    // Create new project
    console.log(`Creating new project: ${config.project_name}`);
    const { data: newProject } = await octokit.projects.createForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      name: config.project_name,
      body: config.project_description
    });

    return newProject;
  } catch (error) {
    console.error('Error creating/finding project:', error);
    return null;
  }
}

async function setupProjectColumns(projectId, columns) {
  try {
    // Get existing columns
    const { data: existingColumns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    // Create default columns if they don't exist
    for (const columnName of columns) {
      const existingColumn = existingColumns.find(col => col.name === columnName);
      if (!existingColumn) {
        await octokit.projects.createColumn({
          project_id: projectId,
          name: columnName
        });
        console.log(`Created column: ${columnName}`);
      }
    }
  } catch (error) {
    console.error('Error setting up columns:', error);
  }
}

async function setupAutomationRules(projectId, config) {
  // This would set up GitHub's built-in automation rules
  // For now, we'll handle automation in the workflow
  console.log('Automation rules will be configured in the workflow');
}

async function processExistingIssues(projectId, config) {
  if (config.auto_assign_issues !== 'true') return;

  try {
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) return;

    // Get open issues
    const { data: issues } = await octokit.issues.listForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      state: 'open'
    });

    // Get project columns to find the first column (usually Backlog)
    const { data: columns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    if (columns.length === 0) return;

    const firstColumn = columns[0];

    // Add issues to project
    for (const issue of issues) {
      if (issue.pull_request) continue; // Skip PRs

      // Add issue to project
      await octokit.projects.createCard({
        column_id: firstColumn.id,
        note: `Issue #${issue.number}: ${issue.title}`
      });

      console.log(`Added issue #${issue.number} to project`);
    }
  } catch (error) {
    console.error('Error processing existing issues:', error);
  }
}

async function processExistingPRs(projectId, config) {
  if (config.pr_automation !== 'true') return;

  try {
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) return;

    // Get open PRs
    const { data: prs } = await octokit.pulls.list({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      state: 'open'
    });

    // Get project columns to find appropriate column
    const { data: columns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    const inProgressColumn = columns.find(col => col.name === 'In Progress') || columns[0];

    // Add PRs to project
    for (const pr of prs) {
      await octokit.projects.createCard({
        column_id: inProgressColumn.id,
        note: `PR #${pr.number}: ${pr.title}`
      });

      console.log(`Added PR #${pr.number} to project`);
    }
  } catch (error) {
    console.error('Error processing existing PRs:', error);
  }
}

main();
SCRIPT_EOF

# Output results based on mode
if $JSON_MODE; then
    printf '{"BRANCH_NAME":"%s","PROJECT_FILE":"%s","PROJECT_ID":"%s"}\n' "$PROJECT_ID" "$PROJECT_FILE" "$PROJECT_ID"
else
    echo "✅ Project configuration created: $PROJECT_FILE"
    echo "✅ GitHub Actions workflow created: $WORKFLOW_FILE"
    echo "✅ Project automator script created: $AUTOMATOR_SCRIPT"
    echo ""
    echo "BRANCH_NAME: $PROJECT_ID"
    echo "PROJECT_FILE: $PROJECT_FILE"
    echo "PROJECT_ID: $PROJECT_ID"
    echo ""
    echo "Next steps:"
    echo "1. Review and customize the project configuration in $PROJECT_FILE"
    echo "2. The GitHub Actions workflow will automatically create and manage your GitHub Project"
    echo "3. Issues and PRs will be automatically added to the project"
    echo "4. Project cards will move automatically based on status changes"
fi
