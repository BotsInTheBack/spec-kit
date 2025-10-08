<#
.SYNOPSIS
    GitHub Project Board Manager

.DESCRIPTION
    This script helps manage GitHub Project Boards for existing repositories, including:
    - Creating and configuring project boards
    - Managing board templates and configurations
    - Automatic GitHub authentication if needed

    The script requires GitHub CLI (gh) to be installed.

.PARAMETER Name
    Board name (default: "Project Board")

.PARAMETER Template
    Board template to use (basic, kanban, bug-triage)

.EXAMPLE
    # Create a kanban board with default name
    .\github-project.ps1 -Template kanban

.EXAMPLE
    # Create a board with custom name and template
    .\github-project.ps1 -Name "My Project" -Template bug-triage
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('add-board', 'import-tasks')]
    [string]$Action = 'add-board',
    
    [Parameter()]
    [string]$Name = "Project Board",
    
    [Parameter()]
    [ValidateSet('basic', 'kanban', 'bug-triage')]
    [string]$Template = 'kanban',
    
    [Parameter()]
    [ValidateSet('user', 'org', 'auto')]
    [string]$Scope = 'auto',
    
    [Parameter()]
    [string]$OrgName,
    
    [Parameter()]
    [switch]$NonInteractive,
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$Help
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# Check for required commands
function Test-CommandExists {
    param([string]$Command)
    return (Get-Command $Command -ErrorAction SilentlyContinue) -ne $null
}

function Test-Requirements {
    $required = @('git', 'gh', 'jq')
    $missing = $required | Where-Object { -not (Test-CommandExists $_) }
    
    if ($missing) {
        $errorMsg = "Missing required tools: $($missing -join ', ')"
        $errorMsg += "`nPlease install the missing requirements and try again:"
        $errorMsg += "`n- GitHub CLI: https://cli.github.com/"
        $errorMsg += "`n- Git: https://git-scm.com/downloads"
        $errorMsg += "`n- jq: https://stedolan.github.io/jq/download/"
        
        Write-Error $errorMsg
    }
}

# Check GitHub authentication
function Test-GitHubAuth {
    try {
        $null = gh auth status 2>&1
        return $true
    } catch {
        Write-Warning "GitHub CLI is not authenticated. Starting authentication..."
        try {
            $null = gh auth login
            return $true
        } catch {
            Write-Error "GitHub authentication failed. Please run 'gh auth login' manually."
        }
    }
}

# Get repository information
function Get-RepositoryInfo {
    [CmdletBinding()]
    param()
    
    try {
        # Check if we're in a Git repository with GitHub remote
        if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
            Write-Warning "Not in a Git repository. Project will be created without repository linking."
            return @{
                Name = ""
                Owner = ""
                IsOrganization = $false
                FullName = ""
            }
        }
        
        # Get repository info using GitHub CLI
        $repoInfo = gh repo view --json name,owner,isInOrganization,nameWithOwner 2>$null | ConvertFrom-Json
        
        if (-not $repoInfo) {
            Write-Warning "Could not determine repository information. Project will be created without repository linking."
            return @{
                Name = ""
                Owner = ""
                IsOrganization = $false
                FullName = ""
            }
        }
        
        $isOrgRepo = $repoInfo.isInOrganization
        $owner = $repoInfo.owner.login
        
        if ($isOrgRepo) {
            Write-Info "Detected organization repository. Owner: $owner"
        } else {
            Write-Info "Detected personal repository. Owner: $owner"
        }
        
        return @{
            Name = $repoInfo.name
            Owner = $owner
            IsOrganization = $isOrgRepo
            FullName = $repoInfo.nameWithOwner
        }
    } catch {
        Write-Warning "Error getting repository information. Project will be created without repository linking: $_"
        return @{
            Name = ""
            Owner = ""
            FullName = ""
        }
    }
}

