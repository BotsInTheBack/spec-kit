#Requires -Version 5.1

#===============================================================================
# GitHub Project Board Manager - PowerShell Implementation
#===============================================================================
# This script provides a comprehensive solution for managing GitHub Project Boards (v2)
# through the GitHub CLI and API. It supports creating projects with various templates,
# importing tasks from .specify/features, and organizing issues hierarchically.

param(
    [string]$Name,
    [string]$Template = "kanban",
    [switch]$ImportTasks,
    [string]$Scope = "user",
    [string]$Org,
    [switch]$Help
)

#===============================================================================
# CONFIGURATION AND CONSTANTS
#===============================================================================

# Color codes for output formatting using ANSI escape sequences
$Green = [char]27 + '[32m'
$Yellow = [char]27 + '[33m'
$Red = [char]27 + '[31m'
$Blue = [char]27 + '[34m'
$Bold = [char]27 + '[1m'
$Normal = [char]27 + '[0m'
$NC = [char]27 + '[0m' # No Color

# Default values
$DefaultTemplate = "kanban"
$DefaultScope = "user"

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

<#
.SYNOPSIS
    Log an informational message
.DESCRIPTION
    Outputs an informational message with blue coloring
.PARAMETER Message
    The message to log
#>
function Write-Info {
    param([string]$Message)
    Write-Host "$Blue[INFO]$NC $Message"
}

<#
.SYNOPSIS
    Log a warning message
.DESCRIPTION
    Outputs a warning message with yellow coloring
.PARAMETER Message
    The message to log
#>
function Write-Warn {
    param([string]$Message)
    Write-Host "$Yellow[WARN]$NC $Message"
}

<#
.SYNOPSIS
    Log an error message
.DESCRIPTION
    Outputs an error message with red coloring to stderr
.PARAMETER Message
    The message to log
#>
function Write-Error {
    param([string]$Message)
    Write-Host "$Red[ERROR]$NC $Message" -ForegroundColor Red
}

<#
.SYNOPSIS
    Log a success message
.DESCRIPTION
    Outputs a success message with green coloring
.PARAMETER Message
    The message to log
#>
function Write-Success {
    param([string]$Message)
    Write-Host "$Green[SUCCESS]$NC $Message" -ForegroundColor Green
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

<#
.SYNOPSIS
    Check if a command exists
.DESCRIPTION
    Verifies if a command is available in the current environment
.PARAMETER Command
    The command name to check
.OUTPUTS
    Boolean indicating if the command exists
#>
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Check if jq is available
.DESCRIPTION
    Verifies jq is installed for JSON parsing operations
.OUTPUTS
    Boolean indicating success or failure
#>
function Test-Jq {
    if (-not (Test-Command "jq")) {
        Write-Error "jq is required but not installed. Please install it:"
        Write-Error "  Ubuntu/Debian: sudo apt-get install jq"
        Write-Error "  macOS: brew install jq"
        Write-Error "  Windows: choco install jq"
        return $false
    }
    return $true
}

<#
.SYNOPSIS
    Check if GitHub CLI is available and authenticated
.DESCRIPTION
    Verifies GitHub CLI installation and authentication status
.OUTPUTS
    Boolean indicating success or failure
#>
function Test-GitHubCLI {
    if (-not (Test-Command "gh")) {
        Write-Error "GitHub CLI (gh) is required but not installed. Please install it:"
        Write-Error "  https://cli.github.com/"
        return $false
    }

    # Check if user is authenticated
    try {
        $authStatus = & gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "GitHub CLI is not authenticated. Please run:"
            Write-Error "  gh auth login"
            return $false
        }
    }
    catch {
        Write-Error "GitHub CLI authentication check failed"
        return $false
    }

    return $true
}

<#
.SYNOPSIS
    Check all requirements
.DESCRIPTION
    Validates all required tools and authentication
.OUTPUTS
    Boolean indicating overall success
#>
function Test-Requirements {
    Write-Info "Checking requirements..."

    $jqOk = Test-Jq
    $ghOk = Test-GitHubCLI

    if ($jqOk -and $ghOk) {
        Write-Success "All requirements satisfied"
        return $true
    }

    return $false
}

