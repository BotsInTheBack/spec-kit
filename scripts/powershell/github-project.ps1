<#
.SYNOPSIS
    GitHub Project Board Manager - A PowerShell module for managing GitHub Projects (v2) boards.

.DESCRIPTION
    This script provides a comprehensive solution for managing GitHub Project Boards (v2) 
    through the GitHub CLI and GraphQL API. It simplifies the process of creating, 
    configuring, and managing project boards with various templates and task import capabilities.

    KEY FEATURES:
    - Create GitHub Projects with configurable templates (basic, kanban, bug-triage)
    - Import tasks from .specify/features directory with automatic issue creation
    - Support for both user and organization scoped projects
    - Interactive and non-interactive modes for CI/CD integration
    - Comprehensive error handling and logging
    - Support for GitHub Enterprise Server (via GitHub CLI configuration)

.PARAMETER Name
    Specifies the name of the GitHub Project board to create or manage.
    - Default: "Project Board"
    - Type: String
    - Example: -Name "Q3 Product Roadmap"

.PARAMETER ImportTasks
    When specified, automatically imports tasks from the .specify/features directory into the project board.
    - Type: SwitchParameter
    - Default: $false
    - Example: -ImportTasks

.PARAMETER Template
    Specifies the template to use for the project board configuration.
    - Type: String
    - Valid values: 'basic', 'kanban', 'bug-triage'
    - Default: 'kanban'
    - basic: Simple project with minimal configuration (Title, Status fields)
    - kanban: Board with Todo/In Progress/Done columns (default)
    - bug-triage: Board with priority and type fields for issue management

.PARAMETER Scope
    Specifies the scope under which to create the project.
    - Type: String
    - Valid values: 'user', 'org', 'auto'
    - Default: 'auto'
    - user: Creates project under the authenticated user's account
    - org: Creates project under an organization (will prompt for org name)
    - auto: Automatically detects the scope based on repository ownership

.PARAMETER Silent
    When specified, suppresses all non-essential output.
    - Type: SwitchParameter
    - Default: $false
    - Example: -Silent

.PARAMETER OrgName
    Specifies the organization name when Scope is set to 'org'.
    - Type: String
    - Example: -OrgName "my-org"

.PARAMETER NonInteractive
    Runs the script in non-interactive mode, using defaults where possible.
    - Type: SwitchParameter
    - Default: $false
    - Example: -NonInteractive

.PARAMETER DryRun
    Simulates the operations without making any actual changes.
    - Type: SwitchParameter
    - Default: $false
    - Example: -DryRun

.PARAMETER Help
    Displays the help message and exits.
    - Type: SwitchParameter
    - Example: -Help

.EXAMPLE
    # Create a kanban board with default name
    .\github-project.ps1 -Template kanban

.EXAMPLE
    # Create a board with custom name and template
    .\github-project.ps1 -Name "Q3 Features" -Template bug-triage

.EXAMPLE
    # Import tasks from .specify/features into a new project board
    .\github-project.ps1 -ImportTasks -Name "Feature Backlog"

.EXAMPLE
    # Create a project in a specific organization non-interactively
    .\github-project.ps1 -Name "Team Project" -Scope org -OrgName my-org -NonInteractive

.EXAMPLE
    # Simulate project creation without making changes
    .\github-project.ps1 -Name "Test Project" -DryRun

.NOTES
    PREREQUISITES:
    - PowerShell 5.1 or later
    - GitHub CLI (gh) installed and authenticated
    - jq for JSON processing (version 1.6 or later)
    - Git (version 2.25.0 or later)

    ENVIRONMENT VARIABLES:
    - GITHUB_TOKEN: Personal Access Token with 'repo', 'project', and 'workflow' scopes
    - GITHUB_ENTERPRISE_TOKEN: For GitHub Enterprise Server authentication

    ERROR HANDLING:
    - The script will exit with non-zero status code on critical errors
    - Warnings are displayed for non-critical issues
    - Detailed logs are available when -Verbose is specified

    SECURITY CONSIDERATIONS:
    - Always use the principle of least privilege for GitHub tokens
    - Review and audit the permissions granted to the GitHub token
    - Store sensitive values in environment variables or GitHub Secrets

    VERSION:
    1.0.0

