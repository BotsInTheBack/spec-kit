#!/bin/bash

# =============================================================================
# GitHub Project Board Manager
# =============================================================================
#
# OVERVIEW:
#   A comprehensive script for managing GitHub project boards through the
#   GitHub CLI (gh) and GitHub's GraphQL API. Supports creating, configuring,
#   and managing project boards with various templates and task import features.
#
# FEATURES:
#   - Create GitHub Projects (v2) with different templates
#   - Import tasks from .specify/features directory
#   - Interactive and non-interactive modes
#   - Detailed logging and error handling
#   - Support for both user and organization projects
#
# PREREQUISITES:
#   - GitHub CLI (gh) installed and authenticated
#   - jq for JSON processing
#   - Standard GNU tools (grep, sed, awk, etc.)
#
# USAGE:
#   ./github-project.sh [--verbose] [options]
#
# For detailed help:
#   ./github-project.sh --help
#
# =============================================================================

# Exit on error, undefined variables, and pipeline failures
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Process command-line arguments
# Handle --verbose flag if it's the first argument
if [ "$#" -gt 0 ] && [ "$1" = "--verbose" ]; then
    VERBOSE=1
    shift
else
    VERBOSE=${VERBOSE:-}
fi

# Logging functions
log_info() {
    [ -n "$VERBOSE" ] && echo -e "${GREEN}[INFO]${NC} $1"
    return 0
}

