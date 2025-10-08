#!/bin/bash

# GitHub Project Board Manager
# A script for managing GitHub project boards in existing repositories

# Exit on error and undefined variables
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Check for required commands
check_requirements() {
    local missing=()
    
    # Check for required commands
    for cmd in git gh jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        echo -e "Please install the missing requirements and try again:"
        echo -e "- GitHub CLI: https://cli.github.com/"
        echo -e "- Git: https://git-scm.com/downloads"
        echo -e "- jq: https://stedolan.github.io/jq/download/"
        exit 1
    fi
}

# Check GitHub authentication
check_auth() {
    if ! gh auth status &> /dev/null; then
        log_warn "GitHub CLI is not authenticated. Starting authentication..."
        if ! gh auth login; then
            log_error "GitHub authentication failed. Please run 'gh auth login' manually."
        fi
    fi
}

# Get repository information
get_repo_info() {
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        log_error "Not a git repository. Please run this command from within a git repository."
    fi

    REPO_OWNER=$(git remote -v | grep -m 1 "origin" | sed -e 's/.*github.com[:/]\([^/]*\).*/\1/')
    REPO_NAME=$(basename -s .git `git config --get remote.origin.url`)
    
    if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
        log_error "Could not determine repository owner or name. Make sure you have a remote named 'origin'."
    fi
}

# Prompt for user input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    if [ -n "$default" ]; then
        read -p "${prompt} [${BLUE}${default}${NC}]: " input
    else
        read -p "${prompt}: " input
    fi
    
    echo "${input:-$default}"
}