.LINK
    GitHub CLI: https://cli.github.com/
    GitHub Projects API: https://docs.github.com/en/issues/planning-and-tracking-with-projects
    jq: https://stedolan.github.io/jq/
#>

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Improves performance on Windows

[CmdletBinding()]
param (
    [Parameter()]
    [string]$Name = "Project Board",
    
    [Parameter()]
    [switch]$ImportTasks,
    
    [Parameter()]
    [ValidateSet('basic', 'kanban', 'bug-triage')]
    [string]$Template = 'kanban',
    
    [Parameter()]
    [ValidateSet('user', 'org', 'auto')]
    [string]$Scope = 'auto',
    
    [Parameter()]
    [switch]$Silent,
    
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

<#
.SYNOPSIS
    Writes an informational message to the host.

.DESCRIPTION
    Outputs a formatted informational message to the console with a green [INFO] prefix.
    The message is only displayed if the script is not running in silent mode.

.PARAMETER Message
    The message to display.

.EXAMPLE
    Write-Info "Operation completed successfully"
#>
function Write-Info {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    if (-not $script:Silent) {
        Write-Host "[INFO] $Message" -ForegroundColor Green
    }
    
    # Optionally log to file if logging is enabled
    if ($script:EnableLogging) {
        Add-Content -Path $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] $Message"
    }
}

<#
.SYNOPSIS
    Writes a warning message to the host.

.DESCRIPTION
    Outputs a formatted warning message to the console with a yellow [WARNING] prefix.
    In silent mode, the message is displayed without a newline to allow for progress indicators.

.PARAMETER Message
    The warning message to display.

.EXAMPLE
    Write-Warning "This action will overwrite existing configuration"
#>
function Write-Warning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    if (-not $script:Silent) {
        Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    } else {
        Write-Host "[WARNING] $Message" -ForegroundColor Yellow -NoNewline
    }
    
    # Log to file if logging is enabled
    if ($script:EnableLogging) {
        Add-Content -Path $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARNING] $Message"
    }
}

<#
.SYNOPSIS
    Writes an error message to the host and exits the script.

.DESCRIPTION
    Outputs a formatted error message to the console with a red [ERROR] prefix
    and terminates the script with exit code 1.

.PARAMETER Message
    The error message to display before exiting.

.EXAMPLE
    Write-Error "Failed to authenticate with GitHub"
#>
function Write-Error {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    $errorMessage = "[ERROR] $Message"
    Write-Host $errorMessage -ForegroundColor Red
    
    # Log to file if logging is enabled
    if ($script:EnableLogging) {
        Add-Content -Path $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $errorMessage"
    }
    
    exit 1
}
}

<#
.SYNOPSIS
    Checks if a specified command is available in the system PATH.

.DESCRIPTION
    Verifies that a given command is installed and accessible from the current
    PowerShell session by checking the system PATH.

.PARAMETER Command
    The name of the command to check (e.g., 'git', 'gh', 'jq').

.RETURNS
    [bool] $true if the command exists, $false otherwise.

.EXAMPLE
    if (Test-CommandExists 'git') { Write-Info 'Git is installed' }
#>
function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    
    try {
        $null = Get-Command -Name $Command -ErrorAction Stop
        return $true
    } catch [System.Management.Automation.CommandNotFoundException] {
        return $false
    } catch {
        # Handle other potential errors
        Write-Warning "Error checking for command '$Command': $_"
        return $false
    }
}

<#
.SYNOPSIS
    Retrieves the version of a specified command-line tool.

.DESCRIPTION
    Gets the version number of common development tools (git, gh, jq) by
    executing their version commands and parsing the output.