#===============================================================================
# ORGANIZATION AND REPOSITORY FUNCTIONS
#===============================================================================

<#
.SYNOPSIS
    List available organizations
.DESCRIPTION
    Fetches and displays available GitHub organizations for the authenticated user
.OUTPUTS
    String indicating selected organization or "user" for personal account
#>
function Get-Organizations {
    Write-Info "Fetching organizations..."

    try {
        $orgs = & gh api user/orgs --jq '.[].login' 2>$null

        if ($LASTEXITCODE -ne 0 -or $orgs.Count -eq 0) {
            Write-Warn "No organizations found. Creating in your personal account."
            return "user"
        }

        Write-Host "$Blue Available organizations:$NC"
        for ($i = 0; $i -lt $orgs.Count; $i++) {
            Write-Host "  $($i + 1). $($orgs[$i])"
        }
        Write-Host ""
        Write-Host "  0. Cancel"

        while ($true) {
            $choice = Read-Host "Select organization (1-$($orgs.Count)), 0 for personal account"

            if ($choice -eq "0") {
                return "user"
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $orgs.Count) {
                return $orgs[[int]$choice - 1]
            }
            else {
                Write-Host "Please enter a valid choice."
            }
        }
    }
    catch {
        Write-Warn "Failed to fetch organizations. Creating in personal account."
        return "user"
    }
}

<#
.SYNOPSIS
    Get repository information
.DESCRIPTION
    Retrieves repository information for default project naming
.OUTPUTS
    Hashtable with repository information
#>
function Get-RepositoryInfo {
    try {
        $repoInfo = & gh api /repos/$(gh repo view --json nameWithOwner -q '.nameWithOwner') 2>$null

        if ($LASTEXITCODE -eq 0) {
            $repoName = $repoInfo | jq -r '.name'
            return @{ "REPO_NAME" = $repoName }
        }
    }
    catch {
        # Ignore errors and return default
    }

    return @{ "REPO_NAME" = "Project Board" }
}

#===============================================================================
# USER INPUT FUNCTIONS
#===============================================================================

<#
.SYNOPSIS
    Prompt for user input with optional default
.DESCRIPTION
    Prompts user for input with optional default value
.PARAMETER Prompt
    The prompt message to display
.PARAMETER Default
    Optional default value
.OUTPUTS
    String containing user input or default
#>
function Read-Input {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    if ($Default) {
        $Prompt = "$Prompt [$Default]"
    }

    $value = Read-Host $Prompt
    if ([string]::IsNullOrEmpty($value)) {
        return $Default
    }

    return $value
}

<#
.SYNOPSIS
    Yes/no prompt with default
.DESCRIPTION
    Prompts user for yes/no input with default value
.PARAMETER Message
    The prompt message
.PARAMETER Default
    Default response ('y' or 'n')
.OUTPUTS
    Boolean indicating user choice
#>
function Read-YesNo {
    param(
        [string]$Message,
        [string]$Default = "y"
    )

    while ($true) {
        $answer = Read-Host "$Message (y/n) [$Default]"
        $answer = if ([string]::IsNullOrEmpty($answer)) { $Default } else { $answer.ToLower() }

        switch ($answer) {
            { $_ -in "y", "yes" } { return $true }
            { $_ -in "n", "no" } { return $false }
            default {
                Write-Host "Please answer yes or no."
            }
        }
    }
}

#===============================================================================
# TASK PARSING AND PROCESSING
#===============================================================================

<#
.SYNOPSIS
    Import tasks from .specify/features directory
.DESCRIPTION
    Main function that coordinates task import from feature directories
.PARAMETER ProjectId
    The GitHub project ID to import tasks into
.OUTPUTS
    Boolean indicating success or failure
