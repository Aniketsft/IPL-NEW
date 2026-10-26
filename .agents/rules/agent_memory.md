---
trigger: always_on
description: Mandatory rules to consult .agentMemory/ first before analyzing any codebase files, and update .agentMemory/ after every proceed execution.
---

# Agent Memory (Codebase Knowledge & Decisions)

This repository maintains a persistent, code-based memory bank in `.agentMemory/`.

## Mandatory Protocol & Execution Order:
1. **Step 1 — Code-Based Memory FIRST**:
   - For *every prompt*, Antigravity MUST read and consult `.agentMemory/` FIRST before doing anything else.
   - Ground all understanding in established architecture (`.agentMemory/architecture/`), patterns (`.agentMemory/patterns/`), past decisions (`.agentMemory/decisions/`), and active context (`.agentMemory/active_context/`).

2. **Step 2 — Codebase File Analysis SECOND**:
   - Only AFTER consulting `.agentMemory/` may Antigravity search, read, grep, or inspect codebase files.

3. **Step 3 — Propose Plan & Wait for Proceed**:
   - Present diagnosis, answers, or implementation plans clearly. Strictly DO NOT write any code until the user says `proceed`.

4. **Step 4 — Memory Update AFTER Every Proceed**:
   - Immediately after completing code changes or fixes upon user `proceed`, Antigravity MUST update `.agentMemory/` with:
     - New or modified database columns, models, or DTO contracts.
     - Solved bugs, root causes, and deadlock prevention rules.
     - Updated milestone states in `.agentMemory/active_context/current_milestone.md`.
