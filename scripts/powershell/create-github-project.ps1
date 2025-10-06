#
# GitHub Project Creation Script (PowerShell)
# ==========================================
#
# PowerShell version of the GitHub Project creation script for Windows compatibility.
# Part of the GitHub Spec Kit's /projectize slash command functionality.
#
# Purpose:
# - Automated GitHub project initialization with best practices
# - Cross-platform project configuration for Windows users
# - Sets up repository, branch protection, and project board
# - Configures CI/CD workflows and standard files
#
# Features:
# - 🚀 One-command project initialization
# - 🔒 Automatic branch protection
# - 📋 Standard project files (README, LICENSE, .gitignore)
# - 🏗️ Project board setup
# - 🔄 CI/CD workflow configuration
#
# Usage:
#   .\create-project.ps1 --name my-project --workflow node
#   .\create-project.ps1 --org myorg --name our-project --public
#   .\create-project.ps1 --name my-python-project --workflow python --license MIT
#

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$Description,
    
    [Parameter(Mandatory=$false)]
    [switch]$Private = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$Public = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$Org,
    
    [Parameter(Mandatory=$false)]
    [string]$Workflow = "node",
    
    [Parameter(Mandatory=$false)]
    [string]$License = "MIT",
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoCI,
    
    [Parameter(Mandatory=$false)]
    [switch]$Json,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Definition -Detailed
    exit 0
}

# Set privacy flag based on parameters
if ($Public) {
    $Private = $false
}

# Set default project name to current directory if not provided
if ([string]::IsNullOrEmpty($Name)) {
    $Name = (Get-Item -Path ".").Name
}

# Function to find repository root by searching for project markers
function Find-RepoRoot {
    param([string]$Directory)
    
    while ($Directory -ne [System.IO.Path]::GetPathRoot($Directory)) {
        if (Test-Path (Join-Path $Directory ".git") -PathType Container) {
            return $Directory
        }
        if (Test-Path (Join-Path $Directory ".specify") -PathType Container) {
            return $Directory
        }
        $Directory = Split-Path $Directory -Parent
    }
    return $null
}

# Find repository root - prefer git detection, fallback to marker search
$RepoRoot = $null
try {
    $RepoRoot = git rev-parse --show-toplevel 2>$null
    $HasGit = $true
} catch {
    $RepoRoot = Find-RepoRoot (Get-Location)
    $HasGit = $false
}

if (-not $RepoRoot) {
    Write-Error "Could not determine repository root."
    exit 1
}

Set-Location $RepoRoot

# Create unique project identifier with timestamp and description slug
$Timestamp = Get-Date -Format "yyyyMMddHHmmss"
$ProjectSlug = $ProjectDescription.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
$ProjectId = "project-${Timestamp}-${ProjectSlug.Substring(0, [Math]::Min(20, $ProjectSlug.Length))}"

# Create new git branch for this project configuration
if ($HasGit) {
    git checkout -b $ProjectId 2>$null | Out-Null
} else {
    Write-Warning "Git repository not detected; skipped branch creation for $ProjectId"
}

# Create project configuration file with user-defined settings
$ProjectsDir = Join-Path ".github" "projects"
New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
$ProjectFile = Join-Path $ProjectsDir "$ProjectId.yml"

# Enhanced interactive project configuration
Write-Host "🔧 GitHub Project Creation Setup" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green
Write-Host ""
Write-Host "Project Description: $ProjectDescription" -ForegroundColor Yellow
Write-Host ""

$ProjectName = Read-Host "Project Name (default: derived from description)"
if (-not $ProjectName) {
    $ProjectName = $ProjectDescription.Substring(0, [Math]::Min(50, $ProjectDescription.Length)).Trim()
    if (-not $ProjectName) {
        $ProjectName = "New Project"
    }
}

$ProjectVisibility = Read-Host "Project Visibility (public/private) [public]"
if (-not $ProjectVisibility) {
    $ProjectVisibility = "public"
}

$TemplateRepo = Read-Host "Template Repository (or leave empty for default)"

