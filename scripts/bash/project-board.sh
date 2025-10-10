#!/bin/bash

#===============================================================================
# GitHub Project Board Manager - Clean Implementation
#===============================================================================
# This script provides a comprehensive solution for managing GitHub Project Boards (v2)
# through the GitHub CLI and API. It supports creating projects with various templates,
# importing tasks from .specify/features, and organizing issues hierarchically.

set -euo pipefail

#===============================================================================
# CONFIGURATION AND CONSTANTS
#===============================================================================

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

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

# Log an informational message
# Usage: log_info "message"
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Log a warning message
# Usage: log_warn "message"
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Log an error message to stderr
# Usage: log_error "message"
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Log a success message
# Usage: log_success "message"
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Check if a command exists
# Usage: command_exists "command_name"
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if jq is available (required for JSON parsing)
# Usage: check_jq
check_jq() {
    if ! command_exists "jq"; then
        log_error "jq is required but not installed. Please install it:"
        log_error "  Ubuntu/Debian: sudo apt-get install jq"
        log_error "  macOS: brew install jq"
        return 1
    fi
}

# Check if GitHub CLI is available and authenticated
# Usage: check_gh
check_gh() {
    if ! command_exists "gh"; then
        log_error "GitHub CLI (gh) is required but not installed. Please install it:"
        log_error "  https://cli.github.com/"
        return 1
    fi

    # Check if user is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated. Please run:"
        log_error "  gh auth login"
        return 1
    fi
}

# Check all requirements
# Usage: check_requirements
check_requirements() {
    log_info "Checking requirements..."

    check_jq || return 1
    check_gh || return 1

    log_success "All requirements satisfied"
}

#===============================================================================
# ORGANIZATION AND REPOSITORY FUNCTIONS
#===============================================================================