# Helper function to prompt for yes/no with default
function Confirm-YesNo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        
        [Parameter()]
        [int]$DefaultChoice = 0,  # 0 for Yes, 1 for No
        
        [Parameter()]
        [int]$Timeout = 0  # Timeout in seconds (0 for no timeout)
    )
    
    $choices = @('&Yes', '&No')
    $default = $choices[$DefaultChoice]
        $maxAttempts = 2
        $attempt = 0
        $projectCreated = $false
        $projectUrl = $null
    }
    
    process {
        # Get repository info for auto-detection
        $repoInfo = Get-RepositoryInfo
        
        # Auto-detect scope if needed
        if ($Scope -eq 'auto') {
            if ($OrgName) {
                $Scope = 'org'
                Write-Info "Using organization from command line: $OrgName"
            } elseif ($repoInfo.IsOrganization -and $repoInfo.Owner) {
                if ($NonInteractive -or (Confirm-YesNo -Prompt "Create project in organization '$($repoInfo.Owner)'?" -DefaultChoice 0)) {
                    $Scope = 'org'
                    $OrgName = $repoInfo.Owner
                    Write-Info "Using repository organization: $OrgName"
                } else {
                    $Scope = 'user'
                    Write-Info "Creating personal project instead"
                }
            } else {
                $Scope = 'user'
                Write-Info "Defaulting to personal project"
            }
        }
        
        # If scope is org but no org name is provided, prompt for it or use repo owner
        if ($Scope -eq 'org' -and -not $OrgName) {
            if ($NonInteractive) {
                Write-Error "Organization name is required for organization-scoped projects"
                return $false
            }
            
            # Suggest the repository owner if available and in an org
            $suggestedOrg = ""
            if ($repoInfo.IsOrganization -and $repoInfo.Owner) {
                $suggestedOrg = $repoInfo.Owner
            }
            
            $OrgName = Read-Host -Prompt "Enter organization name" -DefaultValue $suggestedOrg
            if ([string]::IsNullOrWhiteSpace($OrgName)) {
                Write-Error "Organization name cannot be empty"
                return $false
            }
        }
        
        # Confirm before creating the project
        if (-not $NonInteractive) {
            $scopeDisplay = "personal account"
            if ($Scope -eq 'org') {
                $scopeDisplay = "organization '$OrgName'"
            }
            
            Write-Host "`n$($PSStyle.Formatting.Warning)About to create project:$($PSStyle.Reset)"
            Write-Host "  Name:    $($PSStyle.Foreground.Blue)$Name$($PSStyle.Reset)"
            Write-Host "  Scope:   $($PSStyle.Foreground.Blue)$scopeDisplay$($PSStyle.Reset)"
            Write-Host "  Template: $($PSStyle.Foreground.Blue)$Template$($PSStyle.Reset)"
            
            if ($Scope -eq 'org') {
                Write-Host "$($PSStyle.Formatting.Warning)Note:$($PSStyle.Reset) You'll need 'write' or 'admin' permissions on the organization to create projects."
                Write-Host "      If you don't have sufficient permissions, the script will attempt to create a personal project instead.`n"
            }
            
            if (-not (Confirm-YesNo -Prompt "Proceed with project creation?" -DefaultChoice 0)) {
                Write-Info "Project creation cancelled"
                return $null
            }
        }
        
        # Try to create the project with the specified scope
        while ($attempt -lt $maxAttempts -and -not $projectCreated) {
            $attempt++
            
            try {
                $apiEndpoint = if ($Scope -eq 'org' -and $OrgName) {
                    "/orgs/$OrgName/projects"
                } else {
                    "/user/projects"
                }
                
                Write-Info "Creating project '$Name' with $Template template..."
                
                # Create the project
                $project = gh api -X POST \
                    -H "Accept: application/vnd.github.v3+json" \
                    $apiEndpoint \
                    -f name="$Name" \
                    -f body="Project board for $($repoInfo.FullName)" 2>&1 | ConvertFrom-Json
                
                if (-not $project) {
                    throw "Failed to create project - no response from GitHub API"
                }
                
                $projectUrl = $project.html_url
                $projectNumber = $project.number
                
                if (-not $projectUrl -or -not $projectNumber) {
                    throw "Failed to parse project information from GitHub API response"
                }
                
                # Link the project to the repository if we have the project number and repo info
                if ($projectNumber -and $repoInfo.FullName) {
                    Write-Info "Linking project to repository $($repoInfo.FullName)..."
                    
                    try {
                        $linkCmd = "gh project link $projectNumber --repo $($repoInfo.FullName)"
                        Invoke-Expression $linkCmd | Out-Null
                        Write-Info "✅ Successfully linked project to repository: $($repoInfo.FullName)"
                    } catch {
                        Write-Warning "Failed to link project to repository: $_"
                        Write-Warning "You can link it manually with: gh project link $projectNumber --repo $($repoInfo.FullName)"
                    }
                }
                
                $projectCreated = $true
                Write-Info "✅ Project board created successfully: $projectUrl"
                
            } catch {
                $errorMsg = $_.Exception.Message
                
                # Check for permission errors
                if ($errorMsg -match "Resource not accessible by personal access token" -or 
                    $errorMsg -match "Not Found" -or 
                    $errorMsg -match "ERROR") {
                    
                    if ($Scope -eq 'org') {
                        Write-Warning "Failed to create organization project in '$OrgName': $errorMsg"
                        Write-Warning "This might be due to insufficient permissions or the organization might not exist"
                        
                        # If we have more attempts, try user project next
                        if ($attempt -eq 1 -and $repoInfo.IsOrganization) {
                            Write-Info "Will attempt to create a personal project instead..."
                            $Scope = 'user'
                            continue
                        }
                        
                        if ($repoInfo.IsOrganization) {
                            Write-Error "Cannot create project in organization '$OrgName'. Please check your permissions and try again."
                            return $false
                        }
                        
                        if (-not $NonInteractive -and (Confirm-YesNo -Prompt "Would you like to create a personal project instead?" -DefaultChoice 0)) {
                            $Scope = 'user'
                            continue
                        }
                        
                        Write-Error "Project creation cancelled"
                        return $false
                    } else {
                        Write-Error "Failed to create personal project: $errorMsg"
                        return $false
                    }
                } else {
                    # For other errors, rethrow
                    throw
                }
            }
        }
        
        if (-not $projectCreated) {
            Write-Error "Failed to create project after $maxAttempts attempts"
            return $false
        }
        
        return $projectUrl
    }
    
    end {
        # Clean up if needed
    }
}

