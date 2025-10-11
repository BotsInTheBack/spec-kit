#!/bin/bash

# Debug mode flag
DEBUG_MODE=false

# Parse debug flag first
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG_MODE=true
            shift
            ;;&  # Continue testing remaining patterns
        *)  # No more options
            break
            ;;&
    esac
done

# Debug output
if [ "$DEBUG_MODE" = true ]; then
    set -x
fi

# Color codes for output formatting
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NORMAL='\033[0m'
readonly NC='\033[0m' # No Color

# Default values
readonly DEFAULT_TEMPLATE="kanban"
readonly DEFAULT_SCOPE="user"

# Log an informational message
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Log a warning message
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Log an error message to stderr
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Show help message
show_help() {
    echo "Usage: $0 [--debug] [--name NAME] [--template TEMPLATE] [--scope SCOPE] [--org ORG] [--import-tasks]"
    echo "Create a GitHub project board with optional task import from .specify/features"
    echo ""
    echo "Options:"
    echo "  --name NAME         Name of the project board (required)"
    echo "  --template TEMPLATE  Board template (kanban, feature-dev, bug-triage)"
    echo "  --scope SCOPE       Create under 'user' or 'org' (default: user)"
    echo "  --org ORG           Organization name (required if scope is 'org')"
    echo "  --import-tasks      Import tasks from .specify/features"
    echo "  --debug             Enable debug output"
    echo "  --help              Show this help message"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if jq is available
check_jq() {
    if ! command_exists jq; then
        log_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
}

# Check if GitHub CLI is available and authenticated
check_gh() {
    if ! command_exists gh; then
        log_error "GitHub CLI (gh) is required but not installed. Please install it first."
        exit 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
}

# Check all requirements
check_requirements() {
    check_jq
    check_gh
}

# Main function
main() {
    # Default values
    local PROJECT_NAME=""
    local TEMPLATE="$DEFAULT_TEMPLATE"
    local IMPORT_TASKS=false
    local SCOPE="$DEFAULT_SCOPE"
    local ORG_NAME=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --template)
                TEMPLATE="$2"
                shift 2
                ;;
            --import-tasks)
                IMPORT_TASKS=true
                shift
                ;;
            --scope)
                SCOPE="$2"
                shift 2
                ;;
            --org)
                ORG_NAME="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            --debug)
                # Already handled at the beginning
                shift
                ;;
            *)
                log_warn "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Debug output
    if [ "$DEBUG_MODE" = true ]; then
        echo "=== DEBUG: Script started with the following parameters:" >&2
        echo "  PROJECT_NAME: $PROJECT_NAME" >&2
        echo "  TEMPLATE: $TEMPLATE" >&2
        echo "  SCOPE: $SCOPE" >&2
        echo "  ORG_NAME: $ORG_NAME" >&2
        echo "  IMPORT_TASKS: $IMPORT_TASKS" >&2
    fi

    # Validate required parameters
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Project name is required"
        show_help
        exit 1
    fi

    # Check requirements
    check_requirements

    log_info "Creating project board: $PROJECT_NAME"
    log_info "Template: $TEMPLATE"
    log_info "Scope: $SCOPE"
    if [ "$SCOPE" = "org" ]; then
        log_info "Organization: $ORG_NAME"
    fi
    log_info "Import tasks: $IMPORT_TASKS"

    # Create GitHub project board
    log_info "Creating project board on GitHub..."
    
    # Prepare the command based on scope
    if [ "$SCOPE" = "org" ]; then
        if [ -z "$ORG_NAME" ]; then
            log_error "Organization name is required when scope is org"
            exit 1
        fi
        PROJECT_CMD="gh project create --owner $ORG_NAME --title "$PROJECT_NAME" --template $TEMPLATE"
    else
        PROJECT_CMD="gh project create --owner "$(gh api user --jq .login)" --title "$PROJECT_NAME" --template $TEMPLATE"
    fi
    
    # Execute the command
    if ! eval "$PROJECT_CMD"; then
        log_error "Failed to create project board"
        exit 1
    fi
    
    log_success "Project board "$PROJECT_NAME" created successfully!"
    log_info "Project board creation would happen here"
    
    if [ "$IMPORT_TASKS" = true ]; then
        log_info "Task import would happen here"
    fi

    log_info "Project board created successfully!"
}

# Run the main function
main "$@"