log_warn() {
    if [ -n "$VERBOSE" ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    else
        echo -e -n "${YELLOW}[WARNING]${NC} $1" >&2
    fi
    return 0
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# =============================================================================
# REQUIREMENT CHECKS
# =============================================================================

# Check for required commands and their minimum versions
# 
# This function verifies that all required commands are installed and meet the
# minimum version requirements. It will log warnings for missing optional
# dependencies and errors for required ones.
#
# Global Variables:
#   - Sets $failed_checks to the number of failed checks
#
# Returns:
#   - 0 if all requirements are met
#   - 1 if any required checks fail
check_requirements() {
    local missing=()
    failed_checks=0
    
    # Required commands with minimum versions
    declare -A required_commands=(
        ["git"]="2.25.0"
        ["gh"]="2.0.0"
        ["jq"]="1.6"
    )
    
    log_info "Checking system requirements..."
    
    # Check each required command
    for cmd in "${!required_commands[@]}"; do
        local min_version="${required_commands[$cmd]}"
        
        # Check if command exists
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd (minimum version: $min_version)")
            failed_checks=$((failed_checks + 1))
            continue
        fi
        
        # Check command version if version check is supported
        if [ "$cmd" = "git" ]; then
            local current_version
            current_version=$(git --version | awk '{print $3}')
            if [ "$(printf "%s\n%s" "$min_version" "$current_version" | sort -V | head -n1)" != "$min_version" ]; then
                log_warn "$cmd version $current_version is below minimum required version $min_version"
                failed_checks=$((failed_checks + 1))
            fi
        elif [ "$cmd" = "gh" ]; then
            if ! gh --version &> /dev/null; then
                log_warn "Failed to check $cmd version. Please ensure it's properly installed."
                failed_checks=$((failed_checks + 1))
            fi
        fi
    done
    
    # Check GitHub CLI authentication
    if command -v gh &> /dev/null && ! gh auth status &> /dev/null; then
        log_warn "GitHub CLI is not authenticated. Run 'gh auth login' to authenticate."
        failed_checks=$((failed_checks + 1))
    fi
    
    # Report any missing or outdated dependencies
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        failed_checks=$((failed_checks + ${#missing[@]}))
    fi
    
    # Provide installation instructions if any checks failed
    if [ $failed_checks -gt 0 ]; then
        echo -e "\n${YELLOW}Installation Instructions:${NC}"
        echo -e "1. Git: Install from ${BLUE}https://git-scm.com/downloads${NC}"
        echo -e "2. GitHub CLI: Install from ${BLUE}https://cli.github.com/${NC}"
        echo -e "   - After installation, run: ${BLUE}gh auth login${NC}"
        echo -e "3. jq: Install from ${BLUE}https://stedolan.github.io/jq/download/${NC}"
        echo -e "\n${RED}Please install the missing requirements and try again.${NC}"
        exit 1
    fi
    
    # Verify GitHub CLI has necessary permissions
    if command -v gh &> /dev/null; then
        local has_project_scope
        has_project_scope=$(gh auth status -t 2>&1 | grep -c 'project' || true)
        if [ "$has_project_scope" -eq 0 ]; then
            log_warn "GitHub CLI token may not have the required 'project' scope"
            echo -e "To update your token scopes, visit: ${BLUE}https://github.com/settings/tokens${NC}"
            echo -e "Make sure to include the 'project' scope when creating a new token."
            if [ "$skip_prompts" = false ] && ! yes_no_prompt "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    fi
    
    log_success "All requirements met"
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

# Import tasks from .specify/features directory
import_tasks_from_features() {
    local project_id="$1"  # Now expects project ID instead of URL
    local features_dir="/home/nullsetbuilds/NullSetBuilds-Workspace/projects/spec-kit/.specify/features"
    
    if [ ! -d "$features_dir" ]; then
        log_warn "Features directory not found at $features_dir"
        return 1
    fi
    
    log_info "Scanning for feature files in $features_dir..."
    
    # Find all markdown files in the features directory
    local feature_files=()
    while IFS= read -r -d $'\0' file; do
        feature_files+=("$file")
    done < <(find "$features_dir" -type f -name "*.md" -print0)
    
    if [ ${#feature_files[@]} -eq 0 ]; then
        log_warn "No feature files found in $features_dir"
        return 0
    fi
    
    log_info "Found ${#feature_files[@]} feature files to process"
    
    # Process each feature file
    for feature_file in "${feature_files[@]}"; do
        log_info "Processing feature file: $feature_file"
        
        # Extract feature title from filename or first heading
        local feature_title=$(basename "$feature_file" .md)
        
        # Read the feature file content
        local content=$(<"$feature_file")
        
        # Extract tasks (lines starting with - [ ] or - [x])
        local tasks=()
        while IFS= read -r line; do
            if [[ "$line" =~ ^-\ \[[\ x]\]\ (.+)$ ]]; then
                tasks+=("${BASH_REMATCH[1]}")
            fi
        done <<< "$content"
        
        if [ ${#tasks[@]} -gt 0 ]; then
            log_info "Found ${#tasks[@]} tasks in $feature_title"
            
            # Add tasks to the project board
            for task in "${tasks[@]}"; do
                log_info "Adding task: $task"
                
                # Create an issue for the task
                local issue_result=$(gh issue create --title "$task" --body "Task from feature: $feature_title" --json id,number,url 2>/dev/null)
                
                if [ $? -ne 0 ] || [ -z "$issue_result" ]; then
                    log_warn "Failed to create issue for task: $task"
                    continue
                fi
                
                # Extract issue details
                local issue_id=$(echo "$issue_result" | jq -r '.id')
                local issue_number=$(echo "$issue_result" | jq -r '.number')
                local issue_url=$(echo "$issue_result" | jq -r '.url')
                
                if [ -n "$issue_id" ]; then
                    # Add issue to project board using GraphQL
                    local add_to_project_mutation
                    read -r -d '' add_to_project_mutation <<- GQL || true
                    mutation {
                      addProjectV2ItemById(
                        input: {
                          projectId: "$project_id"
                          contentId: "$issue_id"
                        }
                      ) {
                        item {
                          id
                        }
                      }
                    }
GQL
                    
                    gh api graphql -f query="$add_to_project_mutation" >/dev/null 2>&1 || \
                        log_warn "Failed to add issue #$issue_number to project board"
                fi
                
                log_info "Added task: $task (Issue #$issue_number)"
            done
        else
            log_info "No tasks found in $feature_title"
        fi
    done
    
    return 0
}

# Create a new project board using GitHub Projects (v2) API
create_board() {
    local board_name="${1:-Project Board}"
    local template="${2:-kanban}"
    local scope="${3:-auto}"  # 'user', 'org', or 'auto'
    local org_name="${4:-}"   # Organization name if scope is 'org'
    
    log_info "Creating '$board_name' with $template template using GitHub Projects (v2) API..."
    
    # Get repository information
    local repo_owner=""
    local repo_name=""
    local is_org_repo=false
    
    local repo_info
    repo_info=$(gh repo view --json nameWithOwner,name,owner,isInOrganization 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$repo_info" ]; then
        repo_name=$(echo "$repo_info" | jq -r '.name')
        local owner_info=$(echo "$repo_info" | jq -r '.owner')
        repo_owner=$(echo "$owner_info" | jq -r '.login')
        is_org_repo=$(echo "$repo_info" | jq -r '.isInOrganization // false')
    else
        log_warn "Could not determine repository information. Project will be created without repository linking."
    fi
    
    # Determine scope if auto
    if [ "$scope" = "auto" ]; then
        if [ "$is_org_repo" = "true" ]; then
            scope="org"
            if [ -z "$org_name" ] && [ -n "$repo_owner" ]; then
                org_name="$repo_owner"
            fi
        else
            scope="user"
        fi
    fi
    
    # Set owner based on scope
    local owner=""
    local owner_id=""
    
    # First, get the owner's Node ID
    local owner_query
    if [ "$scope" = "org" ] && [ -n "$org_name" ]; then
        # Get organization ID
        owner="$org_name"
        log_info "Getting organization ID for: $owner"
        owner_query="query { organization(login: \"$owner\") { id } }"
    else
        # Default to user project
        if [ -z "$repo_owner" ]; then
            repo_owner=$(gh api user --jq '.login' 2>/dev/null || echo "")
        fi
        owner="$repo_owner"
        scope="user"
        log_info "Getting user ID for: $owner"
        owner_query="query { user(login: \"$owner\") { id } }"
    fi
    
    if [ -z "$owner" ]; then
        log_error "Could not determine project owner. Please specify an organization or ensure you're authenticated."
        return 1
    fi
    
    # Get the owner's Node ID
    local owner_info
    if ! owner_info=$(gh api graphql -f query="$owner_query" 2>/dev/null); then
        log_error "Failed to get owner information. Please check your authentication and try again."
        return 1
    fi
    
    if [ "$scope" = "org" ]; then
        owner_id=$(echo "$owner_info" | jq -r '.data.organization.id // empty')
    else
        owner_id=$(echo "$owner_info" | jq -r '.data.user.id // empty')
    fi
    
    if [ -z "$owner_id" ]; then
        log_error "Could not determine owner ID. Response: $owner_info"
        return 1
    fi
    
    log_info "Using owner ID: $owner_id ($owner)"
    
    # Create project using REST API
    log_info "Creating project: $board_name"
    
    # Create a temporary file for error output
    local error_file
    error_file=$(mktemp)
    
    # For the new Projects API (v2), we need to use GraphQL
    local query
    if [ "$scope" = "org" ] && [ -n "$org_name" ]; then
        # Create organization project
        query=$(cat <<EOF
        mutation { createProjectV2( input: { ownerId: "$owner_id" title: "$board_name" } ) { projectV2 { id number title url } } }
EOF
        )
    else
        # Create user project
        query=$(cat <<EOF
        mutation { createProjectV2( input: { ownerId: "$owner_id" title: "$board_name" } ) { projectV2 { id number title url } } }
EOF
        )
    fi
    
    log_info "Creating project using Projects API v2..."
    
    # Create the project using GraphQL
    local project
    project=$(gh api graphql -f query="$query" 2>"$error_file")
    local exit_code=$?
    
    # Always capture the error message for logging
    local error_message
    error_message=$(<"$error_file" 2>/dev/null || echo "No error message captured")
    
    # Debug output
    log_info "Exit code: $exit_code"
    log_info "Error output: $error_message"
    
    # Check for errors
    if [ $exit_code -ne 0 ] || [ -z "$project" ]; then
        log_error "=== PROJECT CREATION FAILED ==="
        log_error "Exit code: $exit_code"
        log_error "Error message: $error_message"
        log_error "API Endpoint: $api_endpoint"
        log_error "Scope: $scope"
        log_error "Organization: ${org_name:-Not specified}"
        log_error "=============================="
        return 1
    fi
    
    log_info "Project created successfully"
    
    # Clean up temp file if it exists
    rm -f "$error_file"
    
    # Extract project details from GraphQL response
    local project_id
    project_id=$(echo "$project" | jq -r '.data.createProjectV2.projectV2.id // empty')
    local project_url
    project_url=$(echo "$project" | jq -r '.data.createProjectV2.projectV2.url // empty')
    local project_number
    project_number=$(echo "$project" | jq -r '.data.createProjectV2.projectV2.number // empty')
    
    if [ -z "$project_id" ] || [ -z "$project_url" ]; then
        log_error "Failed to parse project information from GitHub API response"
        log_error "Response: $project"
        return 1
    fi
    
    # Add repository to project if in a repository
    if [ -n "$repo_owner" ] && [ -n "$repo_name" ] && [ -n "$project_id" ]; then
        log_info "Linking repository $repo_owner/$repo_name to project..."
        
        # First, get the repository ID
        local repo_query
        repo_query=$(cat <<EOF
        query {
          repository(owner: "$repo_owner", name: "$repo_name") {
            id
          }
        }
EOF
        )
        
        local repo_info
        repo_info=$(gh api graphql -f query="$repo_query" 2>/dev/null)
        local repo_id
        repo_id=$(echo "$repo_info" | jq -r '.data.repository.id // empty')
        
        if [ -n "$repo_id" ]; then
            # Link repository to project
            local link_mutation
            link_mutation=$(cat <<EOF
            mutation {
              linkProjectV2ToRepository(
                input: {
                  projectId: "$project_id"
                  repositoryId: "$repo_id"
                }
              ) {
                clientMutationId
              }
            }
EOF
            )
            
            if ! gh api graphql -f query="$link_mutation" 2>/dev/null; then
                log_warn "Failed to link repository to project. You may need to link it manually."
                log_warn "Visit: $project_url to link the repository through the web interface"
            else
                log_info "✅ Successfully linked project to repository: $repo_owner/$repo_name"
            fi
        else
            log_warn "Could not find repository ID for $repo_owner/$repo_name. Skipping repository linking."
        fi
    fi
    
    # Set up project fields (replacing columns in Projects v2)
    log_info "Setting up project fields..."
    
    # First, get the default status field ID
    local fields_query
    fields_query=$(cat <<EOF
    query {
      node(id: "$project_id") {
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
EOF
    )
    
    local fields_info
    fields_info=$(gh api graphql -f query="$fields_query" 2>/dev/null)
    
    # Check if we have a status field (similar to columns in Projects v1)
    local status_field_id
    status_field_id=$(echo "$fields_info" | jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .id // empty')
    
    # Define status options based on template
    local status_options=()
    case "$template" in
        kanban)
            status_options=("To Do" "In Progress" "Done")
            ;;
        bug-triage)
            status_options=("Triage" "Needs Triage" "High Priority" "Low Priority" "Closed")
            ;;
        *)
            status_options=("To Do" "In Progress" "Done")
            ;;
    esac
    
    if [ -z "$status_field_id" ]; then
        # Create a new status field if it doesn't exist
        log_info "Creating status field with options..."
        
        # First, create the single select field
        local create_field_mutation
        create_field_mutation=$(cat <<EOF
        mutation {
          createProjectV2Field(
            input: {
              projectId: "$project_id"
              dataType: SINGLE_SELECT
              name: "Status"
              singleSelectOptions: [
                $(printf '{"name": "%s"},' "${status_options[@]}" | sed 's/,$//')
              ]
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
EOF
        )
        
        if ! gh api graphql -f query="$create_field_mutation" 2>/dev/null; then
            log_warn "Failed to create status field. You may need to set it up manually."
        else
            log_info "✅ Created status field with options: ${status_options[*]}"
        fi
    else
        log_info "Status field already exists. Skipping creation."
    fi
    
    log_info "✅ Project board created successfully: $project_url"
    # Return both URL and ID as JSON
    echo "{\"url\":\"$project_url\",\"id\":\"$project_id\"}"
    return 0
}

# Show help
show_help() {
    echo "GitHub Project Board Manager"
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  add-board         Create a new project board (default)"
    echo "  import-tasks      Import tasks from .specify/features directory"
    echo ""
    echo "Options:"
    echo "  -n, --name NAME       Name of the project board (default: Project Board)"
    echo "  -t, --template TPL    Template to use (kanban, basic, bug-triage) (default: kanban)"
    echo "  -s, --scope SCOPE     Project scope: 'user' or 'org' (default: auto-detect)"
    echo "  -o, --org ORG         Organization name (required if scope is 'org')"
    echo "  -y, --yes             Skip all confirmation prompts"
    echo "      --import-tasks    Import tasks from .specify/features directory into a new project board"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add-board --name \"My Project\" --template kanban"
    echo "  $0 --org myorg --name \"Team Project\" --scope org"
    echo "  $0 --import-tasks --name \"Feature Tasks\"  # Import tasks from .specify/features into a new project board"

}

# Main function
main() {
    check_requirements >/dev/null 2>&1 || {
        # If check_requirements fails, run it again to show errors
        check_requirements
        exit 1
    }
    check_auth >/dev/null 2>&1 || {
        check_auth
        exit 1
    }
    get_repo_info >/dev/null 2>&1 || {
        get_repo_info
        exit 1
    }
    
    # Default values
    local action="add-board"
    local board_name="Project Board"
    local template="kanban"
    local scope="auto"
    local org_name=""
    local skip_prompts=false
    local import_tasks=false
    
    # Default to silent mode
    local VERBOSE=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE="1"
                shift
                ;;
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
            --import-tasks)
                import_tasks=true
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
    if [ "$action" = "add-board" ] || [ "$action" = "import-tasks" ]; then
        local project_result
        project_result=$(create_board "$board_name" "$template" "$scope" "$org_name")
        
        if [ $? -ne 0 ]; then
            log_error "Failed to create project board"
            exit 1
        fi
        
        # Extract project URL and ID from the JSON response
        local project_url
        project_url=$(echo "$project_result" | jq -r '.url' 2>/dev/null)
        local project_id
        project_id=$(echo "$project_result" | jq -r '.id' 2>/dev/null)
        
        if [ -z "$project_url" ] || [ -z "$project_id" ]; then
            log_error "Failed to parse project information"
            exit 1
        fi
        
        echo -e "\n${GREEN}✅ Project created successfully!${NC}"
        echo -e "Project URL: ${BLUE}$project_url${NC}"
        
        # Check if we should import tasks (either via --import-tasks flag or import-tasks action)
        if [ "$import_tasks" = true ] || [ "$action" = "import-tasks" ]; then
            log_info "Importing tasks from .specify/features directory..."
            import_tasks_from_features "$project_id"
        fi
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
    [ -n "$VERBOSE" ] && echo -e "${GREEN}[INFO]${NC} $1"
    return 0
}

log_warn() {
    if [ -n "$VERBOSE" ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    else
        echo -e -n "${YELLOW}[WARNING]${NC} $1" >&2
    fi
    return 0
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

Usage: $0 [OPTIONS]

This command creates a GitHub project board for the current repository.

If no options are provided, it will create a kanban board with default settings.

To import tasks from .specify/features, use the --import-tasks flag.

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
    main() {
    # Set default values
    local BOARD_NAME="Project Board"
    local TEMPLATE="kanban"
    local IMPORT_TASKS=false
    local project_url
    
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

    if [ "$IMPORT_TASKS" = true ]; then
        # Get repository info for project creation
        get_repo_info
        
        # Set default values if not provided
        local SCOPE=${SCOPE:-'repo'}
        local ORG_NAME=${ORG_NAME:-''}
        
        # Create the project board first
        log_info "Creating project board for task import..."
        project_url=$(create_board "$BOARD_NAME" "$TEMPLATE" "$SCOPE" "$ORG_NAME")
        
        if [ -z "$project_url" ]; then
            log_error "Failed to create project board for task import"
            exit 1
        fi
        
        # Import tasks from features
        import_tasks_from_features "$project_url"
        
        # Only output the project URL in non-verbose mode
        [ -z "$VERBOSE" ] && echo "$project_url" || log_info "Task import completed successfully! Project Board: $project_url"
        exit 0
    else
        # Set default values if not provided
        local SCOPE=${SCOPE:-'repo'}
        local ORG_NAME=${ORG_NAME:-''}
        project_url=$(create_board "$BOARD_NAME" "$TEMPLATE" "$SCOPE" "$ORG_NAME")
        # Only output the project URL in non-verbose mode
        [ -z "$VERBOSE" ] && echo "$project_url" || log_info "Project Board created: $project_url"
    fi
}

# Run the script
main "$@"