.PARAMETER Command
    The command to check the version for. Supported values: 'git', 'gh', 'jq'.

.RETURNS
    [version] The version number of the command, or $null if the version
    could not be determined or the command is not supported.

.EXAMPLE
    $gitVersion = Get-CommandVersion 'git'
    if ($gitVersion -lt [version]'2.25.0') { Write-Warning 'Git version is outdated' }
#>
function Get-CommandVersion {
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('git', 'gh', 'jq')]
        [string]$Command
    )
    
    try {
        $versionString = $null
        
        switch ($Command) {
            'git' { 
                $versionString = (git --version 2>&1 | Select-Object -First 1) -replace '^git version ' -replace '\.[^.]*$' 
            }
            'gh' { 
                $versionString = (gh --version 2>&1 | Select-String -Pattern '^gh version \d+') -split '\s+' | Select-Object -Last 1
            }
            'jq' { 
                $versionString = (jq --version 2>&1) -replace 'jq-'
            }
        }
        
        if (-not [string]::IsNullOrEmpty($versionString)) {
            # Extract version numbers and convert to Version object
            $versionNumber = $versionString -replace '[^0-9.]'
            return [version]($versionNumber -replace '(?<=\d)\.\.+', '.')  # Handle multiple dots
        }
        
        return $null
    } catch {
        Write-Verbose "Failed to get version for $Command : $_"
        return $null
    }
}

<#
.SYNOPSIS
    Validates that all system requirements are met for the script to run.

.DESCRIPTION
    Checks for the presence and minimum versions of required command-line tools
    and verifies GitHub CLI authentication status. The function will attempt to
    guide the user through any missing requirements.

.NOTES
    The following tools are required:
    - Git (v2.25.0+)
    - GitHub CLI (v2.0.0+)
    - jq (v1.6+)

.EXAMPLE
    if (-not (Test-Requirements)) { exit 1 }

.RETURNS
    [bool] $true if all requirements are met, $false otherwise.
