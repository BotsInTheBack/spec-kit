#!/usr/bin/env bash
#
# GitHub Project Creation Script (Bash)
# ===================================
#
# Bash version of the GitHub Project creation script for Unix/Linux compatibility.
# Part of the GitHub Spec Kit's /projectize slash command functionality.
#
# This script automates the creation of GitHub projects with best practices.
# It's designed to be called by the /projectize slash command.
#
# Features:
# - 🚀 One-command project initialization
# - 🔒 Automatic branch protection
# - 📋 Standard project files (README, LICENSE, .gitignore)
# - 🏗️ Project board setup
# - 🔄 CI/CD workflow configuration

set -euo pipefail

# Load common functions and variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
DEFAULT_BRANCH="main"
DEFAULT_LICENSE="MIT"
DEFAULT_PRIVACY="private"
DEFAULT_PROJECT_TEMPLATE="kanban"
AUTO_DETECT=true
FORCE=false
JSON_OUTPUT=false
PRIVATE=true

# GitHub API configuration
GITHUB_API="https://api.github.com"

# Project templates
declare -A PROJECT_TEMPLATES=(
    ["kanban"]="Kanban board with To Do, In Progress, Done columns"
    ["table"]="Table view with status, priority, and assignee fields"
)

# Common repository templates
declare -A REPO_TEMPLATES=(
    ["node"]="Node.js with GitHub Actions"
    ["python"]="Python with pytest and GitHub Actions"
    ["react"]="React application with Vite"
    ["nextjs"]="Next.js application"
    ["typescript"]="TypeScript project"
    ["go"]="Go module"
    ["rust"]="Rust project with Cargo"
    ["terraform"]="Terraform module"
    ["docker"]="Docker project"
)

# Show help message
show_help() {
    cat <<EOF
GitHub Project Creation Tool (Bash)
==================================

IMPORTANT: This script is designed to be used internally by the '/projectize' command
in the GitHub Spec Kit. Please use the '/projectize' command from your IDE's chat interface
for the best experience.

For end users, the recommended way to use this functionality is via the '/projectize' command:

  /projectize --name my-project --description "Project description"

Internal Documentation (for development purposes only):
----------------------------------------------------
This script automates the creation of GitHub projects with best practices,
including repository setup, project boards, and task tracking.

Internal Usage: $0 [options] [project-name]

Options:
  --name <name>            Project name (default: current directory name)
  --description <text>     Project description
  --private                Make repository private (default)
  --public                 Make repository public
  --org <org>              Organization name (default: current user)
  --repo-template <repo>   GitHub repo to use as template (owner/repo)
  --project-template <type> Project type (kanban/table, default: kanban)
  --feature-md <file>      Path to feature markdown file (default: .specify/features/current/feature.md)
  --license <license>      License type (MIT, Apache-2.0, etc.)
  --branch <name>          Default branch name (default: main)
  --team <team>            Grant access to a team (can be specified multiple times)
  --force                  Override auto-detection
  --no-auto-detect         Disable auto-detection
  --json                   Output in JSON format
  -h, --help               Show this help message

Project Templates:
  kanban                   Kanban board with To Do, In Progress, Done columns
  table                    Table view with status, priority, and assignee fields

Feature Markdown:
  The --feature-md option allows you to specify a markdown file containing
  tasks in checklist format. These tasks will be automatically added to your
  project board. Example:
    - [ ] Task 1
    - [ ] Task 2
    - [x] Completed task

Examples:
  # Create a new project with Kanban board and tasks from feature.md
  $0 --name my-project --project-template kanban --feature-md .specify/features/current/feature.md

  # Create a public project in an organization with a team
  $0 --name our-app --org myorg --public --team @myorg/developers

  # Auto-detect existing repo and create a project
  $0  # Must be run from within a git repository

  # Create a project from a repository template
  $0 --name api-service --repo-template org/template-repo

  # Output in JSON format for programmatic use
  $0 --name my-project --json

  # Show available templates
  $0 --help
EOF
}

