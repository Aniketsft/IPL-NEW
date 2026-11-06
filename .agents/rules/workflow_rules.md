---
trigger: always_on
description: Workspace fast-path execution rules complementing global workflow rules.
---

# Workspace Fast-Path Execution Rules

- **Skill Selection**: State active skills concisely at the top of each reply. Only call `read_file` on a `SKILL.md` when the task actively requires its specialized workflow (skip re-reading `SKILL.md` files on simple conversational or status prompts).
- **Silent Search Only**: Use `graphify` MCP (`query_graph`, `get_node`, `shortest_path`) and `read_file` exclusively for codebase navigation—never `grep_search` or shell search commands.
- **Proceed & Git Gates**: Ask before writing structural code changes (wait for `proceed`), and only branch/commit when explicitly instructed.

