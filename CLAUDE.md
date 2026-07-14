# Development Protocol

This repo uses a **multi-agent Claude Code harness**: a roster of specialized sub-agents plus a
mandated workflow that turns any request into small, reviewed, well-recorded increments. It is
project-agnostic — adopt it in your repo and fill in the placeholders (`<project-slug>`,
`<Project Name>`, `<working-branch>`). See `README.md` for one-time setup.

Always follow the backlog. Task state lives in the **Spec Server** (source of truth); `SPEC.md` is its
generated mirror — see the "Spec Server" section below.
Always use your agents when changing code: planner → spec-keeper → implementer → test-engineer →
reviewer → security → documentation → report-writer

Agent roster (`.claude/agents/`):
- **planner** — breaks large requests into an atomic, ordered implementation plan.
- **spec-keeper** — owns task state (drives the Spec Server API; `SPEC.md` is the mirror); breaks work into atomic tasks and tracks status.
- **implementer** — writes the code for exactly one task.
- **test-engineer** — writes/improves automated tests and runs the narrowest check.
- **reviewer** — checks correctness, style, maintainability, and scope.
- **security** — audits for vulnerabilities and leaked secrets.
- **documentation** — updates READMEs, API docs, and changelogs.
- **report-writer** — maintains the HTML report (before/after tab per change).
- **feature-runner** — runs ONE task end-to-end through the mandated chain, code-only and parallel-safe.
- **deep-diver** — investigates a hard "why is X broken / how should we build Y" question and produces a `<TOPIC>_DEEPDIVE.md` with evidence-backed root cause + a SPEC-ready task breakdown.
- **deploy-coordinator** — runs the project's single coordinated deploy wave (only if the project deploys).
- **ui-reviewer** — reviews UI/UX + user-facing COPY (accessibility/WCAG, CSP-clean web patterns, design-system consistency). Read-only; returns concrete fixes + terse rewrites.
- **architecture-reviewer** — reviews system architecture (component boundaries, data flow, failure modes, scalability, cost posture). Read-only; component map + P0/P1/P2 findings.
- **data-reviewer** — reviews the data layer (schema/migrations, integrity, parameterized-SQL safety, privacy/PII, retention, provenance). Read-only; findings with migration/file refs.
- **performance-reviewer** — reviews performance + cost-performance (latency hot paths, throughput/concurrency, query perf, cold starts, memory budgets, client perf, cost-per-unit-work). Read-only; prefers real measurement.
- **reliability-reviewer** — reviews reliability/resilience (failure modes, retry/idempotency, DLQ coverage, durability, state-machine integrity, graceful degradation, alarms, recovery). Read-only; findings ranked by blast radius.
- **aws-infra / aws-cost-optimizer / aws-teardown-enforcer** — OPTIONAL. Manage, cost-optimise, and tear down cloud (AWS) infrastructure. Delete these if your project has no cloud infra.
- **miro-board-sync** — OPTIONAL. Mirrors the Spec Server backlog onto a single Miro board. Delete if you don't use Miro.

> The last two bullets are **optional example agents**. Keep them only if they fit your project; each
> carries an "OPTIONAL agent" banner and placeholder values (`<infra-profile>`, `<board-id>`, …) for
> you to adapt.

**Review panel (full-system review):** for a periodic audit or before a large change, convene the panel —
architecture-reviewer + data-reviewer + performance-reviewer + reliability-reviewer + security +
test-engineer (+ ui-reviewer for web/UX, reviewer for code-level). Run them READ-ONLY in parallel,
each emitting findings to its own doc, then synthesize into a single prioritized P0/P1/P2 backlog. None
of the reviewers edit code.

For ANY code change the chain spec-keeper → implementer → reviewer → security → report-writer is
MANDATORY; skipping a step requires an explicit one-line justification in `AGENT_LOG.md`.
For any change touching the web UI or user-facing COPY, ALSO invoke **ui-reviewer** (after implementer,
alongside reviewer/security): it audits UI/UX, accessibility, CSP-cleanliness, and copy quality, and
returns concrete fixes + terse rewrites.