# Parse command line arguments
parse_args() {
    local TEAMS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n) 
                PROJECT_NAME="$2"
                shift 2
                ;;
            --description|-d) 
                DESCRIPTION="$2"
                shift 2
                ;;
            --private) 
                PRIVATE=true
                shift
                ;;
            --public) 
                PRIVATE=false
                shift
                ;;
            --org|-o) 
                ORG="$2"
                shift 2
                ;;
            --repo-template|-t) 
                REPO_TEMPLATE="$2"
                shift 2
                ;;
            --project-template|-p) 
                PROJECT_TEMPLATE="$2"
                shift 2
                ;;
            --license|-l) 
                LICENSE="$2"
                shift 2
                ;;
            --branch|-b) 
                DEFAULT_BRANCH="$2"
                shift 2
                ;;
            --team) 
                TEAMS+=("$2")
                shift 2
                ;;
            --feature-md|-f) 
                FEATURE_MD="$2"
                shift 2
                ;;
            --force) 
                FORCE=true
                shift
                ;;
            --no-auto-detect) 
                AUTO_DETECT=false
                shift
                ;;
            --json) 
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help) 
                show_help
                exit 0
                ;;
            --) 
                shift
                break
                ;;
            -*) 
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
            *) 
                # If the argument doesn't start with --, treat it as the project name
                if [[ -z "${PROJECT_NAME:-}" ]]; then
                    PROJECT_NAME="$1"
                else
                    echo "Unexpected argument: $1" >&2
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Export teams to global variable if any were specified
    if [ ${#TEAMS[@]} -gt 0 ]; then
        TEAMS_STR=$(printf ",%s" "${TEAMS[@]}")
        TEAMS_STR=${TEAMS_STR:1}
        export TEAMS_STR
    fi
    
    # Set default feature markdown path if not specified
    if [[ -z "${FEATURE_MD:-}" ]]; then
        FEATURE_MD=".specify/features/current/feature.md"
    fi
    
    # Ensure project template is valid
    if [[ -n "${PROJECT_TEMPLATE:-}" && -z "${PROJECT_TEMPLATES[$PROJECT_TEMPLATE]:-}" ]]; then
        echo "Error: Invalid project template: $PROJECT_TEMPLATE" >&2
        list_templates
        exit 1
    fi
}

# List available templates
list_templates() {
    echo -e "\nAvailable repository templates:\n"
    for template in "${!REPO_TEMPLATES[@]}"; do
        printf "  %-15s %s\n" "$template" "${REPO_TEMPLATES[$template]}"
    done
    
    echo -e "\nAvailable project templates:\n"
    for template in "${!PROJECT_TEMPLATES[@]}"; do
        printf "  %-15s %s\n" "$template" "${PROJECT_TEMPLATES[$template]}"
    done
    echo ""
}

# Find repository root by searching for project markers
find_repo_root() {
    local dir="${1:-$PWD}"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" || -d "$dir/.specify" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# Detect existing git repository and get repository info
get_git_repository_info() {
    local repo_root=""
    local remote_url=""
    local repo_owner=""
    local repo_name=""
    local is_git_repo=false
    
    # Try to get git info
    if command -v git &> /dev/null; then
        if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
            remote_url=$(git -C "$repo_root" remote get-url origin 2>/dev/null || echo "")
            is_git_repo=true
        fi
    fi
    
    # If not in a git repo, try to find repository root by markers
    if [[ -z "$repo_root" ]]; then
        repo_root=$(find_repo_root)
        if [[ -n "$repo_root" ]]; then
            is_git_repo=false
        fi
    fi
    
    # Parse owner and repo from remote URL if available
    if [[ -n "$remote_url" && "$remote_url" =~ github.com[:/]([^/]+)/([^/]+?)(\.git)?$ ]]; then
        repo_owner=${BASH_REMATCH[1]}
        repo_name=${BASH_REMATCH[2]%.git}
    fi
    
    # Output as JSON for easier parsing
    cat <<EOF
{
  "root": "$repo_root",
  "remote_url": "$remote_url",
  "is_git_repo": $is_git_repo,
  "owner": "$repo_owner",
  "name": "$repo_name"
}
EOF
}

# Detect existing git repository (legacy function, kept for compatibility)
detect_git_repo() {
    local repo_info
    repo_info=$(get_git_repository_info)
    
    local is_git_repo
    is_git_repo=$(jq -r '.is_git_repo' <<< "$repo_info")
    
    if [[ "$is_git_repo" == "true" ]]; then
        local owner name
        owner=$(jq -r '.owner' <<< "$repo_info")
        name=$(jq -r '.name' <<< "$repo_info")
        
        if [[ -n "$owner" && -n "$name" ]]; then
            REPO_OWNER=$owner
            REPO_NAME=$name
            echo "Detected GitHub repository: $REPO_OWNER/$REPO_NAME"
            return 0
        fi
    fi
    
    return 1
}

# Create repository from template
create_repo_from_template() {
    local template_owner=$(echo "$REPO_TEMPLATE" | cut -d/ -f1)
    local template_repo=$(echo "$REPO_TEMPLATE" | cut -d/ -f2)
    
    if [ -z "$ORG" ]; then
        gh repo create "$PROJECT_NAME" --template "$REPO_TEMPLATE" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --clone
        cd "$PROJECT_NAME" || exit 1
    else
        gh repo create "$ORG/$PROJECT_NAME" --template "$REPO_TEMPLATE" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --clone
        cd "$PROJECT_NAME" || exit 1
    fi
}

# Initialize a new git repository
init_repo() {
    local repo_name="${1:-$PROJECT_NAME}"
    local branch_name="${2:-$DEFAULT_BRANCH}"
    local license_type="${3:-$LICENSE}"
    local repo_root="${4:-$PWD}"
    
    if [[ "$FORCE" != "true" && -d "$repo_root/.git" ]]; then
        echo "Git repository already initialized in $repo_root. Use --force to reinitialize."
        return 0
    fi
    
    echo "Initializing git repository in $repo_root..."
    
    # Create directory if it doesn't exist
    mkdir -p "$repo_root"
    
    # Initialize git repository
    (cd "$repo_root" && git init)
    
    # Set default branch name
    (cd "$repo_root" && git config --local init.defaultBranch "$branch_name")
    
    # Create README.md with comprehensive content
    cat > "$repo_root/README.md" <<EOF
# $repo_name

${DESCRIPTION:-}

## 🚀 Getting Started

### Prerequisites

- [Git](https://git-scm.com/) (v2.25.0 or later)
- [GitHub CLI](https://cli.github.com/) (v2.0.0 or later)
- [Node.js](https://nodejs.org/) (if using JavaScript/TypeScript)
- [Python](https://www.python.org/) (if using Python)

### 📦 Installation

\`\`\`bash
# Clone the repository
git clone https://github.com/${ORG:-username}/$repo_name.git
cd $repo_name

# Install dependencies (if applicable)
[ -f "package.json" ] && npm install
[ -f "requirements.txt" ] && pip install -r requirements.txt
\`\`\`

## 🛠️ Development

### Building the project

\`\`\`bash
# Build the project (if applicable)
[ -f "package.json" ] && npm run build
\`\`\`

### Running tests

\`\`\`bash
# Run tests (if applicable)
[ -f "package.json" ] && npm test
[ -f "pytest.ini" ] && pytest
\`\`\`

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) to get started.

## 📄 License

This project is licensed under the ${license_type} License - see the [LICENSE](LICENSE) file for details.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of notable changes.

## 📧 Contact

- GitHub: [@${ORG:-username}](https://github.com/${ORG:-username})
- Email: your.email@example.com

    
    # Create .gitignore if it doesn't exist
    if [[ ! -f "$repo_root/.gitignore" ]]; then
        echo "Creating .gitignore..."
        cat > "$repo_root/.gitignore" << 'EOF'
# General
.DS_Store
Thumbs.db
*.log
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Dependencies
node_modules/
__pycache__/
*.py[cod]
*$py.class
.python-version
.python-version.*
.pytest_cache/
.coverage
htmlcov/

# Build output
dist/
build/
*.egg-info/
*.egg

# Editor directories and files
.idea/
.vscode/
*.sublime-workspace
*.sublime-project

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
.venv
venv/
ENV/

# Build outputs
dist/
build/
*.egg-info/
*.egg
*.so
*.dll
*.dylib
*.pyc
*.pyd

# IDEs and editors
.idea/
.vscode/
*.swp
*.swo
*~
.project
.pydevproject
.settings/
*.sublime-workspace
*.sublime-project

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Testing
.coverage
htmlcov/
.pytest_cache/
.tox/

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Local development
.local/

# Project specific
.specify/
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
.terraform.tfstate.lock.info

# Optional npm cache directory
.npm

# Optional eslint cache
.eslintcache

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn Integrity file
.yarn-integrity

# dotenv environment variables file
.env
.env.test

# parcel-bundler cache (https://parceljs.org/)
.cache
.parcel-cache

# Next.js build output
.next
out

# Nuxt.js build / generate output
.nuxt
dist

# Gatsby files
.cache/
public

# vuepress build output
.vuepress/dist

# Serverless directories
.serverless/

# FuseBox cache
.fusebox/

# DynamoDB Local files
.dynamodb/

# TernJS port file
.tern-port

# Stores VSCode versions used for testing VSCode extensions
.vscode-test/

# yarn v2
.yarn/cache
.yarn/unplugged
.yarn/build-state.yml
.yarn/install-state.gz
.pnp.*

# Environment files
.env
.venv
env/
venv/

# IDE specific files
.vscode/
.idea/
*.swp
*.swo

# Logs
logs/
*.log

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
EOF
    fi
    
    # Create LICENSE if specified
    if [[ -n "$license_type" && ! -f LICENSE ]]; then
        case "$license_type" in
            MIT)
                cat > LICENSE << 'EOF'
MIT License

Copyright (c) $(date +%Y) ${ORG:-Your Name}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
                ;;
            *)
                # For other licenses, try to fetch from GitHub API
                if ! curl -s -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/licenses/${license_type}" | \
                    jq -r '.body' > LICENSE 2>/dev/null; then
                    echo "# ${license_type} License" > LICENSE
                    echo "# See https://choosealicense.com/licenses/ for more information" >> LICENSE
                fi
                ;;
        esac
    fi
    
    # Create initial commit
    git add .
    git commit -m "Initial commit"
    
    echo "✅ Repository initialized with $branch_name branch"
}

# Parse feature markdown and extract tasks
get_tasks_from_markdown() {
    local markdown_file="${1:-}"
    local tasks=()
    
    if [[ -z "$markdown_file" ]]; then
        echo "Error: No markdown file specified" >&2
        return 1
    fi
    
    if [[ ! -f "$markdown_file" ]]; then
        echo "Warning: Feature markdown file not found: $markdown_file" >&2
        return 0
    fi
    
    echo "Extracting tasks from: $markdown_file"
    
    # Extract tasks from markdown checklist items
    local in_code_block=false
    local line
    
    while IFS= read -r line; do
        # Skip code blocks
        if [[ "$line" =~ ^\`\`\` ]]; then
            in_code_block=$((1 - in_code_block))
            continue
        fi
        
        if [[ "$in_code_block" == "1" ]]; then
            continue
        fi
        
        # Match task items (- [ ] or * [ ])
        if [[ "$line" =~ ^[\*\-]\s*\[[\sxX]\](\s+.*) ]]; then
            local task_text="${BASH_REMATCH[1]}"
            # Remove leading/trailing whitespace
            task_text=$(echo "$task_text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Skip empty tasks
            if [[ -n "$task_text" ]]; then
                tasks+=("$task_text")
            fi
        fi
    done < "$markdown_file"
    
    # Output tasks as JSON array
    if [[ ${#tasks[@]} -gt 0 ]]; then
        printf '['
        printf '"%s"' "${tasks[0]}"
        for ((i=1; i<${#tasks[@]}; i++)); do
            printf ',"%s"' "${tasks[i]}"
        done
        printf ']\n'
        echo "Found ${#tasks[@]} tasks in $markdown_file" >&2
    else
        echo '[]'
        echo "No tasks found in $markdown_file" >&2
    fi
    
    return 0
}

# Alias for backward compatibility
parse_feature_markdown() {
    get_tasks_from_markdown "$@"
}

# Create GitHub project with tasks from feature markdown
create_github_project() {
    local project_name="${1:-$PROJECT_NAME Project}"
    local project_template="${2:-$DEFAULT_PROJECT_TEMPLATE}"
    local project_description="${3:-$DESCRIPTION}"
    local feature_md="${4:-$FEATURE_MD}"
    
    # Get repository information
    local repo_info
    repo_info=$(gh repo view --json nameWithOwner,owner 2>/dev/null || true)
    
    if [[ -z "$repo_info" ]]; then
        echo "Error: Not in a GitHub repository" >&2
        return 1
    fi
    
    local repo_full_name
    repo_full_name=$(jq -r '.nameWithOwner' <<< "$repo_info")
    local owner
    owner=$(jq -r '.owner.login' <<< "$repo_info")
    
    echo "Creating $project_template project: $project_name"
    
    # Create the project
    echo "Creating GitHub project..."
    
    local project_output
    case $project_template in
        kanban)
            project_output=$(gh project create "$project_name" \
                --format json \
                --owner "$owner" \
                --source "$repo_full_name" \
                --template "https://github.com/orgs/github/projects/1" 2>&1) || {
                echo "Error creating project: $project_output" >&2
                return 1
            }
            ;;
        table)
            project_output=$(gh project create "$project_name" \
                --format json \
                --owner "$owner" \
                --source "$repo_full_name" \
                --format table 2>&1) || {
                echo "Error creating project: $project_output" >&2
                return 1
            }
            ;;
        *)
            echo "Error: Unknown project template: $project_template" >&2
            return 1
            ;;
    esac
    
    # Extract project ID from output
    local project_id
    project_id=$(jq -r '.id' <<< "$project_output" 2>/dev/null || true)
    
    if [[ -z "$project_id" ]]; then
        echo "Error: Failed to create project" >&2
        echo "Output: $project_output" >&2
        return 1
    fi
    
    echo "✅ Project created with ID: $project_id"
    
    # Add tasks from feature markdown if specified
    if [[ -f "$feature_md" ]]; then
        echo "Adding tasks from feature markdown..."
        
        # Get tasks from markdown
        local tasks_json
        tasks_json=$(get_tasks_from_markdown "$feature_md")
        
        # Parse tasks from JSON array
        local tasks=()
        while IFS= read -r line; do
            tasks+=("$line")
        done < <(jq -r '.[]' <<< "$tasks_json" 2>/dev/null)
        
        # Create columns if needed (for kanban)
        local todo_column_id=""
        if [[ "$project_template" == "kanban" ]]; then
            echo "Setting up Kanban board columns..."
            
            # Try to get existing columns
            todo_column_id=$(gh project column list "$project_id" --json id,name --jq '.[] | select(.name == "To do") | .id' 2>/dev/null || true)
            
            # Create columns if they don't exist
            if [[ -z "$todo_column_id" ]]; then
                echo "Creating Kanban columns..."
                
                # Create standard Kanban columns
                for column in "To do" "In Progress" "Done"; do
                    echo "Creating column: $column"
                    gh project column create --project-id "$project_id" --name "$column" --format json >/dev/null || {
                        echo "Warning: Failed to create column: $column" >&2
                    }
                done
                
                # Get the To Do column ID
                todo_column_id=$(gh project column list "$project_id" --json id,name --jq '.[] | select(.name == "To do") | .id' 2>/dev/null || true)
            fi
        fi
        
        # Add tasks to the project
        if [[ ${#tasks[@]} -gt 0 ]]; then
            echo "Adding ${#tasks[@]} tasks to the project..."
            
            local success_count=0
            local fail_count=0
            
            for task in "${tasks[@]}"; do
                if [[ -n "$task" ]]; then
                    echo -n "  - Adding: $task"
                    
                    # Add to the To Do column if this is a Kanban board
                    if [[ -n "$todo_column_id" ]]; then
                        if gh project item-add "$todo_column_id" --title "$task" >/dev/null 2>&1; then
                            echo " "
                            ((success_count++))
                        else
                            echo "  (Failed to add to Kanban board)" >&2
                            ((fail_count++))
                        fi
                    else
                        if gh project item-create "$project_id" --title "$task" >/dev/null 2>&1; then
                            echo " "
                            ((success_count++))
                        else
                            echo "  (Failed to add to project)" >&2
                            ((fail_count++))
                        fi
                    fi
                    
                    # Add a small delay to avoid rate limiting
                    sleep 0.5
                fi
            done
            
            # Print summary
            if [[ $success_count -gt 0 ]]; then
                echo "  Successfully added $success_count tasks to the project"
            fi
            if [[ $fail_count -gt 0 ]]; then
                echo "  Failed to add $fail_count tasks to the project" >&2
            fi
        else
            echo "No tasks found to add to the project."
        fi
    fi
    
{{ ... }}
    # Output project information
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg id "$project_id" \
            --arg name "$project_name" \
            --arg template "$project_template" \
            --arg url "https://github.com/orgs/$owner/projects/$project_id" \
            '{
                "id": $id,
                "name": $name,
                "template": $template,
                "url": $url,
                "tasks_added": ('"${#tasks[@]}"' | tonumber)
            }'
    else
        echo "✅ Project created successfully!"
        echo "   URL: https://github.com/orgs/$owner/projects/$project_id"
    fi
    
    return 0
}

# Set up team access
setup_team_access() {
    local repo_full_name="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
    
    if [ -z "$repo_full_name" ]; then
        echo "Error: Not in a GitHub repository"
        return 1
    fi
    
    for team in "${TEAMS[@]}"; do
        echo "Adding team '$team' to repository"
        gh api -X PUT \
            -H "Accept: application/vnd.github.v3+json" \
            "/orgs/$(echo $repo_full_name | cut -d/ -f1)/teams/$team/repos/$repo_full_name" \
            -f "permission=push"
    done
}

# Set up GitHub repository
setup_github_repo() {
    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) is required. Please install it first."
        exit 1
    fi
    
    # Check if we're already in a git repo with GitHub remote
    if [ "$AUTO_DETECT" = true ] && detect_git_repo; then
        echo "Using existing repository: $REPO_OWNER/$REPO_NAME"
        PROJECT_NAME=$REPO_NAME
        [ -z "$ORG" ] && ORG=$REPO_OWNER
        return 0
    fi
    
    # Create new repository from template if specified
    if [ -n "${REPO_TEMPLATE:-}" ]; then
        create_repo_from_template
        return $?
    fi
    
    # Create new repository
    if [ -n "${ORG:-}" ]; then
        gh repo create "${ORG}/${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    else
        gh repo create "${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    fi
    
    # Set branch protection rules if not from template
    if [ -z "${REPO_TEMPLATE:-}" ]; then
        gh api -X PUT \
            "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/${DEFAULT_BRANCH}/protection" \
            --input - << EOF
        {
            "required_status_checks": {
                "strict": true,
                "checks": ["build"]
            },
            "enforce_admins": true,
            "required_pull_request_reviews": {
                "required_approving_review_count": 1
            },
            "restrictions": null
        }
EOF
    fi
    if [ -n "${ORG:-}" ]; then
        gh repo create "${ORG}/${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    else
        gh repo create "${PROJECT_NAME}" \
            --${PRIVACY:-$DEFAULT_PRIVACY} \
            --description "${DESCRIPTION:-}" \
            --source . \
            --remote upstream
    fi

    # Set branch protection rules (only if not using a template that might have its own rules)
    if [ -z "${TEMPLATE:-}" ] || [ "$TEMPLATE" = "none" ]; then
        gh api -X PUT \
            "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/${DEFAULT_BRANCH}/protection" \
            --input - << EOF
        {
            "required_status_checks": {
                "strict": true,
                "checks": ["build"]
            },
            "enforce_admins": true,
            "required_pull_request_reviews": {
                "required_approving_review_count": 1
            },
            "restrictions": null
        }
EOF
    fi

    # Create project board (skip if using a template that might create its own)
    if [ -z "${TEMPLATE:-}" ] || [ "$TEMPLATE" = "none" ]; then
        gh project create "${PROJECT_NAME} Project" \
            --format json \
            --owner "$(gh repo view --json owner -q .owner.login)" \
            --source "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
            --template "https://github.com/orgs/github/projects/1"
    fi
}

# Main function
main() {
    # Default values
    AUTO_DETECT=true
    FORCE=false
    JSON_OUTPUT=false
    PRIVATE=true
    
    parse_args "$@"
    
    # Set default project name to current directory name if not provided
    if [ -z "${PROJECT_NAME:-}" ]; then
        PROJECT_NAME=$(basename "$(pwd)")
    fi
    
    # Auto-detect repository if enabled
    if [ "$AUTO_DETECT" = true ]; then
        if detect_git_repo; then
            echo "Auto-detected repository: $REPO_OWNER/$REPO_NAME"
            PROJECT_NAME=$REPO_NAME
            [ -z "$ORG" ] && ORG=$REPO_OWNER
        fi
    fi
    
    # Initialize repository if not using a template
    if [ -z "${REPO_TEMPLATE:-}" ]; then
        init_repo
        
        # Set up GitHub repository if not in CI
        if [ -z "${CI:-}" ]; then
            setup_github_repo
        fi
    fi
    
    # Create GitHub project if not in CI
    if [ -z "${CI:-}" ]; then
        create_github_project
        
        # Set up team access if specified
        if [ ${#TEAMS[@]} -gt 0 ]; then
            setup_team_access
        fi
    fi
    
    # Output success message
    if [ "${JSON_OUTPUT}" = true ]; then
        repo_url=$(gh repo view --json url -q .url 2>/dev/null || echo "")
        echo '{"status": "success", "message": "Project initialized successfully", "url": "'$repo_url'"}'
    else
        echo "✅ Project '${PROJECT_NAME}' has been successfully initialized!"
        if [ -z "${CI:-}" ]; then
            repo_url=$(gh repo view --json url -q .url 2>/dev/null || echo "Not pushed to GitHub")
            echo "🌍 View your repository at: $repo_url"
        fi
    fi
}

# Run the script
main "$@"

# Files Created:
# - .github/workflows/ - CI/CD workflows
# - .github/ISSUE_TEMPLATE/ - Issue templates
# - .github/PULL_REQUEST_TEMPLATE/ - PR templates
# - .github/projects/ - Project configurations
# - .gitignore - Project ignores
# - README.md - Project documentation
# - LICENSE - Project license
# - .github/workflows/project-automation.yml - GitHub Actions workflow
# - .github/scripts/project-automator.js - Project automation logic
#
# Usage:
#   ./create-project.sh "My new project description"
#   ./create-project.sh --json "My new project description"
#

set -e

# Parse command line arguments
JSON_MODE=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --help|-h) echo "Usage: $0 [--json] <project_description>"; exit 0 ;;
        *) ARGS+=("$arg") ;;
    esac
done

PROJECT_DESCRIPTION="${ARGS[*]}"
if [ -z "$PROJECT_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] <project_description>" >&2
    exit 1
fi

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialised with --no-git.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within the repository." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

# Create a unique project identifier using timestamp and description slug
PROJECT_ID=$(echo "$PROJECT_DESCRIPTION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//')
PROJECT_ID="project-$(date +%Y%m%d%H%M%S)-${PROJECT_ID:0:20}"

# Create new git branch for this project (if git repository detected)
if [ "$HAS_GIT" = true ]; then
    git checkout -b "$PROJECT_ID"
else
    >&2 echo "[projectize] Warning: Git repository not detected; skipped branch creation for $PROJECT_ID"
fi

# Create project configuration file with user-defined settings
PROJECT_DIR=".github/projects"
mkdir -p "$PROJECT_DIR"
PROJECT_FILE="$PROJECT_DIR/$PROJECT_ID.yml"

# Enhanced interactive project configuration
echo "🔧 GitHub Project Creation Setup"
echo "================================="
echo ""
echo "Project Description: $PROJECT_DESCRIPTION"
echo ""

# Ask for project configuration with sensible defaults
read -p "Project Name (default: derived from description): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-$(echo "$PROJECT_DESCRIPTION" | head -c 50 | sed 's/ $//')}
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="New Project"
fi

read -p "Project Visibility (public/private) [public]: " PROJECT_VISIBILITY
PROJECT_VISIBILITY=${PROJECT_VISIBILITY:-public}

read -p "Template Repository (or leave empty for default): " TEMPLATE_REPO

read -p "Default columns (comma-separated) [Backlog,In Progress,In Review,Done]: " COLUMNS
COLUMNS=${COLUMNS:-"Backlog,In Progress,In Review,Done"}

# Advanced project configuration
read -p "Enable issue automation? (y/n) [y]: " ENABLE_ISSUE_AUTOMATION
ENABLE_ISSUE_AUTOMATION=${ENABLE_ISSUE_AUTOMATION:-y}

read -p "Enable PR automation? (y/n) [y]: " ENABLE_PR_AUTOMATION
ENABLE_PR_AUTOMATION=${ENABLE_PR_AUTOMATION:-y}

read -p "Auto-assign issues to project? (y/n) [y]: " AUTO_ASSIGN_ISSUES
AUTO_ASSIGN_ISSUES=${AUTO_ASSIGN_ISSUES:-y}

read -p "Default issue labels (comma-separated) [enhancement,bug,documentation]: " DEFAULT_LABELS
DEFAULT_LABELS=${DEFAULT_LABELS:-"enhancement,bug,documentation"}

# Create comprehensive project configuration YAML file
cat > "$PROJECT_FILE" << PROJECT_EOF
---
project_name: "$PROJECT_NAME"
project_description: "$PROJECT_DESCRIPTION"
project_visibility: "$PROJECT_VISIBILITY"
template_repository: "$TEMPLATE_REPO"
columns:
$(echo "$COLUMNS" | tr ',' '\n' | sed 's/^/- /')
automation_enabled: true
issue_automation: $(echo "$ENABLE_ISSUE_AUTOMATION" | tr '[:upper:]' '[:lower:]')
pr_automation: $(echo "$ENABLE_PR_AUTOMATION" | tr '[:upper:]' '[:lower:]')
auto_assign_issues: $(echo "$AUTO_ASSIGN_ISSUES" | tr '[:upper:]' '[:lower:]')
default_labels:
$(echo "$DEFAULT_LABELS" | tr ',' '\n' | sed 's/^/- /')
created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
created_by: "projectize-command"
PROJECT_EOF

# Create GitHub Actions workflow for project automation
WORKFLOW_FILE=".github/workflows/project-automation.yml"
if [ ! -f "$WORKFLOW_FILE" ] || [ ! -s "$WORKFLOW_FILE" ]; then
    cat > "$WORKFLOW_FILE" << 'WORKFLOW_EOF'
name: Project Automation
# Workflow to automatically manage GitHub Projects based on repository events
# Triggers on issues, pull requests, and project card events
# Sets up automated project management and status updates

on:
  issues:
    types: [opened, labeled, assigned]
  pull_request:
    types: [opened, closed, merged]
  project_card:
    types: [created, moved]

jobs:
  automate-project:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'

    - name: Install dependencies
      run: npm install @octokit/rest js-yaml

    - name: Run project automation
      run: node .github/scripts/project-automator.js
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
WORKFLOW_EOF
fi

# Create enhanced project automator script for handling GitHub API interactions
AUTOMATOR_SCRIPT=".github/scripts/project-automator.js"
mkdir -p ".github/scripts"
cat > "$AUTOMATOR_SCRIPT" << 'SCRIPT_EOF'
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN
});

async function main() {
  try {
    // Get project configurations from .github/projects/ directory
    const projectsDir = path.join(process.cwd(), '.github', 'projects');
    if (!fs.existsSync(projectsDir)) {
      console.log('No project configurations found');
      return;
    }

    const projectFiles = fs.readdirSync(projectsDir)
      .filter(file => file.endsWith('.yml'));

    for (const projectFile of projectFiles) {
      const projectConfig = path.join(projectsDir, projectFile);
      const config = yaml.load(
        fs.readFileSync(projectConfig, 'utf8')
      );

      await processProject(config);
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

async function processProject(config) {
  console.log(`Processing project: ${config.project_name}`);

  try {
    // Get repository information
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) {
      console.log('Could not determine repository information');
      return;
    }

    // Create or update GitHub Project
    const project = await ensureProjectExists(config, repoInfo);
    if (!project) {
      console.log('Failed to create or find project');
      return;
    }

    // Set up project columns
    await setupProjectColumns(project.id, config.columns);

    // Set up automation rules
    await setupAutomationRules(project.id, config);

    // Process existing issues and PRs
    await processExistingIssues(project.id, config);
    await processExistingPRs(project.id, config);

    console.log(`✅ Project "${config.project_name}" is ready!`);
    console.log(`   Project URL: ${project.url}`);
    console.log(`   Columns: ${config.columns.join(', ')}`);

  } catch (error) {
    console.error(`Error processing project ${config.project_name}:`, error);
  }
}

async function getRepositoryInfo() {
  try {
    // Get repository information from git
    const { execSync } = require('child_process');
    const remoteUrl = execSync('git config --get remote.origin.url', { encoding: 'utf8' }).trim();
    const urlMatch = remoteUrl.match(/github\.com[:/]([^/]+)\/([^/.]+)/);
    if (!urlMatch) return null;

    const [, owner, repo] = urlMatch;
    return { owner, repo };
  } catch (error) {
    console.error('Error getting repository info:', error);
    return null;
  }
}

async function ensureProjectExists(config, repoInfo) {
  try {
    // Check if project already exists
    const { data: projects } = await octokit.projects.listForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo
    });

    // Look for existing project with matching name
    let existingProject = projects.find(p => p.name === config.project_name);

    if (existingProject) {
      console.log(`Found existing project: ${existingProject.name}`);
      return existingProject;
    }

    // Create new project
    console.log(`Creating new project: ${config.project_name}`);
    const { data: newProject } = await octokit.projects.createForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      name: config.project_name,
      body: config.project_description
    });

    return newProject;
  } catch (error) {
    console.error('Error creating/finding project:', error);
    return null;
  }
}

async function setupProjectColumns(projectId, columns) {
  try {
    // Get existing columns
    const { data: existingColumns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    // Create default columns if they don't exist
    for (const columnName of columns) {
      const existingColumn = existingColumns.find(col => col.name === columnName);
      if (!existingColumn) {
        await octokit.projects.createColumn({
          project_id: projectId,
          name: columnName
        });
        console.log(`Created column: ${columnName}`);
      }
    }
  } catch (error) {
    console.error('Error setting up columns:', error);
  }
}

async function setupAutomationRules(projectId, config) {
  // This would set up GitHub's built-in automation rules
  // For now, we'll handle automation in the workflow
  console.log('Automation rules will be configured in the workflow');
}

async function processExistingIssues(projectId, config) {
  if (config.auto_assign_issues !== 'true') return;

  try {
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) return;

    // Get open issues
    const { data: issues } = await octokit.issues.listForRepo({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      state: 'open'
    });

    // Get project columns to find the first column (usually Backlog)
    const { data: columns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    if (columns.length === 0) return;

    const firstColumn = columns[0];

    // Add issues to project
    for (const issue of issues) {
      if (issue.pull_request) continue; // Skip PRs

      // Add issue to project
      await octokit.projects.createCard({
        column_id: firstColumn.id,
        note: `Issue #${issue.number}: ${issue.title}`
      });

      console.log(`Added issue #${issue.number} to project`);
    }
  } catch (error) {
    console.error('Error processing existing issues:', error);
  }
}

async function processExistingPRs(projectId, config) {
  if (config.pr_automation !== 'true') return;

  try {
    const repoInfo = await getRepositoryInfo();
    if (!repoInfo) return;

    // Get open PRs
    const { data: prs } = await octokit.pulls.list({
      owner: repoInfo.owner,
      repo: repoInfo.repo,
      state: 'open'
    });

    // Get project columns to find appropriate column
    const { data: columns } = await octokit.projects.listColumns({
      project_id: projectId
    });

    const inProgressColumn = columns.find(col => col.name === 'In Progress') || columns[0];

    // Add PRs to project
    for (const pr of prs) {
      await octokit.projects.createCard({
        column_id: inProgressColumn.id,
        note: `PR #${pr.number}: ${pr.title}`
      });

      console.log(`Added PR #${pr.number} to project`);
    }
  } catch (error) {
    console.error('Error processing existing PRs:', error);
  }
}

main();
SCRIPT_EOF

# Output results based on mode
if $JSON_MODE; then
    printf '{"BRANCH_NAME":"%s","PROJECT_FILE":"%s","PROJECT_ID":"%s"}\n' "$PROJECT_ID" "$PROJECT_FILE" "$PROJECT_ID"
else
    echo "✅ Project configuration created: $PROJECT_FILE"
    echo "✅ GitHub Actions workflow created: $WORKFLOW_FILE"
    echo "✅ Project automator script created: $AUTOMATOR_SCRIPT"
    echo ""
    echo "BRANCH_NAME: $PROJECT_ID"
    echo "PROJECT_FILE: $PROJECT_FILE"
    echo "PROJECT_ID: $PROJECT_ID"
    echo ""
    echo "Next steps:"
    echo "1. Review and customize the project configuration in $PROJECT_FILE"
    echo "2. The GitHub Actions workflow will automatically create and manage your GitHub Project"
    echo "3. Issues and PRs will be automatically added to the project"
    echo "4. Project cards will move automatically based on status changes"
fi