#>
function Test-Requirements {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Info "Checking system requirements..."
    
    # Required commands with minimum versions and installation URLs
    $requiredTools = @{
        'git' = @{
            MinVersion = [version]'2.25.0'
            HelpUrl = 'https://git-scm.com/downloads'
            TestCommand = 'git --version'
        }
        'gh' = @{
            MinVersion = [version]'2.0.0'
            HelpUrl = 'https://cli.github.com/'
            TestCommand = 'gh --version'
        }
        'jq' = @{
            MinVersion = [version]'1.6'
            HelpUrl = 'https://stedolan.github.io/jq/download/'
            TestCommand = 'jq --version'
        }
    }
    
    $missing = [System.Collections.Generic.List[string]]::new()
    $outdated = [System.Collections.Generic.List[string]]::new()
    $failedChecks = 0
    $allChecksPassed = $true
    
    # Check each required command
    foreach ($tool in $requiredTools.GetEnumerator()) {
        $toolName = $tool.Key
        $minVersion = $tool.Value.MinVersion
        $helpUrl = $tool.Value.HelpUrl
        
        Write-Verbose "Checking for $toolName (minimum version: $minVersion)..."
        
        # Check if command exists
        if (-not (Test-CommandExists $toolName)) {
            $missing.Add("$toolName (minimum version: $minVersion) - Install from: $helpUrl")
            $failedChecks++
            $allChecksPassed = $false
            continue
        }
        
        # Check command version
        $version = Get-CommandVersion $toolName
        if ($null -eq $version) {
            Write-Warning "Could not determine version for $toolName. Some features may not work as expected."
            # Don't fail for version check issues, but note it
            $allChecksPassed = $allChecksPassed -and ($toolName -ne 'gh') # Only fail for gh version check
            continue
        }
        
        # Verify minimum version
        if ($version -lt $minVersion) {
            $outdated.Add("$toolName (installed: $version, required: $minVersion) - Update from: $helpUrl")
            $failedChecks++
            $allChecksPassed = $false
        } else {
            Write-Verbose "$toolName $version is installed (minimum required: $minVersion)"
        }
    }
    
    # Report missing tools
    if ($missing.Count -gt 0) {
        Write-Warning "The following required tools are missing:"
        $missing | ForEach-Object { Write-Warning "  - $_" }
    }
    
    # Report outdated tools
    if ($outdated.Count -gt 0) {
        Write-Warning "The following tools need to be updated:"
        $outdated | ForEach-Object { Write-Warning "  - $_" }
    }
    
    # Check GitHub CLI authentication
    $ghAuthValid = $false
    if (Test-CommandExists 'gh') {
        try {
            $authStatus = gh auth status 2>&1
            if ($LASTEXITCODE -eq 0) {
                $ghAuthValid = $true
                $account = ($authStatus | Select-String 'Logged in to github.com as (\S+)').Matches.Groups[1].Value
                Write-Info "GitHub CLI authenticated as: $account"
            }
        } catch {
            Write-Verbose "GitHub CLI authentication check failed: $_"
        }
    }
    
    # Handle GitHub authentication
    if (-not $ghAuthValid) {
        Write-Warning "GitHub CLI is not authenticated or the session has expired."
        
        if ($NonInteractive) {
            Write-Warning "Running in non-interactive mode. Cannot prompt for authentication."
            $allChecksPassed = $false
        } else {
            try {
                Write-Info "Starting GitHub authentication..."
                $authResult = gh auth login 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $ghAuthValid = $true
                    $account = (gh api user --jq '.login') 2>$null
                    if ($account) {
                        Write-Info "Successfully authenticated as: $account"
                    } else {
                        Write-Info "Successfully authenticated to GitHub"
                    }
                } else {
                    Write-Warning "GitHub authentication failed. Please run 'gh auth login' manually."
                    $allChecksPassed = $false
                }
            } catch {
                Write-Warning "Failed to authenticate with GitHub: $_"
                $allChecksPassed = $false
            }
        }
    }
    
    # Only consider the check failed if we have missing/outdated tools or GitHub auth failed
    $requirementsMet = ($failedChecks -eq 0) -and $ghAuthValid
    
    if ($requirementsMet) {
        Write-Info "All system requirements are met."
        return $true
    } else {
        if (-not $allChecksPassed) {
            Write-Error "One or more system requirements are not met. Please address the issues above and try again."
        }
        return $allChecksPassed
    }
}

<#
.SYNOPSIS
    Retrieves information about the current Git repository.

.DESCRIPTION
    Extracts repository owner and name from the Git configuration by examining
    the 'origin' remote URL. Supports both HTTPS and SSH URL formats.

.OUTPUTS
    [PSCustomObject] An object with the following properties:
    - Owner: The repository owner (user or organization name)
    - Name: The repository name
    - FullName: The full repository name in 'owner/name' format
    - RemoteUrl: The remote URL of the repository

.EXAMPLE
    $repoInfo = Get-RepositoryInfo
    Write-Output "Repository: $($repoInfo.FullName)"

.THROWS
    Throws an error if not in a Git repository or if repository information
    cannot be determined from the remote URL.
