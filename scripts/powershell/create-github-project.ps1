<#
.SYNOPSIS
    GitHub Project Creation Tool (Internal Use)
    =========================================

    IMPORTANT: This script is designed to be used internally by the '/projectize' command
    in the GitHub Spec Kit. Please use the '/projectize' command from your IDE's chat interface
    for the best experience.

    For end users, the recommended way to use this functionality is via the '/projectize' command:

      /projectize --name my-project --description "Project description"

.DESCRIPTION
    This script automates the creation of GitHub projects with best practices,
    including repository setup, project boards, and task tracking.
    
    It's the PowerShell version of the GitHub Project creation script for Windows compatibility.
    Part of the GitHub Spec Kit's /projectize slash command functionality.

    Features:
    - 🚀 One-command project initialization
    - 🔒 Automatic branch protection
    - 📋 Standard project files (README, LICENSE, .gitignore)
    - 🏗️ Project board setup
    - 🔄 CI/CD workflow configuration

    Internal Documentation (for development purposes only):
    ----------------------------------------------------
    This script automates the creation of GitHub projects with best practices,
    including repository setup, project boards, and task tracking.

.PARAMETER Name
    Project name (default: current directory name)

.PARAMETER Description
    Project description

.PARAMETER Private
    Make repository private (default)

.PARAMETER Public
    Make repository public

.PARAMETER Org
    Organization name (default: current user)

.PARAMETER RepoTemplate
    GitHub repo to use as template (owner/repo)

.PARAMETER ProjectTemplate
    Project type (kanban/table, default: kanban)

.PARAMETER FeatureMarkdown
    Path to feature markdown file containing tasks (default: .specify/features/current/feature.md)

.PARAMETER License
    License type (MIT, Apache-2.0, etc.)

.PARAMETER Branch
    Default branch name (default: main)

.PARAMETER Team
    Grant access to a team (can be specified multiple times)

.PARAMETER Force
    Override auto-detection

.PARAMETER NoAutoDetect
    Disable auto-detection

.PARAMETER Json
    Output in JSON format

.PARAMETER Help
    Show this help message

Project Templates:
  kanban                   Kanban board with To Do, In Progress, Done columns
  table                    Table view with status, priority, and assignee fields

Feature Markdown:
  The -FeatureMarkdown parameter allows you to specify a markdown file containing
  tasks in checklist format. These tasks will be automatically added to your
  project board. Example:
    - [ ] Task 1
    - [ ] Task 2
    - [x] Completed task

.EXAMPLE
    # Create a new project with Kanban board
    .\create-github-project.ps1 --name my-project --project-template kanban

.EXAMPLE
    # Create a public project in an organization with a team
    .\create-github-project.ps1 --name our-app --org myorg --public --team @myorg/developers

.EXAMPLE
    # Create a project from a repository template
    .\create-github-project.ps1 --name api-service --repo-template org/template-repo

.EXAMPLE
    # Output in JSON format for programmatic use
    .\create-github-project.ps1 --name my-project --json

.EXAMPLE
    # Create a project with tasks from a feature markdown file
    .\create-github-project.ps1 --name my-feature --feature-md .specify/features/current/feature.md

.NOTES
    This is an internal tool. For end users, please use the '/projectize' command
    from your IDE's chat interface for the best experience.
#>

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Load common functions and variables
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$COMMON_SCRIPT = Join-Path $SCRIPT_DIR 'common.ps1'
if (Test-Path $COMMON_SCRIPT) {
    . $COMMON_SCRIPT
}