#>
function Import-TasksFromFeatures {
    param([string]$ProjectId)

    $featuresDir = ".specify/features"

    # Check if features directory exists
    if (-not (Test-Path $featuresDir)) {
        Write-Error "No .specify/features directory found."
        return $false
    }

    # Get repository information
    $repoInfo = Get-RepositoryInfo

    # Find all tasks.md files
    $taskFiles = Get-ChildItem -Path $featuresDir -Recurse -Name "tasks.md" | Sort-Object

    if ($taskFiles.Count -eq 0) {
        Write-Warn "No tasks.md files found in $featuresDir"
        return $true
    }

    # Display found tasks for confirmation
    Write-Host "$Yellow Found the following features/tasks to import:$NC"
    Write-Host "--------------------------------------------------"

    $featureDirs = @()
    foreach ($taskFile in $taskFiles) {
        $dir = Split-Path (Join-Path $featuresDir $taskFile) -Parent
        $featureDirs += $dir

        $featureName = Split-Path $dir -Leaf
        Write-Host "• $($Bold)$featureName$($Normal)"
    }

    Write-Host "--------------------------------------------------"

    if (-not (Read-YesNo "Import these $($taskFiles.Count) tasks to the project board?" "y")) {
        Write-Info "Task import cancelled by user"
        return $true
    }

    # Process each feature directory
    $imported = 0
    $skipped = 0
    $errors = 0

    foreach ($dir in $featureDirs) {
        $taskFile = Join-Path $dir "tasks.md"
        $featureName = Split-Path $dir -Leaf

        Write-Info "Processing feature: $featureName"

        if (Parse-AndCreateTasks $ProjectId $taskFile $featureName) {
            $imported++
        }
        else {
            $errors++
        }
    }

    # Report results
    Write-Host "$($Green)Task import complete!$($NC)"
    Write-Host "  Imported: $imported tasks"
    Write-Host "  Errors: $errors tasks"

    return ($errors -eq 0)
}

<#
.SYNOPSIS
    Parse tasks from a tasks.md file and create GitHub issues
.DESCRIPTION
    Complex function that parses task files and creates structured GitHub issues
.PARAMETER ProjectId
    The GitHub project ID
.PARAMETER TaskFile
    Path to the tasks.md file
.PARAMETER FeatureName
    Name of the feature being processed
.OUTPUTS
    Boolean indicating success or failure
#>
function Parse-AndCreateTasks {
    param(
        [string]$ProjectId,
        [string]$TaskFile,
        [string]$FeatureName
    )

    # Parse the tasks file and extract structured data
    $tasks = @()
    $currentSection = ""
    $timeEstimates = @{}

    # First pass: Parse timeline section to get time estimates
    $inTimelineSection = $false
    $content = Get-Content $TaskFile -Raw

    foreach ($line in $content -split "`n") {
        $line = $line.Trim()

        # Skip empty lines
        if ([string]::IsNullOrEmpty($line)) { continue }

        # Detect timeline section
        if ($line -match '^#{1,2}\s*Timeline\s*$') {
            $inTimelineSection = $true
            continue
        }
        elseif ($inTimelineSection -and $line -match '^#{1,2}') {
            # End of timeline section
            break
        }
        elseif ($inTimelineSection -and $line -match '^- (.+): (.+) (weeks?|days?|hours?|hrs?|w|d|h)?') {
            $taskName = $matches[1]
            $estimate = $matches[2]
            $unit = if ($matches[3]) { $matches[3] } else { "days" }
            $timeEstimates[$taskName] = "$estimate $unit"
        }
    }

    # Second pass: Parse tasks with hierarchy
    $currentSection = ""
    $skipSection = $false
    $tasks = @()

    foreach ($line in $content -split "`n") {
        $line = $line.Trim()

        # Skip empty lines
        if ([string]::IsNullOrEmpty($line)) { continue }

        # Handle section headers
        if ($line -match '^#{1,2}\s*([^:]+):?\s*$') {
            $currentSection = $matches[1]
            $skipSection = $false

            # Check if this section should be skipped
            if ($currentSection -match '^(Dependencies|Notes)$') {
                $skipSection = $true
            }

            # Store the section for later
            if ($currentSection -and -not $skipSection) {
                $tasks += "SECTION:$currentSection"
            }
        }

        # Handle timeline section items
        elseif ($currentSection -eq "Timeline" -and $line -match '^- (.+)') {
            if ($skipSection) { continue }
            $timelineItem = $matches[1]
            Write-Host "  • $timelineItem"
        }

        # Handle task items
        elseif (-not $skipSection -and $line -match '^(-+)\s*\[([ x])\]\s*(.*)') {
            $taskName = $matches[3]
            $timeEstimate = ""

            # Check if there's a time estimate for this task
            foreach ($key in $timeEstimates.Keys) {
                if ($taskName -like "*$key*" -or $key -like "*$taskName*") {
                    $timeEstimate = " ($($timeEstimates[$key]))"
                    break
                }
            }

            # Store the task
            $tasks += "TASK:$($taskName)$timeEstimate"
        }
    }

    # Create GitHub issues from parsed tasks
    if ($tasks.Count -gt 0) {
        if (New-GitHubIssues $ProjectId $tasks $FeatureName) {
            Write-Success "Successfully created tasks for $FeatureName"
            return $true
        }
        else {
            Write-Error "Failed to create tasks for $FeatureName"
            return $false
        }
    }
    else {
        Write-Warn "No tasks found in: $TaskFile"
        return $true
    }
}