## Model selection — ALWAYS pass a `model` when spawning a sub-agent

Do NOT let sub-agents silently inherit the session model — choose per task and pass `model` explicitly:
- **`sonnet`** — mechanical, well-scoped, pattern-driven, or writing-heavy work: doc writing, test
  authoring, single-file / mechanical implementations, SPEC/status bookkeeping (spec-keeper), report
  tabs, repo-hygiene sweeps, config/hash/lockfile edits, UI/copy review. **Default to Sonnet when a
  task is routine or you're unsure on a cheap one.**
- **`opus`** — judgment, design, investigation, or safety-/security-critical work: architecture &
  root-cause deep-dives, new system/pipeline design, security changes and the security/reviewer gates,
  production deploys (deploy-coordinator), and anything where a wrong call is expensive.

Agent-definition frontmatter encodes the common default (implementer / test-engineer / documentation /
spec-keeper / report-writer / miro-board-sync / ui-reviewer / planner → sonnet; reviewer / security /
deep-diver / deploy-coordinator / aws-* / the review panel → opus). But **`feature-runner` is the
volume driver and is single-model (opus)** — so when you spawn one, OVERRIDE per task: pass
`model: "sonnet"` for a mechanical feature and `model: "opus"` only for a design-/security-heavy one.
Reserve Opus for where it pays off.

## Spec Server task notes are the work JOURNAL (drives the report)

Every task accumulates an append-only NOTE journal via the Spec Server notes API. These notes are the
SOURCE the HTML report is built from — report-writer reads `GET .../tasks/<id>/notes` and assembles
each report tab from the journal; do not hand-narrate the report.

**Four `kind=` types (every note body is prefixed `kind=<type>;` — machine-parseable):**
- `kind=request` — the ask. The ORCHESTRATOR (`author=main`) posts the user's request that spawned the task, and the brief it hands to each agent.
- `kind=report` — what was done. EVERY agent posts one on completion: approach, files changed, findings/evidence — concise.
- `kind=response` — the verdict/decision. Reviewers / security post their PASS/FAIL/CHANGES verdict + key points. The ORCHESTRATOR (`main`) posts decisions made and what was reported back to the user.
- `kind=model` — per-agent model + token telemetry: `model=<exact-id>; tokens_in=<N>; tokens_out=<N>; tokens_total=<N>`. Every agent posts one. The git commit footer is a hardcoded string and does NOT reflect which sub-agent ran on which model — these notes are the auditable cost signal.

**`author`** = your agent slug (matches your frontmatter `name:` field) or `main` for the orchestrator.

**Epic-level notes too** (symmetric with task notes): `POST|GET /projects/<project-slug>/epics/<key>/notes`
for epic-scope journaling. The project feed `GET /projects/<project-slug>/notes` merges task + epic
notes (newest-first, each row tagged with `scope` = task|epic and its key), filterable by
`scope=task|epic|all`, `epic=<key>`, `author`, `since`.

Notes API:
```
curl -s -X POST http://localhost:8080/api/v1/projects/<project-slug>/tasks/<task-id>/notes \
  -H 'Content-Type: application/json' \
  -d '{"body":"kind=report; <text>","author":"<agent-slug>"}'
# GET the same URL lists a task's notes (oldest first); notes are append-only.
```

report-writer BUILDS/UPDATES each report tab by reading `GET .../tasks/<id>/notes`: the tab is
assembled from `kind=request` (what was asked), `kind=report` (what each agent did), `kind=response`
(verdicts/decisions), and `kind=model` telemetry — never from a free-form description.

## HTML report

Keep an HTML report at `report.html` up to date with a new tab (change description + before/after
detail) after every change. report-writer owns it and builds each tab from the task-note journal.

## Spec Server — task management (source of truth)

Task state for this repo lives in the local **Spec Server** (API `http://localhost:8080/api/v1`,
project slug **`<project-slug>`**). **Read the Spec Server's `INTEGRATION_GUIDE.md` before your first
task** (endpoint recipes are in its `AGENTS_API.md`). See `README.md` here for how to run it and create
the project.