[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [Alias('name')]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [Alias('description')]
    [string]$Description,
    
    [Parameter(Mandatory=$false)]
    [Alias('private')]
    [switch]$Private = $true,
    
    [Parameter(Mandatory=$false)]
    [Alias('public')]
    [switch]$Public = $false,
    
    [Parameter(Mandatory=$false)]
    [Alias('org')]
    [string]$Org,
    
    [Parameter(Mandatory=$false)]
    [Alias('repo-template')]
    [string]$RepoTemplate,
    
    [Parameter(Mandatory=$false)]
    [Alias('project-template')]
    [ValidateSet('kanban', 'table')]
    [string]$ProjectTemplate = 'kanban',
    
    [Parameter(Mandatory=$false)]
    [Alias('license')]
    [string]$License = 'MIT',
    
    [Parameter(Mandatory=$false)]
    [Alias('branch')]
    [string]$Branch = 'main',
    
    [Parameter(Mandatory=$false)]
    [Alias('team')]
    [string[]]$Team = @(),
    
    [Parameter(Mandatory=$false)]
    [Alias('feature-md')]
    [string]$FeatureMarkdown = '.specify/features/current/feature.md',
    
    [Parameter(Mandatory=$false)]
    [Alias('force')]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [Alias('no-auto-detect')]
    [switch]$NoAutoDetect,
    
    [Parameter(Mandatory=$false)]
    [Alias('json')]
    [switch]$Json,
    
    [Parameter(Mandatory=$false)]
    [Alias('h', 'help')]
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

# GitHub API configuration
$GITHUB_API = "https://api.github.com"

# Project templates
$PROJECT_TEMPLATES = @{
    "kanban" = "Kanban board with To Do, In Progress, Done columns"
    "table" = "Table view with status, priority, and assignee fields"
}

# Common repository templates
$REPO_TEMPLATES = @{
    "node" = "Node.js with GitHub Actions"
    "python" = "Python with pytest and GitHub Actions"
    "react" = "React application with Vite"
    "nextjs" = "Next.js application"
    "typescript" = "TypeScript project"
    "go" = "Go module"
    "rust" = "Rust project with Cargo"
    "terraform" = "Terraform module"
    "docker" = "Docker project"
}

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

# Function to detect git repository and get repository info
function Get-GitRepositoryInfo {
    $repoRoot = $null
    $remoteUrl = $null
    
    try {
        $repoRoot = git rev-parse --show-toplevel 2>$null
        $remoteUrl = git remote get-url origin 2>$null
    } catch {
        $repoRoot = Find-RepoRoot (Get-Location).Path
    }
    
    $repoInfo = @{
        Root = $repoRoot
        RemoteUrl = $remoteUrl
        IsGitRepo = -not [string]::IsNullOrEmpty($repoRoot)
    }
    
    # Parse owner and repo from remote URL if available
    if ($remoteUrl -match 'github.com[:/]([^/]+)/([^/]+?)(\.git)?$') {
        $repoInfo.Owner = $matches[1]
        $repoInfo.Name = $matches[2] -replace '\.git$', ''
    }
    
    return $repoInfo
}

# Function to list available templates
function Show-AvailableTemplates {
    Write-Host "`nAvailable repository templates:" -ForegroundColor Cyan
    Write-Host ""
    $REPO_TEMPLATES.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host ("  {0,-15} {1}" -f $_.Name, $_.Value)
    }
    
    Write-Host "`nAvailable project templates:" -ForegroundColor Cyan
    Write-Host ""
    $PROJECT_TEMPLATES.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host ("  {0,-15} {1}" -f $_.Name, $_.Value)
    }
    Write-Host ""
}

