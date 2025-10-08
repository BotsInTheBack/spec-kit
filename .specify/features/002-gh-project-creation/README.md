# GitHub Project Creation Feature

## Overview
This feature introduces a powerful command-line tool for automating GitHub project creation and configuration. It streamlines the process of setting up new repositories with best practices, including branch protection, project boards, and standard files. The tool intelligently handles both personal and organization projects with robust error handling and user-friendly prompts.

## Features

### Core Functionality
- **Repository Creation**: Initialize new GitHub repositories with a single command
- **Cross-Platform Support**: Compatible with both bash (Linux/macOS) and PowerShell (Windows)
- **Project Board Setup**: Automatically creates project boards with default columns
- **Organization Support**: Handles both personal and organization projects with intelligent fallback
- **Branch Protection**: Configures branch protection rules for main branches
- **Standard Files**: Generates essential files (README, LICENSE, .gitignore)
- **Interactive Prompts**: User-friendly prompts for project configuration
- **Error Recovery**: Graceful fallback from organization to personal projects on permission issues

### Technical Highlights
- **GitHub CLI Integration**: Leverages `gh` for all GitHub operations
- **JSON Support**: Provides JSON output for programmatic use
- **Input Validation**: Ensures all inputs are valid before execution
- **Error Handling**: Comprehensive error handling for GitHub API and system operations
- **Auto-Detection**: Automatically detects repository type (personal/organization)
- **Permission Handling**: Graceful degradation when organization permissions are insufficient
- **Cross-Platform**: Consistent behavior between bash and PowerShell implementations

## Prerequisites

### Required Tools
- [GitHub CLI (`gh`)](https://cli.github.com/)
- `jq` (for bash scripts)
- `curl` (for bash scripts)
- Bash 4+ (Linux/macOS) or PowerShell 7+ (Windows)

### Authentication
- GitHub CLI must be authenticated (`gh auth login`)
- Sufficient permissions for repository creation in the target organization/account

## Usage

### Basic Usage

#### Bash (Linux/macOS)
```bash
# Create a new personal project
./scripts/bash/github-project.sh add-board --name "My Project"

# Create a project in a specific organization
./scripts/bash/github-project.sh add-board --name "Org Project" --org myorg

# Auto-detect organization from current repository
./scripts/bash/github-project.sh add-board --name "Auto Project" --scope auto

# Non-interactive mode (for CI/CD)
./scripts/bash/github-project.sh add-board --name "CI Project" --org myorg --yes
```

#### PowerShell (Windows)
```powershell
# Create a new personal project
.\scripts\powershell\github-project.ps1 add-board -Name "My Project"

# Create a project in a specific organization
.\scripts\powershell\github-project.ps1 add-board -Name "Org Project" -OrgName myorg

# Auto-detect organization from current repository
.\scripts\powershell\github-project.ps1 add-board -Name "Auto Project" -Scope auto

# Non-interactive mode (for CI/CD)
.\scripts\powershell\github-project.ps1 add-board -Name "CI Project" -OrgName myorg -NonInteractive
```

## Command Line Options

### Common Options
| Option | Description | Default |
|--------|-------------|---------|
| `--name`, `-n` | Project name (required) | |
| `--template`, `-t` | Project template (basic, kanban, bug-triage) | kanban |
| `--scope`, `-s` | Project scope (user, org, auto) | auto |
| `--org`, `-o` | GitHub organization name | Auto-detected |
| `--yes`, `-y` | Skip confirmation prompts | false |
| `--help`, `-h` | Show help message | |

### Action-Specific Options
#### add-board
| Option | Description |
|--------|-------------|
| `--template`, `-t` | Board template to use |
| `--scope`, `-s` | Scope for the project (user/org/auto) |
| `--org`, `-o` | Organization name for org-scoped projects |
| `--yes`, `-y` | Skip confirmation prompts |

#### import-tasks
| Option | Description |
|--------|-------------|
| `--file`, `-f` | Path to tasks file |
| `--project`, `-p` | Target project ID or name |

## Implementation Details

### Project Structure
```
scripts/
  bash/
    github-project.sh           # Main bash implementation
  powershell/
    github-project.ps1          # PowerShell implementation
templates/
  commands/
    projectize.md              # Command documentation
```

### Key Features
- **Auto-Detection**: Automatically detects if the current repository is part of an organization
- **User-Friendly Prompts**: Interactive prompts for required information
- **Permission Handling**: Graceful fallback to personal projects when organization permissions are insufficient
- **Consistent Behavior**: Same functionality across bash and PowerShell
- **Error Recovery**: Comprehensive error handling with helpful messages

### Key Components
1. **Project Initialization**: Sets up repository structure and configuration
2. **GitHub Integration**: Handles all GitHub API interactions
3. **Template System**: Manages project templates and file generation
4. **Error Handling**: Provides meaningful error messages and recovery options
5. **Scope Management**: Handles both personal and organization projects
6. **User Interaction**: Manages prompts and confirmations
7. **Permission Handling**: Detects and handles permission issues gracefully

## Testing

### Test Cases
- [x] Personal project creation
- [x] Organization project creation
- [x] Auto-detection of repository type
- [x] Fallback to personal projects on permission issues
- [x] Interactive prompts and confirmations
- [x] Non-interactive mode for CI/CD
- [x] Cross-platform compatibility (bash/PowerShell)
- [x] Error handling and validation

To run tests:
```bash
# Run bash tests
./scripts/bash/run-tests.sh

# Run PowerShell tests
./scripts/powershell/run-tests.ps1
```

### Testing Organization Projects
To test organization project creation, ensure you have:
1. A GitHub organization where you have admin permissions
2. A personal access token with the `admin:org` scope
3. The GitHub CLI authenticated with the appropriate account

## Security Considerations
- Uses GitHub CLI for secure authentication
- Implements input validation to prevent injection attacks
- Handles sensitive data (tokens, credentials) securely
- Follows GitHub's security best practices
- Only requests necessary permissions (no excessive scopes)
- Provides clear feedback when permissions are insufficient
- Does not store credentials or tokens in logs

## Dependencies

### Runtime Dependencies
- GitHub CLI (`gh`)
- `jq` (for bash scripts)
- `curl` (for bash scripts)
- Bash 4+ or PowerShell 7+

### Development Dependencies
- Node.js 16+
- TypeScript
- Jest (for testing)
- ESLint (for code quality)

## Future Enhancements
- Support for custom issue templates
- Advanced workflow automation
- More project board templates
- Interactive setup wizard
- Support for additional VCS providers
- Team and collaborator management
- Project board column customization
- Integration with project milestones

## Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- Follow existing code style and patterns
- Include comments for complex logic
- Write tests for new features
- Update documentation as needed

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments
- GitHub CLI team for the amazing `gh` tool
- All contributors who helped test and improve this feature
