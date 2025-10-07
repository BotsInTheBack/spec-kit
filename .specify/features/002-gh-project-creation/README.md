# GitHub Project Creation Feature

## Overview
This feature introduces a powerful command-line tool for automating GitHub project creation and configuration. It streamlines the process of setting up new repositories with best practices, including branch protection, project boards, and standard files.

## Features

### Core Functionality
- **Repository Creation**: Initialize new GitHub repositories with a single command
- **Cross-Platform Support**: Compatible with both bash (Linux/macOS) and PowerShell (Windows)
- **Project Board Setup**: Automatically creates project boards with default columns
- **Branch Protection**: Configures branch protection rules for main branches
- **Standard Files**: Generates essential files (README, LICENSE, .gitignore)

### Technical Highlights
- **GitHub CLI Integration**: Leverages `gh` for all GitHub operations
- **JSON Support**: Provides JSON output for programmatic use
- **Input Validation**: Ensures all inputs are valid before execution
- **Error Handling**: Comprehensive error handling for GitHub API and system operations

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
```bash
# Create a new repository with default settings
./scripts/bash/create-github-project.sh --name my-project

# Create a public repository in an organization
./scripts/bash/create-github-project.sh --name my-project --org myorg --public

# Create with custom description and team access
./scripts/bash/create-github-project.sh --name my-project -d "My awesome project" --team "@myorg/developers"
```

### PowerShell (Windows)
```powershell
# Create a new repository with default settings
.\scripts\powershell\create-github-project.ps1 -Name "my-project"
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--name`, `-n` | Project name (required) | Current directory name |
| `--org`, `-o` | GitHub organization | Current user |
| `--description`, `-d` | Project description | "" |
| `--private`, `-p` | Make repository private | true |
| `--public` | Make repository public | false |
| `--team` | Add team access (can be specified multiple times) | |
| `--json` | Output result as JSON | false |
| `--help`, `-h` | Show help message | |

## Implementation Details

### Project Structure
```
scripts/
  bash/
    create-github-project.sh    # Main bash implementation
  powershell/
    create-github-project.ps1   # PowerShell implementation
templates/
  commands/
    projectize.md              # Command documentation
```

### Key Components
1. **Project Initialization**: Sets up repository structure and configuration
2. **GitHub Integration**: Handles all GitHub API interactions
3. **Template System**: Manages project templates and file generation
4. **Error Handling**: Provides meaningful error messages and recovery options

## Testing

### Test Cases
- [x] Repository creation (public/private)
- [x] Organization repository creation
- [x] Branch protection rules
- [x] Project board creation
- [x] Cross-platform compatibility

To run tests:
```bash
# Run bash tests
./scripts/bash/run-tests.sh

# Run PowerShell tests
./scripts/powershell/run-tests.ps1
```

## Security Considerations
- Uses GitHub CLI for secure authentication
- Implements input validation to prevent injection attacks
- Handles sensitive data (tokens, credentials) securely
- Follows GitHub's security best practices

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
- More project templates
- Interactive setup wizard
- Support for additional VCS providers

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