Drive each atomic increment through the API instead of hand-editing `SPEC.md`:
- **Pick the next task** → `POST /projects/<project-slug>/tasks/claim-next {"agent":"<you>"}` — never
  scan-and-pick a `[ ]` box (two agents would collide); claim is atomic and collision-proof.
- **Mark a task done** → `POST /projects/<project-slug>/tasks/<id>/complete {"commit_sha":"…","test_summary":"…","proof_cmd":"…"}`.
- **Reserve a numbered resource** (a SQL migration, queue, etc.) → `POST /projects/<project-slug>/reservations {"namespace":"migration"}`
  — never choose a number by hand; the server allocates a unique, monotonic value so two agents never collide.
- **Your own specs** → `GET /projects/<project-slug>/tasks?owner=<you>`.

`SPEC.md` stays a **mirror**: refresh it any time with
`curl -s http://localhost:8080/api/v1/projects/<project-slug>/export > SPEC.md`. If the server is
unreachable, fall back to the `SPEC.md` checkbox workflow below — nothing is lost.

Work in atomic increments:
1. Read `SPEC.md` before changing code.
2. Claim exactly one task via the Spec Server — `POST .../projects/<project-slug>/tasks/claim-next {"agent":"<you>"}` (atomic, collision-proof; 204 = backlog empty). Only fall back to scanning `SPEC.md` for an unchecked `[ ]` box if the server is unreachable.
3. Restate the task in one sentence.
4. Make the smallest code change that completes only that task.
5. Run the narrowest relevant test/check.
6. Commit the changes with a very descriptive commit description and a short tldr, on the branch `<working-branch>`.
7. Mark the task done in the Spec Server — `POST .../projects/<project-slug>/tasks/<id>/complete {"commit_sha":"…","test_summary":"…","proof_cmd":"…"}`. Add any discovered follow-ups via `POST .../projects/<project-slug>/tasks {…}`. Then:
   - refresh the SPEC.md mirror: `curl -s http://localhost:8080/api/v1/projects/<project-slug>/export > SPEC.md`
   - **Post the journal notes** (see "Spec Server task notes are the work JOURNAL" above): at dispatch `main` posts `kind=request`; each agent posts `kind=report` on completion; reviewers/security post `kind=response`; every agent posts `kind=model` telemetry. Then report-writer refreshes the tab from `GET .../tasks/<id>/notes`.
   - (If the Spec Server is unreachable, fall back to hand-editing `SPEC.md`: mark `[x]`, move to the completed section, add follow-ups.)
8. Record decisions in `DECISIONS.md` if any.
9. Append an entry to `AGENT_LOG.md`.
10. Update `SESSION_REPORT.md`.
11. Update the HTML report with before/after detail under a new tab.
12. **Tidy-up & git hygiene (definition-of-done — a task is NOT complete until ALL of these hold):**
    - `git status --porcelain` is EMPTY (clean tree). Every file you created or changed — including files changed OUTSIDE the Edit tool (formatters, chmod, generators, installs, renames) — is either committed or covered by `.gitignore`. New files MUST be `git add`ed and committed, not left untracked.
    - No scratch left in the repo: temp/scratch goes under `/tmp` or an ignored `/scratch/` dir, never into tracked paths.
    - The SPEC task for this increment is FLIPPED to done by spec-keeper (do not merely "suggest" it — the state must actually change).
    - One logical commit for the task (descriptive message + tldr), on `<working-branch>`, footer `Co-Authored-By: Claude Opus 4.8`.
    - The mandated chain actually ran: for code changes, reviewer AND security AND report-writer were invoked (or it is explicitly recorded WHY one was skipped). A deferred `[SECURITY-REVIEW]` tag is NOT a substitute for running security before commit.
13. Stop and report: files changed · test result · `git status` is clean · next recommended task.

Do not batch unrelated tasks.
Do not refactor unless `SPEC.md` explicitly asks for it.
If the spec is wrong or incomplete, update `SPEC.md` first, then continue.
A task is not complete until all documentation is updated.

For tasks that require permission multiple times, always write a script and ask permission once.

