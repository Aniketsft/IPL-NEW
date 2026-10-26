---
trigger: always_on
description: Core workflow rules for multi-agent skill orchestration, memory-first execution order, file analysis second, proceed gates, and git branching.
---

# Global Workflow Rules

- Always use @multi-agent-tasks-orcehstrator to use the best skills for any prompt I am sending and always tell me what skills are being used.
- **Strict Execution Order for EVERY prompt**:
  1. **Memory First**: Always consult and read the code-based memory in `.agentMemory/` FIRST.
  2. **File Analysis Second**: Only after consulting memory may the agent inspect, grep, or analyze codebase files.
  3. **No Code Without Proceed**: Do not write any code until I say proceed.
  4. **Post-Proceed Memory Sync**: Immediately after completing each proceed execution, ALWAYS update the code-based memory in `.agentMemory/`.
- Only when i say commit to git then branch out and commit to git hub.
