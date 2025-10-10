---
description: Interactive GitHub project board management with task import from .specify/features
name: projectize
category: project
icon: project
scripts:
  default: |
    #!/bin/bash
    set -e
    
    # Get the directory of this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    # Detect operating system
    detect_os() {
        case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*|MING*) 
          # Check for WSL (Windows Subsystem for Linux)
          if [ -f /proc/version ] && grep -q "Microsoft" /proc/version; then
            echo "wsl"
          else
            echo "windows"
          fi
          ;;
        *)          echo "unknown" ;;
      esac
    }
    
    # Get the OS and determine which script to run
    OS=$(detect_os)
    
    # Set script paths
    BASH_SCRIPT="$(dirname "$0")/../../scripts/bash/project-board.sh"
    POWERSHELL_SCRIPT="$(dirname "$0")/../../scripts/powershell/project-board.ps1"
    
    # Function to run the appropriate script
    run_script() {
      case "$1" in
        linux|macos|wsl)
          # On Linux, macOS, or WSL, prefer bash script
          if [ -f "$BASH_SCRIPT" ]; then
            echo "Running bash script (OS: $1)"
            "$BASH_SCRIPT" --interactive
          else
            echo "Bash script not found at $BASH_SCRIPT"
            exit 1
          fi
          ;;
        windows)
          # On Windows, prefer PowerShell
          if [ -f "$POWERSHELL_SCRIPT" ]; then
            echo "Running PowerShell script (OS: $1)"
            pwsh -File "$POWERSHELL_SCRIPT" -Interactive
          else
            echo "PowerShell script not found at $POWERSHELL_SCRIPT"
            exit 1
          fi
          ;;
        *)
          # Fallback to bash if available, otherwise PowerShell
          if [ -f "$BASH_SCRIPT" ]; then
            echo "Running bash script (fallback)"
            "$BASH_SCRIPT" --interactive
          elif [ -f "$POWERSHELL_SCRIPT" ]; then
            echo "Running PowerShell script (fallback)"
            pwsh -File "$POWERSHELL_SCRIPT" -Interactive
          else
            echo "No suitable script found"
            exit 1
          fi
          ;;
      esac
    }
    
    # Run the script
    run_script "$OS"

# Define parameters for interactive mode
parameters:
  - name: project_name
    description: Name of the project board
    type: string
    required: true
    prompt: What would you like to name your project board?
    
  - name: template
    description: Template to use for the project
    type: string
    required: true
    default: kanban
    choices:
      - name: Basic Kanban
        value: kanban
        description: Simple To Do, In Progress, Done workflow
      - name: Feature Development
        value: feature-dev
        description: Backlog, Ready, In Progress, Review, Done workflow
      - name: Bug Triage
        value: bug-triage
        description: Triage, In Progress, Needs Review, Done workflow
    prompt: Which template would you like to use?

  - name: scope
    description: Scope of the project (user or organization)
    type: string
    required: false
    default: user
    choices:
      - name: User
        value: user
        description: Create under your personal account
      - name: Organization
        value: org
        description: Create under an organization
    prompt: Where would you like to create this project?

  - name: org_name
    description: Organization name (if scope is org)
    type: string
    required: false
    prompt: Which organization should own this project? (Leave blank to skip)
    when: scope == 'org'

  - name: import_tasks
    description: Import tasks from .specify/features
    type: boolean
    required: false
    default: true
    prompt: Would you like to import tasks from .specify/features?
---
