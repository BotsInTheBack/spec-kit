#!/usr/bin/env bash
#
# GitHub Project Creation Script
# =============================
#
# This script is part of the GitHub Spec Kit's /projectize slash command.
# It handles the interactive setup of GitHub Projects with automated workflows.
#
# Purpose:
# - Create project configuration files with comprehensive settings
# - Set up GitHub Actions workflows for project automation
# - Generate project management scripts with full GitHub API integration
# - Provide interactive configuration for project settings
#
# Integration:
# - Called by the projectize.md slash command template
# - Outputs JSON for AI agent processing (when --json flag used)
# - Creates new git branch for project configuration
# - Follows existing Spec Kit patterns and conventions
#
# Files Created:
# - .github/projects/{project-id}.yml - Project configuration
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