#>
function Get-RepositoryInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Check if we're in a Git repository
        if (-not (Test-Path .git -PathType Container) -and 
            -not (git rev-parse --is-inside-work-tree 2>$null)) {
            throw "Not in a Git repository. Please run this script from within a Git repository."
        }
        
        # Get the remote URL
        $remoteUrl = git config --get remote.origin.url
        if (-not $remoteUrl) {
            throw "Could not determine remote URL. Please ensure you have a remote named 'origin' configured."
        }
        
        # Parse the remote URL to extract owner and repository name
        $owner = $null
        $repoName = $null
        
        # Handle both HTTPS and SSH URL formats:
        # HTTPS: https://github.com/owner/repo.git
        # SSH:   git@github.com:owner/repo.git
        # GitHub Enterprise: https://github.example.com/owner/repo.git or git@github.example.com:owner/repo.git
        
        if ($remoteUrl -match 'github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$') {
            # Matches both HTTPS and SSH URLs for github.com
            $owner = $Matches[1]
            $repoName = $Matches[2]
        } elseif ($remoteUrl -match '^https?://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$') {
            # Generic HTTPS URL (for GitHub Enterprise or other Git servers)
            $owner = $Matches[2]
            $repoName = $Matches[3]
        } elseif ($remoteUrl -match '^[^@]+@([^:]+):([^/]+)/([^/]+?)(?:\.git)?$') {
            # Generic SSH URL (for GitHub Enterprise or other Git servers)
            $owner = $Matches[2]
            $repoName = $Matches[3]
        }
        
        if (-not $owner -or -not $repoName) {
            throw "Could not parse repository information from remote URL: $remoteUrl"
        }
        
        # Remove .git suffix if present
        $repoName = $repoName -replace '\.git$', ''
        
        # Create and return a custom object with repository information
        return [PSCustomObject]@{
            Owner = $owner
            Name = $repoName
            FullName = "$owner/$repoName"
            RemoteUrl = $remoteUrl
        }
    } catch {
        Write-Error "Failed to get repository information: $_"
        throw
    }
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
        # Set default scope if not provided
        if (-not $PSBoundParameters.ContainsKey('Scope')) {
            $Scope = 'repo'
        }
        
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
                # For the new Projects API (v2), we need to use GraphQL
                $query = @"
                mutation { createProjectV2( input: { ownerId: "$owner_id" title: "$Name" } ) { projectV2 { id number title url } } }
"@
                
                Write-Info "Creating project '$Name' with $Template template using GitHub Projects (v2) API..."
                
                # Create a temporary file for error output
                $tempErrorFile = [System.IO.Path]::GetTempFileName()
                
                try {
                    # Create the project using GraphQL
                    $project = & {
                        $ErrorActionPreference = 'Continue'
                        $Error.Clear()
                        
                        # Make the GraphQL API request
                        $output = gh api graphql -f query="$query" 2> $tempErrorFile | ConvertFrom-Json
                        
                        if ($LASTEXITCODE -ne 0) {
                            $errorContent = Get-Content -Path $tempErrorFile -Raw -ErrorAction SilentlyContinue
                            throw "GitHub API Error: $errorContent"
                        }
                        
                        if (-not $output) {
                            throw "No response received from GitHub API"
                        }
                        
                        $output.data.createProjectV2.projectV2
                    }
                    
                    if (-not $project) {
                        $errorContent = Get-Content -Path $tempErrorFile -Raw -ErrorAction SilentlyContinue
                        throw "Failed to create project. Error: $errorContent"
                    }
                } catch {
                    $errorMessage = $_.Exception.Message
                    $errorContent = Get-Content -Path $tempErrorFile -Raw -ErrorAction SilentlyContinue
                    throw "Failed to create project: $errorMessage`nError details: $errorContent"
                } finally {
                    # Clean up the temporary file
                    if (Test-Path $tempErrorFile) {
                        Remove-Item -Path $tempErrorFile -Force -ErrorAction SilentlyContinue
                    }
                }
                
                $projectUrl = $project.url
                $projectId = $project.id
                $projectNumber = $project.number
                
                if (-not $projectUrl -or -not $projectId) {
                    $responseJson = $project | ConvertTo-Json -Depth 10
                    throw "Failed to parse project information from GitHub API response. Response: $responseJson"
                }
                
                # Link the project to the repository if we have the project ID and repo info
                if ($projectId -and $repoInfo.FullName) {
                    Write-Info "Linking repository $($repoInfo.FullName) to project..."
                    
                    # First, get the repository ID
                    $repoQuery = @"
                    query {
                      repository(owner: "$($repoInfo.Owner)", name: "$($repoInfo.Name)") {
                        id
                      }
                    }
"@
                    
                    try {
                        $repoInfo = gh api graphql -f query="$repoQuery" | ConvertFrom-Json
                        $repoId = $repoInfo.data.repository.id
                        
                        if (-not $repoId) {
                            throw "Could not get repository ID"
                        }
                        
                        # Link repository to project using GraphQL
                        $linkMutation = @"
                        mutation {
                          linkProjectV2ToRepository(
                            input: {
                              projectId: "$projectId"
                              repositoryId: "$repoId"
                            }
                          ) {
                            clientMutationId
                          }
                        }
"@
                        
                        $linkResult = gh api graphql -f query="$linkMutation" 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-Info "✅ Successfully linked project to repository: $($repoInfo.FullName)"
                        } else {
                            Write-Warning "Failed to link project to repository: $linkResult"
                            Write-Warning "You can try linking it manually through the GitHub web interface: $projectUrl"
                        }
                    } catch {
                        Write-Warning "Error linking project to repository: $_"
                        Write-Warning "You can try linking it manually through the GitHub web interface: $projectUrl"
                    }
                }
                
                # Set up project fields (replacing columns in Projects v2)
                Write-Info "Setting up project fields..."
                
                # First, get the default status field ID
                $fieldsQuery = @"
                query {
                  node(id: "$projectId") {
                    ... on ProjectV2 {
                      fields(first: 20) {
                        nodes {
                          ... on ProjectV2Field {
                            id
                            name
                            dataType
                          }
                          ... on ProjectV2SingleSelectField {
                            id
                            name
                            options {
                              id
                              name
                            }
                          }
                        }
                      }
                    }
                  }
                }
