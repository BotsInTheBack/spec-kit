# GitHub Project Creation Slash Command Template
---
description: Initialize GitHub Project creation with automated workflows and project setup.
scripts:
  sh: scripts/bash/create-project.sh --json "{ARGS}"
  ps: scripts/powershell/create-project.ps1 -Json "{ARGS}"
---

The user input to you can be provided directly by the agent or as a command argument - you **MUST** consider it before proceeding with the prompt (if not empty).

User input:

$ARGUMENTS

The text the user typed after `/projectize` in the triggering message **is** the project description or requirements. Assume you always have it available in this conversation even if `{ARGS}` appears literally below. Do not ask the user to repeat it unless they provided an empty command.

Given that project description, do this:

1. Run the script `{SCRIPT}` from repo root and parse its JSON output for BRANCH_NAME, PROJECT_FILE, and other metadata. All file paths must be absolute.
   **IMPORTANT** You must only ever run this script once. The JSON is provided in the terminal as output - always refer to it to get the actual content you're looking for.
2. The script will ask questions to gather GitHub project configuration details.
3. Create and configure the `.github/workflows/project-automation.yml` workflow file.
4. Set up GitHub Project with appropriate columns and automation rules.
5. Report completion with branch name, project configuration, and next steps.

Note: The script creates and checks out the new branch and initializes the project configuration before setup.