# Prompt for yes/no with default
yes_no_prompt() {
    local prompt="$1"
    local default="${2:-y}"
    local choices="[y/n]"
    
    if [[ "$default" =~ ^[Yy]$ ]]; then
        choices="[Y/n]"
    else
        choices="[y/N]"
    fi
    
    while true; do
        read -p "${prompt} ${choices}: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) 
                if [ -z "$yn" ]; then
                    [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
                fi
                echo "Please answer yes or no.";;
        esac
    done
}

# Create a new project board
create_board() {
    local board_name="${1:-Project Board}"
    local template="${2:-kanban}"
    local scope="${3:-user}"  # 'user' or 'org'
    local org_name="${4:-}"   # Organization name if scope is 'org'
    
    log_info "Creating '$board_name' with $template template..."
    
    # Get repository information
    local repo_info
    repo_info=$(gh repo view --json nameWithOwner,name,owner,isInOrganization -q '.nameWithOwner' 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$repo_info" ]; then
        log_warn "Could not determine repository information. Project will be created without repository linking."
        local repo_name=""
        local is_org_repo="false"
    else
        # Get repository name and owner
        local repo_name
        repo_name=$(gh repo view --json name -q '.name' 2>/dev/null)
        local is_org_repo
        is_org_repo=$(gh repo view --json isInOrganization -q '.isInOrganization' 2>/dev/null || echo "false")
    fi
    
    # Determine project scope and owner
    local target_owner=""
    local api_endpoint=""
    local attempt_count=0
    local max_attempts=2
    local project_json=""
    
    while [ $attempt_count -lt $max_attempts ]; do
        # Reset variables for each attempt
        target_owner=""
        api_endpoint=""
        
        # Determine project scope based on current attempt
        if [ $attempt_count -eq 0 ] && { [ "$scope" = "org" ] || [ "$is_org_repo" = "true" ]; }; then
            # First attempt: Try organization scope if specified or in an org repo
            if [ -z "$org_name" ] && [ "$is_org_repo" = "true" ]; then
                # Auto-detect organization from repository
                org_name=$(gh repo view --json owner -q '.owner.login' 2>/dev/null)
            fi
            
            if [ -n "$org_name" ]; then
                target_owner="$org_name"
                api_endpoint="/orgs/$target_owner/projects"
                scope="org"
                log_info "Attempting to create organization project in: $target_owner"
            fi
        else
            # Second attempt or user scope: Create user project
            scope="user"
            api_endpoint="/user/projects"
            log_info "Creating user project"
        fi
        
        # Create project using GitHub CLI
        log_info "Creating project: $board_name"
        project_json=$(gh api -X POST \
            -H "Accept: application/vnd.github.v3+json" \
            "$api_endpoint" \
            -f name="$board_name" \
            -f body="Project board for ${target_owner:-$repo_name}" 2>&1 || echo "ERROR:$?")
        
        # Check for permission errors
        if [[ "$project_json" == *"Resource not accessible by personal access token"* ]] || 
           [[ "$project_json" == *"Not Found"* ]] || 
           [[ "$project_json" == ERROR* ]]; then
            
            if [ "$scope" = "org" ]; then
                log_warn "Failed to create organization project in '$target_owner': $project_json"
                log_warn "This might be due to insufficient permissions or the organization might not exist"
                
                # If we have more attempts, try user project next
                if [ $attempt_count -eq 0 ] && [ "$is_org_repo" = "true" ]; then
                    log_info "Will attempt to create a personal project instead..."
                    attempt_count=$((attempt_count + 1))
                    continue
                fi
                
                if [ "$is_org_repo" = "true" ]; then
                    log_error "Cannot create project in organization '$target_owner'. Please check your permissions and try again."
                    return 1
                fi
                
                if ! yes_no_prompt "Would you like to create a personal project instead?" "y"; then
                    log_error "Project creation cancelled"
                    return 1
                fi
                
                attempt_count=$((attempt_count + 1))
                continue
            else
                log_error "Failed to create personal project: $project_json"
                return 1
            fi
        else
            # Successfully created project
            break
        fi
    done
    
    # If we've exhausted all attempts without success
    if [ -z "$project_json" ] || [[ "$project_json" == ERROR* ]]; then
        log_error "Failed to create project after $max_attempts attempts"
        return 1
    fi
    
    # Extract project URL and number from the output
    local project_url
    project_url=$(echo "$project_json" | jq -r '.html_url // empty' 2>/dev/null)
    local project_number
    project_number=$(echo "$project_json" | jq -r '.number // empty' 2>/dev/null)
    
    if [ -z "$project_url" ] || [ -z "$project_number" ]; then
        log_error "Failed to parse project information from GitHub API response"
        log_error "API Response: $project_json"
        return 1
    fi
    
    # Link the project to the repository if we have the project number and repo info
    if [ -n "$project_number" ] && [ -n "$repo_name" ]; then
        log_info "Linking project to repository $repo_name..."
        
        # Build the link command based on the scope
        local link_cmd="gh project link $project_number --repo "
        local link_target=""
        
        if [ "$scope" = "org" ] && [ -n "$target_owner" ]; then
            link_target="$target_owner/$repo_name"
        else
            # For user projects, we need to get the current user's login
            local current_user
            current_user=$(gh api user -q '.login' 2>/dev/null || echo "")
            if [ -n "$current_user" ]; then
                link_target="$current_user/$repo_name"
            else
                link_target="$repo_name"
            fi
        fi
        
        link_cmd+="$link_target"
        
        if ! eval "$link_cmd" >/dev/null 2>&1; then
            log_warn "Failed to link project to repository. You may need to link it manually."
            log_warn "Command to link manually: $link_cmd"
            log_warn "Or visit: $project_url to link the repository through the web interface"
        else
            log_info "✅ Successfully linked project to repository: $link_target"
        fi
    else
        log_warn "Skipping repository linking - missing project number or repository information"
    fi
    
    log_info "✅ Project board created successfully: $project_url"
    echo "$project_url"
    return 0
}

# Show help
show_help() {
    echo "GitHub Project Board Manager"
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  add-board         Create a new project board (default)"
    echo "  import-tasks      Import tasks from a file (not yet implemented)"
    echo ""
    echo "Options:"
    echo "  -n, --name NAME     Name of the project board (default: Project Board)"
    echo "  -t, --template TPL  Template to use (kanban, basic, bug-triage) (default: kanban)"
    echo "  -s, --scope SCOPE   Project scope: 'user' or 'org' (default: auto-detect)"
    echo "  -o, --org ORG       Organization name (required if scope is 'org')"
    echo "  -y, --yes           Skip all confirmation prompts"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add-board --name "My Project" --template kanban"
    echo "  $0 --org myorg --name "Team Project" --scope org"
}

# Main function
main() {
    check_requirements
    check_auth
    get_repo_info
    
    # Default values
    local action="add-board"
    local board_name="Project Board"
    local template="kanban"
    local scope="auto"
    local org_name=""
    local skip_prompts=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            add-board|import-tasks)
                action="$1"
                shift
                ;;
            -n|--name)
                board_name="$2"
                shift 2
                ;;
            -t|--template)
                template="$2"
                shift 2
                ;;
            -s|--scope)
                scope="${2,,}"  # Convert to lowercase
                if [[ ! "$scope" =~ ^(user|org|auto)$ ]]; then
                    log_error "Invalid scope: $scope. Must be 'user', 'org', or 'auto'"
                    show_help
                    exit 1
                fi
                shift 2
                ;;
            -o|--org)
                org_name="$2"
                scope="org"  # If org is specified, force scope to org
                shift 2
                ;;
            -y|--yes)
                skip_prompts=true
                shift
                ;;
            -h|--help)
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
    
    # Get repository information for auto-detection
    local is_org_repo="false"
    local repo_owner=""
    
    # Check if we're in a Git repository with GitHub remote
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        # Get repository owner and organization status
        if gh repo view --json isInOrganization,owner 2>/dev/null >/dev/null; then
            is_org_repo=$(gh repo view --json isInOrganization -q '.isInOrganization' 2>/dev/null || echo "false")
            repo_owner=$(gh repo view --json owner -q '.owner.login' 2>/dev/null || echo "")
            
            if [ -n "$repo_owner" ] && [ "$is_org_repo" = "true" ]; then
                log_info "Detected organization repository. Owner: $repo_owner"
            elif [ -n "$repo_owner" ]; then
                log_info "Detected personal repository. Owner: $repo_owner"
            fi
        else
            log_warn "Could not determine repository information. Project will be created without repository linking."
        fi
    else
        log_warn "Not in a Git repository. Project will be created without repository linking."
    fi
    
    # Auto-detect scope if not specified
    if [ "$scope" = "auto" ]; then
        if [ -n "$org_name" ]; then
            scope="org"
            log_info "Using organization from command line: $org_name"
        elif [ "$is_org_repo" = "true" ] && [ -n "$repo_owner" ]; then
            if [ "$skip_prompts" = true ] || yes_no_prompt "Create project in organization '$repo_owner'?" "y"; then
                scope="org"
                org_name="$repo_owner"
                log_info "Using repository organization: $org_name"
            else
                scope="user"
                log_info "Creating personal project instead"
            fi
        else
            scope="user"
            log_info "Defaulting to personal project"
        fi
    fi
    
    # If scope is org but no org name is provided, prompt for it or use repo owner
    if [ "$scope" = "org" ] && [ -z "$org_name" ]; then
        if [ "$skip_prompts" = true ]; then
            log_error "Organization name is required for organization-scoped projects"
            exit 1
        fi
        
        # Suggest the repository owner if available and in an org
        local suggested_org=""
        if [ -n "$repo_owner" ] && [ "$is_org_repo" = "true" ]; then
            suggested_org="$repo_owner"
        fi
        
        org_name=$(prompt_input "Enter organization name" "$suggested_org")
        if [ -z "$org_name" ]; then
            log_error "Organization name cannot be empty"
            exit 1
        fi
    fi
    
    # Confirm before creating the project
    if [ "$skip_prompts" = false ]; then
        local scope_display="personal account"
        if [ "$scope" = "org" ]; then
            scope_display="organization '$org_name'"
        fi
        
        echo -e "\n${YELLOW}About to create project:${NC}"
        echo -e "  Name:    ${BLUE}$board_name${NC}"
        echo -e "  Scope:   ${BLUE}$scope_display${NC}"
        echo -e "  Template: ${BLUE}$template${NC}"
        
        if [ "$scope" = "org" ]; then
            echo -e "${YELLOW}Note:${NC} You'll need 'write' or 'admin' permissions on the organization to create projects."
            echo -e "      If you don't have sufficient permissions, the script will attempt to create a personal project instead.\n"
        fi
        
        if ! yes_no_prompt "Proceed with project creation?" "y"; then
            log_info "Project creation cancelled"
            exit 0
        fi
    fi
    
    # Call the appropriate action
    if [ "$action" = "add-board" ]; then
        create_board "$board_name" "$template" "$scope" "$org_name"
    else
        log_info "Action '$action' will be implemented in a future version"
    fi
}