# Main function
function Start-ProjectWorkflow {
    [CmdletBinding()]
    param()
    
    # Show help if requested
    if ($Help) {
        Get-Help $PSCommandPath -Detailed
        return
    }
    
    # Check requirements
    Test-Requirements
    
    # Check authentication
    Test-GitHubAuth | Out-Null
    
    # Get repository info
    $repoInfo = Get-RepositoryInfo
    
    # Execute the requested action
    switch ($Action.ToLower()) {
        'add-board' {
            $boardUrl = New-GitHubBoard -Name $Name -Template $Template
            return $boardUrl
        }
        'import-tasks' {
            Write-Info "Importing tasks is not yet implemented"
        }
        default {
            Write-Error "Unknown action: $Action"
        }
    }
}

# Execute the main function
try {
    Start-ProjectWorkflow
} catch {
    Write-Error "An error occurred: $_"
    exit 1
}.EXAMPLE
    # Add a kanban board to the current repository
    .\github-project.ps1 -Template kanban -Name "Development Board"

    # Import tasks to an existing project board
    .\github-project.ps1 import-tasks

    # Use a specific repository
    .\github-project.ps1 -Owner myorg -Repo myrepo -Template bug-triage -Name "Bug Tracker"

.NOTES
    Templates:
      - basic: Simple board with To Do, In Progress, Done
      - kanban: Kanban board with Backlog, To Do, In Progress, In Review, Done
      - bug-triage: Bug tracking board with Reported, Needs Triage, In Progress, Needs Fix, Resolved

    Requirements:
      - Must be run from within a git repository or specify owner/repo
      - GitHub CLI (gh) must be installed and authenticated
      - jq is required for JSON processing
#>

[CmdletBinding(DefaultParameterSetName = 'AddBoard')]
param(
    [Parameter(Position = 0)]
    [string]$Action = 'add-board',

    [Parameter(ParameterSetName = 'AddBoard')]
    [string]$Repo,

    [Parameter(ParameterSetName = 'AddBoard')]
    [string]$Name = 'Project Board',

    [Parameter(ParameterSetName = 'AddBoard')]
    [string]$Description,

    [Parameter(ParameterSetName = 'AddBoard')]
    [ValidateSet('kanban', 'basic', 'bug-triage')]
    [string]$Template = 'kanban',

    [switch]$NonInteractive
{{ ... }}
}