# Function to create repository from template
function New-RepositoryFromTemplate {
    param(
        [string]$Template,
        [string]$Name,
        [string]$Description,
        [bool]$Private,
        [string]$Org
    )
    
    $templateOwner, $templateRepo = $Template -split '/'
    if ($templateOwner -notmatch '^[a-zA-Z0-9_-]+$' -or $templateRepo -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Error "Invalid template format. Expected format: owner/repo"
        return $false
    }
    
    $privateFlag = if ($Private) { "--private" } else { "--public" }
    $orgFlag = if ($Org) { "--org $Org" } else { "" }
    $descFlag = if ($Description) { "--description `"$Description`"" } else { "" }
    
    try {
        $command = "gh repo create $Name --template $Template $privateFlag $orgFlag $descFlag --clone"
        Write-Verbose "Executing: $command"
        Invoke-Expression $command
        
        # Change to the new repository directory
        Set-Location $Name
        return $true
    } catch {
        Write-Error "Failed to create repository from template: $_"
        return $false
    }
}

# Function to initialize a new repository
function Initialize-Repository {
    param(
        [string]$Name,
        [string]$Branch,
        [string]$License,
        [string]$Description,
        [bool]$Private
    )
    
    try {
        # Initialize git repository
        git init
        
        # Create initial commit with README
        $readmeContent = @"
# $Name

$Description

## Getting Started

### Prerequisites

- [Git](https://git-scm.com/)
- [GitHub CLI](https://cli.github.com/)

### Installation

```bash
git clone https://github.com/$($Org ?? 'username')/$Name.git
cd $Name
```

## License

This project is licensed under the $License License - see the [LICENSE](LICENSE) file for details.
"@
        
        $readmeContent | Out-File -FilePath "README.md" -Encoding utf8
        
        # Create .gitignore
        @"
# Dependencies
node_modules/
__pycache__/
*.py[cod]
*$py.class

# Build outputs
dist/
build/
*.egg-info/

# Environment files
.env
.venv
env/
venv/

# IDE specific files
.vscode/
.idea/
*.swp
*.swo

# Logs
logs/
*.log

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
"@ | Out-File -FilePath ".gitignore" -Encoding utf8
        
        # Create LICENSE if specified
        if ($License -eq 'MIT') {
            @"
MIT License

Copyright (c) $(Get-Date -Format 'yyyy') $(if ($Org) { $Org } else { 'Your Name' })

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@ | Out-File -FilePath "LICENSE" -Encoding utf8
        }
        
        # Initial commit
        git add .
        git commit -m "Initial commit"
        
        # Create and switch to the specified branch
        git checkout -b $Branch
        
        return $true
    } catch {
        Write-Error "Failed to initialize repository: $_"
        return $false
    }
}

# Function to parse feature markdown and extract tasks
function Get-TasksFromMarkdown {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Warning "Feature markdown file not found: $Path"
        return @()
    }
    
    $content = Get-Content $Path -Raw
    $tasks = [System.Collections.Generic.List[PSCustomObject]]::new()
    $currentSection = ""
    $taskId = 1
    
    # Process each line in the markdown file
    $content -split "`n" | ForEach-Object {
        $line = $_.Trim()
        
        # Check for section headers
        if ($line -match '^##?\s+(.+)$') {
            $currentSection = $matches[1].Trim()
        }
        # Check for task items
        elseif ($line -match '^- \[ \]\s+(.+)$') {
            $tasks.Add([PSCustomObject]@{
                Id = $taskId++
                Title = $matches[1].Trim()
                Section = $currentSection
                Status = 'To Do'
            })
        }
    }
    
    return $tasks
}

# Function to create GitHub project
function New-GitHubProject {
    param(
        [string]$Name,
        [string]$Template,
        [string]$Description,
        [string]$Branch,
        [array]$Tasks,
        [bool]$Json
    )
    
    try {
        # Create GitHub project
        $projectArgs = @(
            'project', 'create', $Name,
            '--format', 'json',
            '--owner', (if ($Org) { $Org } else { $env:USERNAME }),
            '--title', $Name,
            '--description', $Description,
            '--template', $Template
        )
        
        $project = gh $projectArgs | ConvertFrom-Json
        
        # Add tasks to the project
        if ($Tasks.Count -gt 0) {
            $Tasks | ForEach-Object {
                $taskArgs = @(
                    'project', 'item-add', $project.id,
                    '--title', $_.Title,
                    '--body', "Section: $($_.Section)",
                    '--format', 'json'
                )
                gh $taskArgs | Out-Null
            }
        }
        
        # Set default branch protection
        $protectionArgs = @(
            'api', "repos/$(if ($Org) { "$Org/" } else { "" })$Name/branches/$Branch/protection"
            '-X', 'PUT',
            '-H', 'Accept: application/vnd.github.v3+json',
            '-f', 'enforce_admins=null',
            '-f', 'required_pull_request_reviews.required_approving_review_count=1',
            '-f', 'required_pull_request_reviews.dismiss_stale_reviews=true',
            '-f', 'required_status_checks.strict=true',
            '-f', 'required_status_checks.contexts=[]',
            '-f', 'restrictions=null'
        )
        
        gh $protectionArgs | Out-Null
        
        # Output the result
        if ($Json) {
            return $project | ConvertTo-Json -Depth 10
        } else {
            Write-Host "✅ Successfully created project: $($project.html_url)" -ForegroundColor Green
            return $project
        }
    } catch {
        Write-Error "Failed to create GitHub project: $_"
        return $null
    }
}