# Show help
show_help() {
    cat << EOF
GitHub Project Board Manager
=========================

Usage: $0 [OPTIONS]

Options:
  -n, --name NAME       Board name (default: "Project Board")
  -t, --template TYPE   Board template: basic, kanban, or bug-triage (default: kanban)
  -h, --help            Show this help message

Templates:
  basic        Simple board with: To Do, In Progress, Done
  kanban       Kanban board with: Backlog, To Do, In Progress, In Review, Done
  bug-triage   Bug tracking board with: Reported, Needs Triage, In Progress, Needs Fix, Resolved

Examples:
  # Create a kanban board with default name
  $0 --template kanban

  # Create a board with custom name and template
  $0 --name "My Project" --template bug-triage
EOF
}

# Ensure script has execute permissions
if [ ! -x "$0" ]; then
    chmod +x "$0" 2>/dev/null || {
        echo "Error: Failed to set execute permissions. Please run: chmod +x $0" >&2
        exit 1
    }
    # Re-execute with proper permissions
    exec "$0" "$@"
fi

set -e  # Exit on error

# Check for required commands
check_requirements() {
    local missing=()
    
    # Check for required commands
    for cmd in git gh jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[ERROR]${NC} The following requirements are missing:" >&2
        for cmd in "${missing[@]}"; do
            echo -e "  - $cmd" >&2
        done
        echo -e "\nPlease install the missing requirements and try again." >&2
        echo -e "GitHub CLI: https://cli.github.com/" >&2
        echo -e "Git: https://git-scm.com/downloads" >&2
        echo -e "jq: https://stedolan.github.io/jq/download/" >&2
        exit 1
    fi

    # Check GitHub CLI authentication
    if ! gh auth status &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} GitHub CLI is not authenticated. Please run 'gh auth login' first." >&2
        exit 1
    fi
}

