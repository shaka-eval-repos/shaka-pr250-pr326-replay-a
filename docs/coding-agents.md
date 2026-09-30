# Coding agents

Your coding agent supplies the model, permissions, and tools. Install Shaka once
and use it across your repositories.

| Coding agent | Start a task | Notes |
| --- | --- | --- |
| Codex | `$shaka` | Desktop app or CLI; the optional RCT skill needs desktop task tools |
| Claude Code | `/shaka` | Desktop app or CLI; Claude tower skills need desktop session tools |
| Cursor | `/shaka` | Start a new Agent chat after installation |
| OpenCode | `/shaka` | Use the installed skill in a session; an optional launcher is also available |
| Pi | Load the installed Shaka skill | Uses Pi's existing permissions; no separate Shaka launcher |

Use the [installation prompt](getting-started.md); the agent follows the
[installation reference](../skills/shaka/references/installation.md) for your environment.

To support another coding agent, [contribute](../CONTRIBUTING.md) installation
instructions, a demonstrated task, and known limitations. Keep environment-specific
code separate from the shared workflow.
