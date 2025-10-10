---
description: Interactive GitHub project board management with task import from .specify/features
name: projectize
category: project
icon: project
scripts:
  default: |
    #!/bin/bash
    set -e
    
    # Get script directory and set paths
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    BASH_SCRIPT="$(dirname "$0")/../../scripts/bash/project-board.sh"
    POWERSHELL_SCRIPT="$(dirname "$0")/../../scripts/powershell/project-board.ps1"
    
    # Detect OS and run appropriate script
    case "$(uname -s)" in
        Linux*|Darwin*)
            [ -f "$BASH_SCRIPT" ] && exec "$BASH_SCRIPT" "$@" || exit 1 ;;
        CYGWIN*|MINGW*|MSYS*)
            [ -f "$POWERSHELL_SCRIPT" ] && exec pwsh -File "$POWERSHELL_SCRIPT" "$@" || exit 1 ;;
        *)
            [ -f "$BASH_SCRIPT" ] && exec "$BASH_SCRIPT" "$@" || exit 1 ;;
    esac

# Interactive parameters - these will be prompted immediately
parameters:
  - name: project_name
    description: Name of the project board
    type: string
    required: true
    prompt: "What would you like to name your project board?"

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
    prompt: "Which template would you like to use?"

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
    prompt: "Where would you like to create this project?"

  - name: org_name
    description: Organization name (if scope is org)
    type: string
    required: false
    prompt: "Which organization should own this project? (Leave blank to skip)"
    when: scope == 'org'

  - name: import_tasks
    description: Import tasks from .specify/features
    type: boolean
    required: false
    default: true
    prompt: "Would you like to import tasks from .specify/features?"