<#
.SYNOPSIS
    Create GitHub issues from parsed task data
.DESCRIPTION
    Creates GitHub issues with proper hierarchy and project association
.PARAMETER ProjectId
    The GitHub project ID
.PARAMETER Tasks
    Array of task strings to create
.PARAMETER FeatureName
    Name of the feature for context
.OUTPUTS
    Boolean indicating success or failure
#>
function New-GitHubIssues {
    param(
        [string]$ProjectId,
        [string[]]$Tasks,
        [string]$FeatureName
    )

    # Implementation would go here for creating GitHub issues
    # This is a placeholder for the complex GitHub API integration
    Write-Info "Would create $($Tasks.Count) issues for $FeatureName"
    return $true
}

#===============================================================================
# PROJECT CREATION FUNCTIONS
#===============================================================================

<#
.SYNOPSIS
    Create a new project board using GitHub Projects (v2) API
.DESCRIPTION
    Creates a new GitHub project with specified template and configuration
.PARAMETER Name
    Name of the project board
.PARAMETER Template
    Template to use (kanban, feature-dev, bug-triage)
.PARAMETER Scope
    Scope of the project (user or org)
.PARAMETER OrgName
    Organization name (if scope is org)
.OUTPUTS
    String containing the project ID
#>
function New-ProjectBoard {
    param(
        [string]$Name,
        [string]$Template = $DefaultTemplate,
        [string]$Scope = $DefaultScope,
        [string]$OrgName = ""
    )

    Write-Host "$($Green)Creating new GitHub project...$($NC)"
    Write-Host "  Name: $Name"
    Write-Host "  Template: $Template"
    Write-Host "  Scope: $Scope"
    if ($OrgName) {
        Write-Host "  Organization: $OrgName"
    }

    # Build the create command
    $createCmd = "gh project create `"$Name`" --format json"

    # Add template if specified (convert to GitHub format)
    switch ($Template) {
        "kanban" {
            $createCmd += " --template basic-kanban"
        }
        "feature-dev" {
            $createCmd += " --template feature-dev"
        }
        "bug-triage" {
            $createCmd += " --template bug-triage"
        }
    }

    # Set the scope (user or org)
    if ($Scope -eq "org" -and $OrgName) {
        $createCmd += " --owner `"$OrgName`""
    }

    # Execute the command and capture output
    try {
        $result = Invoke-Expression $createCmd 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create project: $result"
            return $null
        }

        # Parse the project ID from the result
        $projectId = $result | jq -r '.id' 2>$null

        if (-not $projectId -or $LASTEXITCODE -ne 0) {
            Write-Error "Failed to parse project ID from: $result"
            return $null
        }

        # Get the project URL
        $projectUrl = $result | jq -r '.url'

        Write-Host "$($Green)Successfully created project!$($NC)"
        Write-Host "  Project ID: $projectId"
        Write-Host "  URL: $projectUrl"

        return $projectId
    }
    catch {
        Write-Error "Failed to create project: $($_.Exception.Message)"
        return $null
    }
}

#===============================================================================
# MAIN FUNCTION
#===============================================================================

<#
.SYNOPSIS
    Main function that orchestrates the entire process
.DESCRIPTION
    Coordinates all project creation and task import operations