"@
                
                $fieldsInfo = gh api graphql -f query="$fieldsQuery" | ConvertFrom-Json
                
                # Check if we have a status field (similar to columns in Projects v1)
                $statusField = $fieldsInfo.data.node.fields.nodes | Where-Object { $_.name -eq "Status" } | Select-Object -First 1
                
                # Define status options based on template
                $statusOptions = @()
                switch ($Template) {
                    "kanban" { $statusOptions = @("To Do", "In Progress", "Done") }
                    "bug-triage" { $statusOptions = @("Triage", "Needs Triage", "High Priority", "Low Priority", "Closed") }
                    default { $statusOptions = @("To Do", "In Progress", "Done") }
                }
                
                if (-not $statusField) {
                    # Create a new status field if it doesn't exist
                    Write-Info "Creating status field with options..."
                    
                    # Format options for the mutation
                    $optionsJson = $statusOptions | ForEach-Object { @{ name = $_ } } | ConvertTo-Json -Compress
                    
                    $createFieldMutation = @"
                    mutation {
                      createProjectV2Field(
                        input: {
                          projectId: "$projectId"
                          dataType: SINGLE_SELECT
                          name: "Status"
                          singleSelectOptions: $($optionsJson -replace '"', '\"')
                        }
                      ) {
                        projectV2Field {
                          ... on ProjectV2SingleSelectField {
                            id
                            name
                            options {
                              id
                              name
                            }
                          }
                        }
                      }
                    }
"@
                    
                    $createFieldResult = gh api graphql -f query="$createFieldMutation" 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Info "✅ Created status field with options: $($statusOptions -join ', ')"
                    } else {
                        Write-Warning "Failed to create status field. You may need to set it up manually."
                    }
                } else {
                    Write-Info "Status field already exists. Skipping creation."
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
        
        Write-Info "Project created successfully: $projectUrl"
        
        # Set up project columns based on template
        $columns = @("To Do", "In Progress", "Done")  # Default columns
        
        if ($Template -eq "kanban") {
            $columns = @("To Do", "In Progress", "In Review", "Done")
        } elseif ($Template -eq "bug-triage") {
            $columns = @("Triage", "Needs Triage", "High Priority", "Low Priority", "Closed")
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
# Import tasks from .specify/features directory
function Import-TasksFromFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        
        [Parameter()]
        [string]$FeaturesDir = "/home/nullsetbuilds/NullSetBuilds-Workspace/projects/spec-kit/.specify/features"
    )
    
    if (-not (Test-Path $FeaturesDir -PathType Container)) {
        Write-Warning "Features directory not found at $FeaturesDir"
        return $false
    }
    
    Write-Info "Scanning for feature files in $FeaturesDir..."
    
    # Get all markdown files in the features directory
    $featureFiles = Get-ChildItem -Path $FeaturesDir -Filter "*.md" -Recurse -File
    
    if ($featureFiles.Count -eq 0) {
        Write-Warning "No feature files found in $FeaturesDir"
        return $true
    }
    
    Write-Info "Found $($featureFiles.Count) feature files to process"
    
    # Get repository info for issue creation
    $repoInfo = Get-RepositoryInfo
    $repoOwner = $repoInfo.owner
    $repoName = $repoInfo.name
    
    # Process each feature file
    foreach ($file in $featureFiles) {
        Write-Info "Processing feature file: $($file.FullName)"
        
        # Extract feature title from filename
        $featureTitle = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw
        
        # Extract tasks (lines starting with - [ ] or - [x])
        $tasks = $content -split "`n" | Where-Object { $_ -match '^- \[[ x]\] (.+)$' } | ForEach-Object {
            $matches[1]
        }
        
        if ($tasks.Count -gt 0) {
            Write-Info "Found $($tasks.Count) tasks in $featureTitle"
            
            # Add each task to the project board
            foreach ($task in $tasks) {
                Write-Info "Adding task: $task"
                
                # Create an issue for the task
                $issueBody = @"
Task from feature: $featureTitle

**Source File:** $($file.Name)
"@
                
                try {
                    # Create the issue
                    $issueResult = gh issue create --title $task --body $issueBody --json id,number,url
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to create issue for task: $task"
                        continue
                    }
                    
                    $issue = $issueResult | ConvertFrom-Json
                    
                    # Add issue to project board using GraphQL
                    $addToProjectMutation = @"
                    mutation {
                      addProjectV2ItemById(
                        input: {
                          projectId: "$ProjectId"
                          contentId: "$($issue.id)"
                        }
                      ) {
                        item {
                          id
                        }
                      }
                    }
"@
                    $addResult = gh api graphql -f query=$addToProjectMutation
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to add issue #$($issue.number) to project board"
                    }
                    
                    Write-Info "Added task: $task (Issue #$($issue.number))"
                }
                catch {
                    Write-Warning "Error processing task '$task': $_"
                }
            }
        }
        else {
            Write-Info "No tasks found in $featureTitle"
        }
    }
    
    return $true
}

function Start-ProjectWorkflow {
    [CmdletBinding()]
    param()
    
    # Default values
    $Name = 'Project Board'
    $Template = 'kanban'
    $Scope = 'auto'
    $OrgName = $null
    $NonInteractive = $false
    $DryRun = $false
    $Help = $false
    $ImportTasks = $false
    
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
            '^--import-tasks$' {
                $ImportTasks = $true
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
    
    # Execute the workflow
    if ($ImportTasks) {
        # Get repository info for project creation
        $repoInfo = Get-RepositoryInfo
        
        # Create the project board first
        Write-Info "Creating project board for task import..."
        $project = New-GitHubBoard @params
        
        if (-not $project -or -not $project.url) {
            Write-Error "Failed to create project board for task import"
            exit 1
        }
        
        # Import tasks from features
        $result = Import-TasksFromFeatures -ProjectId $project.id
        
        if ($result) {
            Write-Info "Task import completed successfully!"
            Write-Host "Project Board: $projectUrl" -ForegroundColor Green
        } else {
            Write-Warning "Task import completed with warnings"
        }
    } else {
        $params = @{
            Name = $Name
            Template = $Template
            Scope = $Scope
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

}

# Start the workflow
try {
    Start-ProjectWorkflow
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