# Create GitHub project board using GraphQL API
function New-GitHubProjectBoard {
    param(
        [string]$Repo,
        [string]$Name,
        [string]$Description,
        [string]$Template
    )
    
    Write-Info "Creating project board: $Name"
{{ ... }}
    
    try {
        # Get repository and owner information using GraphQL
        $repoQuery = @'
        query($owner: String!, $repo: String!) {
            repository(owner: $owner, name: $repo) {
                id
                owner {
                    ... on Organization { id }
                    ... on User { id }
                }
            }
        }
'@
        
        $repoVariables = @{
            owner = $RepoOwner
            repo = $RepoName
        } | ConvertTo-Json -Compress
        
        $repoInfo = gh api graphql -f query=$repoQuery -f variables=$repoVariables | ConvertFrom-Json
        
        if (-not $repoInfo -or -not $repoInfo.data.repository) {
            throw "Failed to get repository information. Make sure you have the correct permissions."
        }
        
        $repoId = $repoInfo.data.repository.id
        $ownerId = $repoInfo.data.repository.owner.id
        
        if (-not $repoId -or -not $ownerId) {
            throw "Failed to get repository or owner ID. Response: $($repoInfo | ConvertTo-Json -Depth 5)"
        }
        
        Write-Info "Creating project in repository: $RepoOwner/$RepoName"
        
        # Create project using GraphQL
        $createProjectQuery = @'
        mutation($input: CreateProjectV2Input!) {
            createProjectV2(input: $input) {
                projectV2 {
                    id
                    number
                    url
                }
            }
        }
'@
        
        $projectInput = @{
            ownerId = $ownerId
            title = $Name
            repositoryIds = @($repoId)
        } | ConvertTo-Json -Compress -Depth 5
        
        $projectInfo = gh api graphql -f query=$createProjectQuery -f input=$projectInput | ConvertFrom-Json
        
        if (-not $projectInfo -or -not $projectInfo.data.createProjectV2.projectV2) {
            throw "Failed to create project. Response: $($projectInfo | ConvertTo-Json -Depth 5)"
        }
        
        $projectId = $projectInfo.data.createProjectV2.projectV2.id
        $projectUrl = $projectInfo.data.createProjectV2.projectV2.url
        
        Write-Info "Project created successfully: $projectUrl"
        
        # Setup board columns based on template
        $columns = @()
        switch ($Template) {
            'kanban' { $columns = @('To Do', 'In Progress', 'In Review', 'Done') }
            'bug-triage' { $columns = @('Reported', 'Needs Triage', 'In Progress', 'Needs Fix', 'Resolved') }
            default { $columns = @('To Do', 'In Progress', 'Done') } # basic
        }
        
        # Add columns to the project
        foreach ($column in $columns) {
            $addColumnQuery = @'
            mutation($projectId: ID!, $name: String!) {
                addProjectV2Field(input: {
                    projectId: $projectId
                    dataType: TEXT
                    name: $name
                }) {
                    projectV2Field {
                        id
                        name
                    }
                }
            }
'@
            $columnVariables = @{
                projectId = $projectId
                name = $column
            } | ConvertTo-Json -Compress
            
            gh api graphql -f query=$addColumnQuery -f variables=$columnVariables | Out-Null
        }
        
        Write-Info "Project board '$Name' created with $($columns.Count) columns"
        
        return $projectId
    }
    catch {
        Write-Error "Failed to create project board: $_"
    }
}