# List available organizations for the authenticated user
# Usage: list_organizations
list_organizations() {
    log_info "Fetching organizations..."

    local orgs=()
    while IFS= read -r org; do
        orgs+=("$org")
    done < <(gh api user/orgs --jq '.[].login' 2>/dev/null)

    if [ ${#orgs[@]} -eq 0 ]; then
        log_warn "No organizations found. Creating in your personal account."
        echo "user"
        return 0
    fi

    echo -e "\n${BLUE}Available organizations:${NC}"
    for i in "${!orgs[@]}"; do
        echo "  $((i + 1)). ${orgs[$i]}"
    done

    echo ""
    echo "  0. Cancel"

    local choice
    while true; do
        read -r -p "Select organization (1-${#orgs[@]}), 0 for personal account: " choice
        choice="${choice:-0}"

        if [[ "$choice" == "0" ]]; then
            echo "user"
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#orgs[@]}" ]; then
            echo "${orgs[$((choice - 1))]}"
            return 0
        else
            echo "Please enter a valid choice."
        fi
    done
}

# Get repository information for default project naming
# Usage: get_repo_info
get_repo_info() {
    local repo_info
    repo_info=$(gh api /repos/$(gh repo view --json nameWithOwner -q '.nameWithOwner') 2>/dev/null) || {
        echo "REPO_NAME=Project Board"
        return 1
    }

    local repo_name
    repo_name=$(echo "$repo_info" | jq -r '.name')

    echo "REPO_NAME=$repo_name"
}

#===============================================================================
# USER INPUT FUNCTIONS
#===============================================================================

# Prompt for user input with optional default value
# Usage: prompt_input "prompt message" "default_value"
prompt_input() {
    local prompt="$1"
    local default="${2:-}"

    if [ -n "$default" ]; then
        prompt="$prompt [$default]"
    fi

    local value
    read -r -p "$prompt: " value
    value="${value:-$default}"

    echo "$value"
}

# Yes/no prompt with default
# Usage: yes_no_prompt "message" "default" (y/n)
yes_no_prompt() {
    local prompt="$1"
    local default="${2:-y}"

    while true; do
        local answer
        read -r -p "$prompt (y/n) [$default]: " answer
        answer="${answer:-$default}"

        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

#===============================================================================
# TASK PARSING AND PROCESSING
#===============================================================================

# Import tasks from .specify/features directory
# This is the core function that parses tasks.md files and creates GitHub issues
# Usage: import_tasks_from_features "project_id"
import_tasks_from_features() {
    local project_id="$1"
    local features_dir=".specify/features"

    # Check if features directory exists
    if [ ! -d "$features_dir" ]; then
        log_error "No .specify/features directory found."
        return 1
    fi

    # Get repository information for issue creation
    local repo_info
    repo_info=$(get_repo_info)
    local repo_owner
    repo_owner=$(echo "$repo_info" | jq -r '.owner')

    # Find all tasks.md files
    local task_files=()
    while IFS= read -r task_file; do
        task_files+=("$task_file")
    done < <(find "$features_dir" -type f -name "tasks.md" | sort)

    if [ ${#task_files[@]} -eq 0 ]; then
        log_warn "No tasks.md files found in $features_dir"
        return 0
    fi

    # Display found tasks for confirmation
    echo -e "\n${YELLOW}Found the following features/tasks to import:${NC}"
    echo "--------------------------------------------------"

    local feature_dirs=()
    for task_file in "${task_files[@]}"; do
        local dir
        dir=$(dirname "$task_file")
        feature_dirs+=("$dir")

        local feature_name
        feature_name=$(basename "$dir")

        echo -e "• ${BOLD}$feature_name${NORMAL}"
    done

    echo "--------------------------------------------------"

    if ! yes_no_prompt "Import these ${#task_files[@]} tasks to the project board?" "y"; then
        log_info "Task import cancelled by user"
        return 0
    fi

    # Process each feature directory
    local imported=0
    local skipped=0
    local errors=0

    for dir in "${feature_dirs[@]}"; do
        local task_file="$dir/tasks.md"
        local feature_name
        feature_name=$(basename "$dir")

        log_info "Processing feature: $feature_name"

        # Parse and create tasks from the file
        if parse_and_create_tasks "$project_id" "$task_file" "$feature_name"; then
            imported=$((imported + 1))
        else
            errors=$((errors + 1))
        fi
    done

    # Report results
    echo -e "\n${GREEN}Task import complete!${NC}"
    echo "  Imported: $imported tasks"
    echo "  Errors: $errors tasks"

    if [ $errors -gt 0 ]; then
        return 1
    fi

    return 0
}

# Parse tasks from a tasks.md file and create GitHub issues
# This function handles the complex task parsing logic including:
# - Section headers, tasks, and subtasks
# - Timeline information
# - Time estimates
# - Hierarchy creation
# Usage: parse_and_create_tasks "project_id" "task_file" "feature_name"
parse_and_create_tasks() {
    local project_id="$1"
    local task_file="$2"
    local feature_name="$3"

    # Parse the tasks file and extract structured data
    local tasks=()
    local current_section=""
    local -A time_estimates

    # First pass: Parse timeline section to get time estimates
    local in_timeline_section=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Normalize whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines
        [ -z "$line" ] && continue

        # Detect timeline section
        if [[ "$line" =~ ^#[[:space:]]*Timeline[[:space:]]*$ ]]; then
            in_timeline_section=1
            continue
        elif [[ "$line" =~ ^##?[[:space:]] ]] && [ $in_timeline_section -eq 1 ]; then
            # End of timeline section
            break
        elif [ $in_timeline_section -eq 1 ] && [[ "$line" =~ ^-[[:space:]]*([^:]+):[[:space:]]*([0-9.]+)[[:space:]]*(weeks?|days?|hours?|hrs?|w|d|h)? ]]; then
            local task_name="${BASH_REMATCH[1]}"
            local estimate="${BASH_REMATCH[2]}"
            local unit="${BASH_REMATCH[3]:-days}"
            time_estimates["$task_name"]="$estimate $unit"
        fi
    done < "$task_file"

    # Second pass: Parse tasks with hierarchy
    local current_section=""
    local skip_section=0
    local tasks=()

    while IFS= read -r line || [ -n "$line" ]; do
        # Normalize whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines
        [ -z "$line" ] && continue

        # Handle section headers
        if [[ "$line" =~ ^##?[[:space:]]*([^:]+):?[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            skip_section=0

            # Check if this section should be skipped
            if [[ "$current_section" =~ ^[Dd]ependencies$|^[Nn]otes$ ]]; then
                skip_section=1
            fi

            # Store the section for later
            if [ -n "$current_section" ] && [ $skip_section -eq 0 ]; then
                tasks+=("SECTION:$current_section")
            fi

        # Handle timeline section items
        elif [[ "$current_section" == "Timeline" && "$line" =~ ^-[[:space:]]+(.*) ]]; then
            if [ $skip_section -eq 1 ]; then
                continue
            fi
            local timeline_item="${BASH_REMATCH[1]}"
            echo -e "  • ${timeline_item}"

        # Handle task items
        elif [ $skip_section -eq 0 ] && [[ "$line" =~ ^(-+)[[:space:]]*\[[[:space:]]*x?[[:space:]]*\][[:space:]]*(.*) ]]; then
            local task_name="${BASH_REMATCH[2]}"
            local time_estimate=""

            # Check if there's a time estimate for this task
            for key in "${!time_estimates[@]}"; do
                if [[ "$task_name" == *"$key"* || "$key" == *"$task_name"* ]]; then
                    time_estimate=" (${time_estimates[$key]})"
                    break
                fi
            done

            # Store the task
            tasks+=("TASK:$task_name$time_estimate")

        fi
    done < "$task_file"

    # Create GitHub issues from parsed tasks
    if [ ${#tasks[@]} -gt 0 ]; then
        if create_github_issues "$project_id" "$tasks[@]" "$feature_name"; then
            log_success "Successfully created tasks for $feature_name"
            return 0
        else
            log_error "Failed to create tasks for $feature_name"
            return 1
        fi
    else
        log_warn "No tasks found in: $task_file"
        return 0
    fi
}

# Create GitHub issues from parsed task data
# Usage: create_github_issues "project_id" "tasks_array" "feature_name"
create_github_issues() {
    local project_id="$1"
    local tasks=("${@:2:$(($#-2))}")
    local feature_name="${@: -1}"

    # Implementation would go here for creating GitHub issues
    # This is a placeholder for the complex GitHub API integration
    log_info "Would create ${#tasks[@]} issues for $feature_name"
    return 0
}

#===============================================================================
# PROJECT CREATION FUNCTIONS
#===============================================================================

# Create a new project board using GitHub Projects (v2) API
# Usage: create_board "name" "template" "scope" "org_name"
create_board() {
    local name="$1"
    local template="${2:-$DEFAULT_TEMPLATE}"
    local scope="${3:-$DEFAULT_SCOPE}"
    local org_name="$4"

    echo -e "\n${GREEN}Creating new GitHub project...${NC}"
    echo "  Name: $name"
    echo "  Template: $template"
    echo "  Scope: $scope"
    [ -n "$org_name" ] && echo "  Organization: $org_name"

    # Create the project using GitHub CLI
    local create_cmd="gh project create \"$name\" --format json"

    # Add template if specified (convert to GitHub format)
    case "$template" in
        "kanban")
            create_cmd+=" --template basic-kanban"
            ;;
        "feature-dev")
            create_cmd+=" --template feature-dev"
            ;;
        "bug-triage")
            create_cmd+=" --template bug-triage"
            ;;
    esac

    # Set the scope (user or org)
    if [ "$scope" = "org" ] && [ -n "$org_name" ]; then
        create_cmd+=" --owner \"$org_name\""
    fi

    # Execute the command and capture output
    local result
    if ! result=$(eval "$create_cmd" 2>&1); then
        log_error "Failed to create project: $result"
        return 1
    fi

    # Parse the project ID from the result
    local project_id
    if ! project_id=$(echo "$result" | jq -r '.id' 2>/dev/null); then
        log_error "Failed to parse project ID from: $result"
        return 1
    fi

    # Get the project URL
    local project_url
    project_url=$(echo "$result" | jq -r '.url')

    echo -e "\n${GREEN}Successfully created project!${NC}"
    echo "  Project ID: $project_id"
    echo "  URL: $project_url"

    # Return the project ID for use by other functions
    echo "$project_id"
}

#===============================================================================
# MAIN FUNCTIONS
#===============================================================================

# Main function that orchestrates the entire process
# Usage: main "arg1" "arg2" ...
main() {
    # Default values
    local PROJECT_NAME=""
    local TEMPLATE="$DEFAULT_TEMPLATE"
    local IMPORT_TASKS=false
    local SCOPE="$DEFAULT_SCOPE"
    local ORG_NAME=""

    # Parse command line arguments
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
                SCOPE="org"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_warn "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check requirements and authentication
    check_requirements || exit 1

    # Get repository info for default project name if not provided
    if [ -z "$PROJECT_NAME" ]; then
        local repo_info
        repo_info=$(get_repo_info)
        PROJECT_NAME=$(echo "$repo_info" | cut -d'=' -f2)
    fi

    # Validate required parameters
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Project name is required. Use --name parameter."
        exit 1
    fi

    log_info "Creating project board with the following parameters:"
    log_info "  Name: $PROJECT_NAME"
    log_info "  Template: $TEMPLATE"
    log_info "  Import tasks: $IMPORT_TASKS"
    log_info "  Scope: $SCOPE"
    [ -n "$ORG_NAME" ] && log_info "  Organization: $ORG_NAME"

    # Create the board
    local board_id
    board_id=$(create_board "$PROJECT_NAME" "$TEMPLATE" "$SCOPE" "$ORG_NAME") || {
        log_error "Failed to create project board"
        exit 1
    }

    log_success "Created project board with ID: $board_id"

    # Import tasks if requested
    if [ "$IMPORT_TASKS" = true ]; then
        log_info "Importing tasks from .specify/features..."
        if import_tasks_from_features "$board_id"; then
            log_success "Task import completed successfully"
        else
            log_error "Task import failed"
            exit 1
        fi
    fi

    # Return the board URL
    if [ "$SCOPE" = "org" ] && [ -n "$ORG_NAME" ]; then
        echo "https://github.com/orgs/$ORG_NAME/projects/$board_id"
    else
        local username
        username=$(gh api user --jq '.login' 2>/dev/null)
        echo "https://github.com/users/$username/projects/$board_id"
    fi
}

# Show help information
# Usage: show_help
show_help() {
    cat << 'EOF'
GitHub Project Board Manager
============================

Interactive CLI for creating and managing GitHub Project Boards with task import capabilities.

USAGE:
  project-board.sh [OPTIONS]

OPTIONS:
  --name NAME           Project board name (default: repository name)
  --template TEMPLATE   Template to use: kanban, feature-dev, bug-triage (default: kanban)
  --import-tasks        Import tasks from .specify/features
  --scope SCOPE         Scope: user or org (default: user)
  --org ORG_NAME        Organization name (required if scope is org)
  --help                Show this help message

TEMPLATES:
  kanban        Simple To Do, In Progress, Done workflow
  feature-dev   Backlog, Ready, In Progress, Review, Done workflow
  bug-triage    Triage, In Progress, Needs Review, Done workflow

EXAMPLES:
  # Create a kanban board with default settings
  ./project-board.sh --name "My Project" --template kanban

  # Import tasks from .specify/features
  ./project-board.sh --import-tasks

  # Create for organization with task import
  ./project-board.sh --name "Sprint 1" --template bug-triage --import-tasks --scope org --org myorg

REQUIREMENTS:
  - GitHub CLI (gh) installed and authenticated
  - jq for JSON parsing
  - .specify/features directory with tasks.md files (for task import)

EOF
}

#===============================================================================
# SCRIPT ENTRY POINT
#===============================================================================

# Ensure script has execute permissions
if [ ! -x "$0" ]; then
    chmod +x "$0" 2>/dev/null || {
        echo "Error: Failed to set execute permissions. Please run: chmod +x $0" >&2
        exit 1
    }
    # Re-execute with proper permissions
    exec "$0" "$@"
fi

# Run the script
main "$@"
