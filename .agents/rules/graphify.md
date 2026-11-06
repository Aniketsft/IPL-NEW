---
trigger: always_on
description: Consult the graphify knowledge graph at graphify-out/ for codebase and architecture questions.
---

## graphify

This project has a graphify knowledge graph at `graphify-out/`.

Rules:
- Use `query_graph` (with `depth: 2`, `token_budget: 800` by default for fast responses; increase only for broad architectural traces), `shortest_path`, or `get_node` via MCP. For non-codebase chat questions, use `depth: 1`, `token_budget: 300` or `graph_stats` to keep latency minimal.
- Read `graphify-out/GRAPH_REPORT.md` only when `query_graph` / `shortest_path` / `get_node` do not surface enough context.
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost).
