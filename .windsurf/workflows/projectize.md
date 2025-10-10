---
description: Interactive GitHub project board management with task import from .specify/features
scripts:
  sh: scripts/bash/project-board.sh
  ps: scripts/powershell/project-board.ps1
---

The `/projectize` command creates GitHub project boards with optional task import from .specify/features.

Usage: /projectize [project_name] [template] [scope] [org_name] [import_tasks]

Examples:
  /projectize "My Project" kanban user
  /projectize "Team Project" feature-dev org "myorg" true
