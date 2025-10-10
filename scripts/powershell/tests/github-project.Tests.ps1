#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for github-project.ps1 script
.DESCRIPTION
    This file contains Pester tests for the github-project.ps1 script.
    It tests both interactive and non-interactive modes, as well as error conditions.
#>

$ErrorActionPreference = 'Stop'

# Import the script file
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\github-project.ps1' -Resolve
. $scriptPath

describe 'github-project.ps1 Tests' {
    # Mock the gh CLI to avoid making real API calls during tests
    Mock gh {
        param($Command, $Api, $Method, $Body, $Query)
        
        switch -Wildcard ($Api) {
            'user' { 
                return '{"login": "testuser"}' 
            }
            'user/orgs' {
                return '[{"login": "testorg1"}, {"login": "testorg2"}]'
            }
            'repos/*' {
                return '{"name": "test-repo", "owner": {"login": "testuser"}, "default_branch": "main"}'
            }
            'graphql' {
                if ($Body -match 'query GetRepositoryId') {
                    return '{"data": {"repository": {"id": "R_12345"}}}'
                }
                return '{"data": {"createProjectV2": {"projectV2": {"id": "P_12345", "url": "https://github.com/users/testuser/projects/1"}}}}'
            }
        }
    }

    # Mock the Get-RepositoryInfo function to return test data
    Mock Get-RepositoryInfo {
        [PSCustomObject]@{
            Name = 'test-repo'
            Owner = 'testuser'
            IsOrganization = $false
            FullName = 'testuser/test-repo'
            DefaultBranch = 'main'
            RemoteUrl = 'https://github.com/testuser/test-repo.git'
        }
    }

    # Mock the Test-Path function to simulate .specify/features directory
    Mock Test-Path { return $true } -ParameterFilter { $Path -eq '.specify/features' }
    
    # Mock Get-ChildItem to return test feature files
    Mock Get-ChildItem {
        @(
            [PSCustomObject]@{
                FullName = '.specify/features/feature1.md'
                Name = 'feature1.md'
                BaseName = 'feature1'
            },
            [PSCustomObject]@{
                FullName = '.specify/features/feature2.md'
                Name = 'feature2.md'
                BaseName = 'feature2'
            }
        )
    } -ParameterFilter { $Path -eq '.specify/features' -and $Filter -eq '*.md' }

    # Mock Get-Content to return test feature content
    Mock Get-Content {
        switch ($Path) {
            '.specify/features/feature1.md' { '# Feature 1', 'Description 1' }
            '.specify/features/feature2.md' { '# Feature 2', 'Description 2' }
            default { '' }
        }
    }

    context 'Parameter Validation' {
        it 'Should accept valid template names' {
            { & $scriptPath -Template 'kanban' } | Should -Not -Throw
            { & $scriptPath -Template 'feature-dev' } | Should -Not -Throw
            { & $scriptPath -Template 'bug-triage' } | Should -Not -Throw
        }

        it 'Should reject invalid template names' {
            { & $scriptPath -Template 'invalid-template' -ErrorAction Stop } | Should -Throw
        }

        it 'Should require organization name with org scope' {
            { & $scriptPath -Scope 'org' -ErrorAction Stop } | Should -Throw
            { & $scriptPath -Scope 'org' -OrgName 'testorg' } | Should -Not -Throw
        }
    }

    context 'Interactive Mode' {
        it 'Should create a project with default values' {
            # Mock Read-Host to simulate user input
            Mock Read-Host { return '' } -ParameterFilter { $Prompt -like "Enter project board name*" }
            
            $result = & $scriptPath -NonInteractive
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeLike 'https://github.com/*'
        }

        it 'Should handle organization selection' {
            # Simulate user selecting an organization
            Mock Read-Host -ParameterFilter { $Prompt -like "Do you want to create this in an organization*" } { return 'y' }
            Mock Read-Host -ParameterFilter { $Prompt -like "Select an organization*" } { return '1' }
            
            $result = & $scriptPath -NonInteractive
            
            $result | Should -Not -BeNullOrEmpty
        }

        it 'Should handle task import confirmation' {
            # Simulate user confirming task import
            Mock Read-Host -ParameterFilter { $Prompt -like "Import these*" } { return 'y' }
            
            $result = & $scriptPath -NonInteractive -ImportTasks
            
            $result | Should -Not -BeNullOrEmpty
        }
    }

    context 'Non-Interactive Mode' {
        it 'Should create a project with specified parameters' {
            $projectName = 'Test Project '
            $result = & $scriptPath -Name $projectName -Template 'kanban' -NonInteractive
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeLike 'https://github.com/*'
        }

        it 'Should create an organization project with --org flag' {
            $result = & $scriptPath -Name 'Org Project' -Scope org -OrgName 'testorg' -NonInteractive
            
            $result | Should -Not -BeNullOrEmpty
        }
    }

    context 'Error Handling' {
        it 'Should handle missing repository information' {
            Mock Get-RepositoryInfo { throw 'Not a git repository' }
            
            { & $scriptPath -NonInteractive -ErrorAction Stop } | Should -Throw
        }

        it 'Should handle failed project creation' {
            Mock gh { throw 'API error' } -ParameterFilter { $Command -eq 'api' -and $Api -eq 'graphql' }
            
            { & $scriptPath -NonInteractive -ErrorAction Stop } | Should -Throw
        }
    }
}