# Import tasks from .specify/features
function Import-TasksFromFeatures {
    param(
        [string]$ProjectId
    )
    
    $featuresPath = ".specify/features"
    if (-not (Test-Path $featuresPath)) {
        Write-Warning "Features directory not found at '$featuresPath'. No tasks to import."
        return
    }
    
    Write-Info "Importing tasks from '$featuresPath'..."
    
    $featureFiles = Get-ChildItem -Path $featuresPath -Filter "*.md" -Recurse
    
    foreach ($file in $featureFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        $title = $file.BaseName -replace '[^\w\s-]', '' -replace '\s+', ' ' -trim
        
        # Create an issue for each feature file
        $issueTitle = "[Feature] $title"
        $issueBody = "### Description\n$content\n\n*Imported from $($file.Name)*"
        
        try {
            $issue = gh issue create --title $issueTitle --body $issueBody
            Write-Info "Created issue: $issue"
            
            # Add issue to project board (if project ID is provided)
            if ($ProjectId) {
                $issueNumber = $issue -replace '^.*/(\d+)$', '$1'
                
                $addToProjectQuery = @'
                mutation($projectId: ID!, $contentId: ID!) {
                    addProjectV2ItemById(input: {
                        projectId: $projectId
                        contentId: $contentId
                    }) {
                        item {
                            id
                        }
                    }
                }
'@
                $variables = @{
                    projectId = $ProjectId
                    contentId = "I_$issueNumber"
                } | ConvertTo-Json -Compress
                
                gh api graphql -f query=$addToProjectQuery -f variables=$variables | Out-Null
                Write-Info "Added issue #$issueNumber to project board"
            }
        }
        catch {
            Write-Warning "Failed to create issue from '$($file.Name)': $_"
        }
    }
}

# Main execution flow
function Start-ProjectWorkflow {
    [CmdletBinding()]
    param()
    
    # Default values
    $Action = 'add-board'
    $Name = 'Project Board'
    $Template = 'kanban'
    $Scope = 'auto'
    $OrgName = $null
    $NonInteractive = $false
    $DryRun = $false
    $Help = $false
    
    # Parse command line arguments
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = $args[$i]
        
        switch -Regex ($arg) {
            '^-n$|^--name$' {
                $Name = $args[++$i]
                break
            }
            '^-t$|^--template$' {
                $Template = $args[++$i]
                break
            }
            '^-s$|^--scope$' {
                $Scope = $args[++$i].ToLower()
                if ($Scope -notin @('user', 'org', 'auto')) {
                    Write-Error "Invalid scope: $Scope. Must be 'user', 'org', or 'auto'"
                    Get-Help $PSCommandPath -Detailed
                    exit 1
                }
                break
            }
            '^-o$|^--org$' {
                $OrgName = $args[++$i]
                $Scope = 'org'  # If org is specified, force scope to org
                break
            }
            '^--non-interactive$' {
                $NonInteractive = $true
                break
            }
            '^--dry-run$' {
                $DryRun = $true
                break
            }
            '^-y$|^--yes$' {
                $NonInteractive = $true
                break
            }
            '^-h$|^--help$|^/\?$' {
                $Help = $true
                break
            }
            '^add-board$|^import-tasks$' {
                $Action = $_
                break
            }
            default {
                Write-Warning "Unknown argument: $_"
                Get-Help $PSCommandPath -Detailed
                exit 1
            }
        }
    }
    
    # Show help if requested
    if ($Help) {
        Get-Help $PSCommandPath -Detailed
        return
    }
    
    # Check requirements
    Test-Requirements
    
    # Check authentication
    if (-not (Test-GitHubAuth)) {
        exit 1
    }
    
    # Execute the requested action
    switch ($Action.ToLower()) {
        'add-board' {
            $params = @{
                Name = $Name
                Template = $Template
                Scope = $Scope
                NonInteractive = $NonInteractive
            }
            
            if ($OrgName) {
                $params['OrgName'] = $OrgName
            }
            
            if ($DryRun) {
                $params['WhatIf'] = $true
            }
            
            $projectUrl = New-GitHubBoard @params
            if ($projectUrl) {
                return $projectUrl
            } else {
                Write-Error "Failed to create project board"
                exit 1
            }
        }
        
        'import-tasks' {
            Write-Info "Importing tasks is not yet implemented"
            # Import-TasksFromFeatures
        }
        
        default {
            Write-Error "Unknown action: $Action"
            Get-Help $PSCommandPath -Detailed
            exit 1
        }
    }

}

# Start the workflow
try {
    Start-ProjectWorkflow
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
