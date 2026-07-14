# agent-harness

A drop-in **multi-agent Claude Code harness** for any repository. It gives Claude Code a roster of
specialized sub-agents and an opinionated, atomic-increment workflow so that every change is planned,
implemented, tested, reviewed, security-audited, documented, and recorded — instead of one big
free-form edit.

It is **project-agnostic**: clone it into your repo, replace a few placeholders, and go. Domain-specific
pieces (cloud infra, ML evals, a Miro board) are isolated as clearly-marked **optional** agents/sections
you keep or delete.

## What's in the box

```
CLAUDE.md                     # the development protocol Claude Code reads automatically
.claude/
  agents/                     # 20 sub-agent definitions (see roster below)
  settings.json               # hooks config (one-commit-per-turn)
  hooks/commit-on-stop.sh     # commits each turn's changes; guards against giant blobs
README.md                     # you are here
```

**Core agents** (keep these): `planner`, `spec-keeper`, `implementer`, `test-engineer`, `reviewer`,
`security`, `documentation`, `report-writer`, `feature-runner`, `deep-diver`, `deploy-coordinator`,
and the read-only review panel (`architecture-reviewer`, `data-reviewer`, `performance-reviewer`,
`reliability-reviewer`, `ui-reviewer`).

**Optional example agents** (delete if they don't fit your project): `aws-infra`, `aws-cost-optimizer`,
`aws-teardown-enforcer` (cloud/GPU infrastructure), `miro-board-sync` (publish task state to a Miro
board). Each starts with an "OPTIONAL agent" banner and uses placeholders you adapt.

## Adopt it in your repo

1. **Copy the harness in:**
   ```bash
   cp -r agent-harness/.claude your-repo/.claude
   cp agent-harness/CLAUDE.md   your-repo/CLAUDE.md
   ```
2. **Replace the placeholders** across `CLAUDE.md` and `.claude/agents/*.md`:
   | placeholder            | replace with                                             |
   | ---------------------- | -------------------------------------------------------- |
   | `<project-slug>`       | your Spec Server project slug (kebab-case)               |
   | `<Project Name>`       | your project's human-readable name                       |
   | `<working-branch>`     | the git branch work happens on (e.g. `main`)             |
   | `<infra-profile>`, `<board-id>`, `<account-id>`, `<region>`, `<protected-instance-id>` | only if you keep the optional cloud/Miro agents |

   A quick sweep to find anything left:
   ```bash
   grep -rn '<project-slug>\|<Project Name>\|<working-branch>' your-repo/.claude your-repo/CLAUDE.md
   ```
3. **Delete the optional agents you don't need** (`.claude/agents/aws-*.md`, `miro-board-sync.md`) and
   remove their bullets from `CLAUDE.md`'s roster.
4. **Decide your task backend** (below).
5. Open the repo in Claude Code — it reads `CLAUDE.md` automatically and the agents become available.

## Task backend: the Spec Server

The workflow's source of truth is the **Spec Server** — a small local service that stores task state,
hands out atomic task claims (`claim-next`), allocates unique numbered resources (`reservations`), and
stores the per-task note journal the HTML report is built from. `SPEC.md` in your repo is a **generated
mirror** of it.

- Run it locally (it expects `http://localhost:8080/api/v1`) and create a project with your
  `<project-slug>`. See the Spec Server's own `INTEGRATION_GUIDE.md` and `AGENTS_API.md` for setup and
  endpoint recipes.
- Refresh the mirror any time: `curl -s http://localhost:8080/api/v1/projects/<project-slug>/export > SPEC.md`.

**No server? Zero-setup fallback.** Every agent falls back to a plain checkboxed `SPEC.md`
(`[ ]` todo · `[~]` in progress · `[x]` done · `[-]` superseded). You lose atomic multi-agent
coordination but the single-agent workflow works out of the box.

## The workflow in one paragraph

For any code change, the orchestrator drives the mandated chain
**spec-keeper → implementer → test-engineer → reviewer → security → documentation → report-writer**,
one atomic task at a time, on `<working-branch>`. Reviewers and `security` are read-only gates; a task
isn't done until the tree is clean, the task is flipped to done in the backend, and the change is
recorded (`AGENT_LOG.md`, `SESSION_REPORT.md`, `DECISIONS.md`, and a `report.html` tab). The full
protocol — including model-selection guidance and the note-journal format — is in `CLAUDE.md`.

## The commit hook

`.claude/hooks/commit-on-stop.sh` runs on `Stop`/`SubagentStop` and makes **one commit per turn** (all
staged changes together), refusing to commit an untracked non-ignored file larger than 25 MB (a guard
against build artifacts / model weights / datasets leaking into history). Remove the `Stop` hooks from
`.claude/settings.json` if you'd rather commit manually.