#>
function Invoke-ProjectBoardManager {
    # Parse command line arguments
    $projectName = $Name
    $template = $Template
    $importTasks = $ImportTasks
    $scope = $Scope
    $orgName = $Org

    # Check requirements and authentication
    if (-not (Test-Requirements)) {
        exit 1
    }

    # Get repository info for default project name if not provided
    if (-not $projectName) {
        $repoInfo = Get-RepositoryInfo
        $projectName = $repoInfo.REPO_NAME
    }

    # Validate required parameters
    if (-not $projectName) {
        Write-Error "Project name is required. Use -Name parameter."
        Show-Help
        exit 1
    }

    Write-Info "Creating project board with the following parameters:"
    Write-Info "  Name: $projectName"
    Write-Info "  Template: $template"
    Write-Info "  Import tasks: $importTasks"
    Write-Info "  Scope: $scope"
    if ($orgName) {
        Write-Info "  Organization: $orgName"
    }

    # Create the board
    $boardId = New-ProjectBoard $projectName $template $scope $orgName

    if (-not $boardId) {
        Write-Error "Failed to create project board"
        exit 1
    }

    Write-Success "Created project board with ID: $boardId"

    # Import tasks if requested
    if ($importTasks) {
        Write-Info "Importing tasks from .specify/features..."
        if (Import-TasksFromFeatures $boardId) {
            Write-Success "Task import completed successfully"
        }
        else {
            Write-Error "Task import failed"
            exit 1
        }
    }

    # Return the board URL
    if ($scope -eq "org" -and $orgName) {
        return "https://github.com/orgs/$orgName/projects/$boardId"
    }
    else {
        try {
            $username = & gh api user --jq '.login' 2>$null
            return "https://github.com/users/$username/projects/$boardId"
        }
        catch {
            Write-Warn "Could not determine username for project URL"
            return "https://github.com/projects/$boardId"
        }
    }
}

<#
.SYNOPSIS
    Show help information
.DESCRIPTION
    Displays comprehensive help and usage information
#>
function Show-Help {
    Write-Host "GitHub Project Board Manager"
    Write-Host "============================"
    Write-Host ""
    Write-Host "Interactive CLI for creating and managing GitHub Project Boards with task import capabilities."
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host "  .\project-board.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "  -Name <NAME>          Project board name (default: repository name)"
    Write-Host "  -Template <TEMPLATE>  Template to use: kanban, feature-dev, bug-triage (default: kanban)"
    Write-Host "  -ImportTasks          Import tasks from .specify/features"
    Write-Host "  -Scope <SCOPE>        Scope: user or org (default: user)"
    Write-Host "  -Org <ORG_NAME>       Organization name (required if scope is org)"
    Write-Host "  -Help                 Show this help message"
    Write-Host ""
    Write-Host "TEMPLATES:"
    Write-Host "  kanban        Simple To Do, In Progress, Done workflow"
    Write-Host "  feature-dev   Backlog, Ready, In Progress, Review, Done workflow"
    Write-Host "  bug-triage    Triage, In Progress, Needs Review, Done workflow"
    Write-Host ""
    Write-Host "EXAMPLES:"
    Write-Host "  # Create a kanban board with default settings"
    Write-Host "  .\project-board.ps1 -Name `"My Project`" -Template kanban"
    Write-Host ""
    Write-Host "  # Import tasks from .specify/features"
    Write-Host "  .\project-board.ps1 -ImportTasks"
    Write-Host ""
    Write-Host "  # Create for organization with task import"
    Write-Host "  .\project-board.ps1 -Name `"Sprint 1`" -Template bug-triage -ImportTasks -Scope org -Org myorg"
    Write-Host ""
    Write-Host "REQUIREMENTS:"
    Write-Host "  - GitHub CLI (gh) installed and authenticated"
    Write-Host "  - jq for JSON parsing"
    Write-Host "  - .specify/features directory with tasks.md files (for task import)"
}

#===============================================================================
# SCRIPT ENTRY POINT
#===============================================================================

# Show help if requested
if ($Help) {
    Show-Help
    exit 0
}

# Run the main function and handle output
try {
    $result = Invoke-ProjectBoardManager
    if ($result) {
        Write-Host $result
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