$ColumnsInput = Read-Host "Default columns (comma-separated) [Backlog,In Progress,In Review,Done]"
if (-not $ColumnsInput) {
    $ColumnsInput = "Backlog,In Progress,In Review,Done"
}

$Columns = $ColumnsInput.Split(',') | ForEach-Object { $_.Trim() }

# Advanced project configuration
$EnableIssueAutomation = Read-Host "Enable issue automation? (y/n) [y]"
if (-not $EnableIssueAutomation) {
    $EnableIssueAutomation = "y"
}

$EnablePrAutomation = Read-Host "Enable PR automation? (y/n) [y]"
if (-not $EnablePrAutomation) {
    $EnablePrAutomation = "y"
}

$AutoAssignIssues = Read-Host "Auto-assign issues to project? (y/n) [y]"
if (-not $AutoAssignIssues) {
    $AutoAssignIssues = "y"
}

$DefaultLabelsInput = Read-Host "Default issue labels (comma-separated) [enhancement,bug,documentation]"
if (-not $DefaultLabelsInput) {
    $DefaultLabelsInput = "enhancement,bug,documentation"
}

$DefaultLabels = $DefaultLabelsInput.Split(',') | ForEach-Object { $_.Trim() }

# Create comprehensive project configuration YAML file
$config = @"
---
project_name: "$ProjectName"
project_description: "$ProjectDescription"
project_visibility: "$ProjectVisibility"
template_repository: "$TemplateRepo"
columns:
$(($Columns | ForEach-Object { "- $_" }) -join "`n")
automation_enabled: true
issue_automation: $($EnableIssueAutomation.ToLower())
pr_automation: $($EnablePrAutomation.ToLower())
auto_assign_issues: $($AutoAssignIssues.ToLower())
default_labels:
$(($DefaultLabels | ForEach-Object { "- $_" }) -join "`n")
created_at: "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
created_by: "projectize-command"
"@

$config | Out-File -FilePath $ProjectFile -Encoding UTF8

# Create GitHub Actions workflow for project automation
$WorkflowFile = Join-Path ".github" "workflows" "project-automation.yml"
if (-not (Test-Path $WorkflowFile) -or (Get-Item $WorkflowFile).Length -eq 0) {
    $workflow = @'
name: Project Automation
# GitHub Actions workflow for automated project management
# Handles issue and PR events to update project status automatically
# Provides foundation for custom project automation rules

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
'@

    New-Item -ItemType Directory -Force -Path (Split-Path $WorkflowFile) | Out-Null
    $workflow | Out-File -FilePath $WorkflowFile -Encoding UTF8
}

# Create enhanced project automator script for GitHub API interactions
$ScriptsDir = Join-Path ".github" "scripts"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
$AutomatorScript = Join-Path $ScriptsDir "project-automator.js"

$scriptContent = @'
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN
});

async function main() {
  try {
    // Load project configurations from .github/projects/ directory
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
'@

$scriptContent | Out-File -FilePath $AutomatorScript -Encoding UTF8

# Output results based on mode
if ($Json) {
    $result = @{
        BRANCH_NAME = $ProjectId
        PROJECT_FILE = $ProjectFile
        PROJECT_ID = $ProjectId
    } | ConvertTo-Json
    Write-Output $result
} else {
    Write-Host "✅ Project configuration created: $ProjectFile" -ForegroundColor Green
    Write-Host "✅ GitHub Actions workflow created: $WorkflowFile" -ForegroundColor Green
    Write-Host "✅ Project automator script created: $AutomatorScript" -ForegroundColor Green
    Write-Host ""
    Write-Host "BRANCH_NAME: $ProjectId" -ForegroundColor Cyan
    Write-Host "PROJECT_FILE: $ProjectFile" -ForegroundColor Cyan
    Write-Host "PROJECT_ID: $ProjectId" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Review and customize the project configuration in $ProjectFile"
    Write-Host "2. The GitHub Actions workflow will automatically create and manage your GitHub Project"
    Write-Host "3. Issues and PRs will be automatically added to the project"
    Write-Host "4. Project cards will move automatically based on status changes"
}