# Function to set up team access
function Set-TeamAccess {
    param([array]$Teams)
    
    foreach ($team in $Teams) {
        if ($team -match '^@([^/]+)/([^/]+)$') {
            $orgName = $matches[1]
            $teamSlug = $matches[2]
            
            try {
                gh api -X PUT "orgs/$orgName/teams/$teamSlug/repos/$Org/$Name" \
                    -f "permission=push" | Out-Null
                Write-Host "✅ Granted push access to team: $team" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to grant access to team $team: $_"
            }
        } else {
            Write-Warning "Invalid team format: $team. Expected format: @org/team"
        }
    }
}
        $Directory = Split-Path $Directory -Parent
    }
    return $null
}

# Main script execution
function Start-ProjectCreation {
    # Show help if no arguments provided
    if ($args.Count -eq 0 -and -not $Name) {
        Show-AvailableTemplates
        Write-Host "Use -Help for detailed usage information" -ForegroundColor Yellow
        exit 0
    }

    # Get repository information
    $repoInfo = Get-GitRepositoryInfo
    $currentDir = Get-Location
    
    # If no name provided and we're in a git repo, use the repo name
    if (-not $Name -and $repoInfo.IsGitRepo) {
        $Name = $repoInfo.Name
    }
    
    # If still no name, use current directory name
    if (-not $Name) {
        $Name = (Get-Item -Path ".").Name
    }
    
    # If we have a repository template, create from template
    if ($RepoTemplate) {
        Write-Host "🚀 Creating repository from template: $RepoTemplate" -ForegroundColor Cyan
        $success = New-RepositoryFromTemplate -Template $RepoTemplate -Name $Name -Description $Description -Private $Private -Org $Org
        
        if (-not $success) {
            Write-Error "Failed to create repository from template"
            exit 1
        }
    }
    # If we're not in a git repository, initialize one
    elseif (-not $repoInfo.IsGitRepo) {
        Write-Host "🔄 Initializing new git repository" -ForegroundColor Cyan
        $success = Initialize-Repository -Name $Name -Branch $Branch -License $License -Description $Description -Private $Private
        
        if (-not $success) {
            Write-Error "Failed to initialize repository"
            exit 1
        }
    }
    
    # If we have a project template, create a GitHub project
    if ($ProjectTemplate) {
        # Parse tasks from feature markdown if provided
        $tasks = @()
        if ($FeatureMarkdown) {
            $tasks = Get-TasksFromMarkdown -Path $FeatureMarkdown
            Write-Host "📋 Found $($tasks.Count) tasks in feature markdown" -ForegroundColor Green
        }
        
        # Create GitHub project
        Write-Host "🏗️  Creating GitHub project with $ProjectTemplate template" -ForegroundColor Cyan
        $project = New-GitHubProject -Name $Name -Template $ProjectTemplate -Description $Description -Branch $Branch -Tasks $tasks -Json:$Json
        
        if (-not $project) {
            Write-Error "Failed to create GitHub project"
            exit 1
        }
        
        # Output project information
        if ($Json) {
            $project | ConvertTo-Json -Depth 10
        } else {
            Write-Host "✅ Successfully created project: $($project.html_url)" -ForegroundColor Green
        }
    }
    
    # Set up team access if specified
    if ($Team.Count -gt 0) {
        Write-Host "👥 Setting up team access" -ForegroundColor Cyan
        Set-TeamAccess -Teams $Team
    }
    
    Write-Host "✨ Project setup complete!" -ForegroundColor Green
}

# Execute the main function
try {
    Start-ProjectCreation @PSBoundParameters
} catch {
    Write-Error "An error occurred: $_"
    if ($_.ScriptStackTrace) {
        Write-Debug "Stack trace: $($_.ScriptStackTrace)"
    }
    exit 1
}

# Display success message
Write-Host "✅ GitHub Project Creation Script is ready to use!" -ForegroundColor Green
Write-Host "   Run with -Help to see available options and examples" -ForegroundColor Cyan
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