# Run requirements check
check_requirements

# Initialize variables
ACTION="create"  # Default action
REPO_OWNER=""
REPO_NAME=""
PROJECT_NAME=""
BOARD_NAME=""
DESCRIPTION=""
TEMPLATE="basic"
BOARD_TEMPLATE="basic"
NON_INTERACTIVE=false
IMPORT_TASKS=false
DRY_RUN=false

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Show help
show_help() {
    cat << EOF
GitHub Project Board Manager
=========================

Usage: $0 [ACTION] [OPTIONS]

Actions:
  $0 [add-board] [options]  Add a project board to the current repository (default action)
  $0 import-tasks            Import tasks from .specify/features to a project board

Options:
  -n, --name NAME           Board name (default: "Project Board")
  -d, --description TEXT    Board description
  -t, --template TYPE       Board template: basic, kanban, or bug-triage (default: kanban)
  -o, --owner USER          Repository owner (default: detected from git)
  -r, --repo REPO           Repository name (default: detected from git)
  --non-interactive         Run without interactive prompts
  --dry-run                 Show what would be done without making changes
  -h, --help                Show this help message

Templates:
  basic        Simple board with: To Do, In Progress, Done
  kanban       Kanban board with: Backlog, To Do, In Progress, In Review, Done
  bug-triage   Bug tracking board with: Reported, Needs Triage, In Progress, Needs Fix, Resolved

Examples:
  # Add a kanban board with default name
  $0 --template kanban

  # Add a bug-triage board with custom name
  $0 --name "Bug Tracking" --template bug-triage

  # Import tasks to an existing project
  $0 import-tasks
EOF
}
        # Set default values
    ACTION="add-board"
    BOARD_NAME="Project Board"
    TEMPLATE="kanban"
    
    # Process command line arguments
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -n|--name)
                BOARD_NAME="$2"
                shift 2
                ;;
            -t|--template)
                TEMPLATE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                # If it's a known action, use it
                if [[ "$1" =~ ^(add-board|import-tasks)$ ]]; then
                    ACTION="$1"
                fi
                shift
                ;;
        esac
    done

    case "$action" in
        add-board)
            create_board "$board_name" "$template" "$scope" "$org_name"
            ;;
        import-tasks)
            log_error "Import tasks not yet implemented"
            exit 1
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Run the script
main "$@"