## Parallel-agent coordination
- **Numbered resources are reserved, not chosen.** Reserve the next number ATOMICALLY via the Spec
  Server — `POST .../projects/<project-slug>/reservations {"namespace":"migration","reserved_by":"<you>"}`
  — which allocates a unique, monotonic number, so two agents never collide. Create the file only after
  the reservation returns.
- **Task state is coordinated by the Spec Server, not by file locks.** `claim-next` (each agent gets a
  distinct task via `FOR UPDATE SKIP LOCKED`), `reservations` (unique numbers), and owner/lease replace
  the old "one writer at a time" dance for TASK state; `SPEC.md` is a GENERATED MIRROR — never hand-edit
  it concurrently, regenerate it from the server (`/export`). For the remaining shared files
  (`DECISIONS.md`, `AGENT_LOG.md`, `SESSION_REPORT.md`, `report.html`), still only ONE agent at a time;
  prefer a new dated section over editing existing lines.

---

## OPTIONAL — cloud infrastructure, deploys, and ML evals

Everything below applies **only if your project uses it**. Delete the sections (and the matching
optional agents) that don't fit. The specific values are placeholders — replace them with your own.

### Evaluation as part of definition-of-done (only if the project ships a trained model)

If your project trains/ships a model, a **model change is not done until its evals have run and the
metrics are recorded** (e.g. in `results/EVAL_REPORT.md`, with per-run JSON/CSV under `results/<eval>/`).
Run training on the expensive/transient compute, publish the weights, TERMINATE that compute, then run
the evals on cheap local hardware — never let an idle GPU burn through an eval. Define what "the
recommended evals" means in your own eval-strategy doc.

### Cloud container/image builds — build in the cloud, not locally

Do NOT build-and-push container images from a laptop when the target architecture differs (e.g. an
arm64 Mac pushing an amd64 image is a slow QEMU cross-build plus a multi-GB push over a flaky link).
Build in the cloud (e.g. AWS CodeBuild) on native architecture and push to the registry from inside the
cloud. Prefer defining the build project in your IaC.

### Terraform / IaC guardrails

**All durable infra is code.** Define every durable resource in Terraform (or your IaC of choice); do
not create durable resources by hand in the console or ad-hoc CLI. If you change infra outside IaC,
you've created drift — fix the code to match before moving on.

**Credentials & blast radius.** Use a dedicated deploy principal per stack; confirm
`aws sts get-caller-identity` (or equivalent) shows the expected principal before applying. Never
mutate a stack with personal/SSO creds. Never touch a resource the project has explicitly marked
protected (`<protected-instance-id>` and the like). Cost is a top priority: never leave transient
compute running after a task.

**Plan before apply — always.** Never `terraform apply` without reading the plan first
(`plan -out=tfplan` → `apply tfplan`; `-target=...` for narrow changes). After any apply, the post-apply
plan MUST be clean ("No changes"). `fmt` and `validate` must pass before you commit IaC source.

**The two deploy gotchas that bite repeatedly.**
- **Untracked source hashes.** If a function's deployed-artifact hash isn't wired to the freshly-built
  artifact, `apply` does NOT update its code. After apply, compare the deployed hash against the local
  build for every function whose source changed and force-update any that drift.
- **Non-deterministic builds.** Rebuilds that restamp timestamps show perpetual hash "drift" in the
  plan. Reconcile to the real code state; don't chase the churn or commit a "fix" that's only the
  timestamp moving.

**State safety.** Never hand-edit state, never `state rm`/`import` as a shortcut, never commit
`*.tfstate*` / `.terraform/` (keep them gitignored; keep `.terraform.lock.hcl` tracked). `destroy`
requires explicit user consent. IAM least-privilege: scope every policy to specific ARNs/actions — no
`"*"` grants; new IAM grants require explicit user consent.

**Parallel-agent rule (state lock).** Only ONE `apply` runs at a time — concurrent applies fight over
the state lock. Code-only agents NEVER apply; they write IaC SOURCE and hand off to a single
coordinated deploy (the deploy-coordinator agent).
