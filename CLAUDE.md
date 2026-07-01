# Development Protocol

Always follow the backlog. Task state is the **Spec Server** (source of truth); `SPEC.md` is its generated mirror — see the "Spec Server" section below.
Always use your agents when changing code: planner → spec-keeper → implementer → test-engineer → reviewer → security → documentation → report-writer

Agent roster (.claude/agents/):
- planner — breaks large requests into an atomic, ordered implementation plan.
- spec-keeper — owns task state (drives the Spec Server API; `SPEC.md` is the mirror); breaks work into atomic tasks and tracks status.
- implementer — writes the code for exactly one task.
- test-engineer — writes/improves automated tests and runs the narrowest check.
- reviewer — checks correctness, style, maintainability, and scope.
- security — audits for vulnerabilities and leaked secrets.
- documentation — updates READMEs, API docs, and changelogs.
- report-writer — maintains the HTML report (before/after tab per change).
- ui-reviewer — reviews UI/UX + user-facing COPY (accessibility/WCAG, CSP-clean web patterns, design-system consistency, interaction-state contrast) and writes crisp copy pitched at customers AND technical users. Read-only; returns concrete fixes + terse rewrites.
- architecture-reviewer — reviews system architecture (component boundaries, data flow, the processing planes, failure modes, scalability, cost posture). Read-only; component map + P0/P1/P2 findings + risks/opportunities.
- data-reviewer — reviews the data layer (schema/migrations, integrity, RDS Data API typeHint safety, the D5 privacy rule, retention, provenance, PII). Read-only; findings with migration/file refs.
- performance-reviewer — reviews performance + cost-performance (latency hot paths, throughput/concurrency, query perf, cold starts, memory budgets, client perf, $/clip). Read-only; prefers real measurement.
- reliability-reviewer — reviews reliability/resilience (failure modes, retry/idempotency, DLQ coverage, durability, state-machine integrity, graceful degradation, alarms, recovery). Read-only; findings ranked by blast radius.
- aws-infra / aws-cost-optimizer / aws-teardown-enforcer — manage, cost-optimise, and tear down AWS GPU infrastructure.

**Review panel (full-system review):** for a periodic audit or before a large change, convene the panel —
architecture-reviewer + data-reviewer + performance-reviewer + reliability-reviewer + security +
test-engineer (+ ui-reviewer for web/UX, aws-cost-optimizer for spend, reviewer for code-level). Run them
READ-ONLY in parallel, each emitting findings to its own doc, then synthesize into a single prioritized
P0/P1/P2 backlog. None of the reviewers edit code.

For ANY code change the chain spec-keeper → implementer → reviewer → security → report-writer is
MANDATORY; skipping a step requires an explicit one-line justification in AGENT_LOG.md.
For any change touching the web UI or user-facing COPY, ALSO invoke **ui-reviewer** (after implementer,
alongside reviewer/security): it audits UI/UX, accessibility, CSP-cleanliness, and copy quality for this
platform's customer + technical audience, and returns concrete fixes + terse, no-slop rewrites.

## Model selection — ALWAYS pass a `model` when spawning a sub-agent

Do NOT let sub-agents silently inherit the session model — choose per task and pass `model` explicitly:
- **`sonnet` (Sonnet 4.6)** — mechanical, well-scoped, pattern-driven, or writing-heavy work: doc writing,
  test authoring, single-file / mechanical implementations, SPEC/status bookkeeping (spec-keeper), the Miro
  sync, report tabs, repo-hygiene sweeps, config/hash/lockfile edits, UI/copy review. **Default to Sonnet
  when a task is routine or you're unsure on a cheap one.**
- **`opus` (Opus 4.8)** — judgment, design, investigation, or safety-/security-critical work: architecture
  & root-cause deep-dives, new infra/pipeline design, IAM/security changes and the security/reviewer gates,
  production deploys (deploy-coordinator), and anything where a wrong call is expensive.

Agent-definition frontmatter encodes the common default (implementer/test-engineer/documentation/
spec-keeper/report-writer/miro-board-sync/ui-reviewer/planner → sonnet; reviewer/security/deep-diver/
deploy-coordinator/aws-* /the review panel → opus). But **`feature-runner` is the volume driver and is
single-model (opus)** — so when you spawn one, OVERRIDE per task: pass `model: "sonnet"` for a mechanical
feature and `model: "opus"` only for a design-/security-heavy one. Reserve Opus for where it pays off.

## Spec Server task notes are the work JOURNAL (drives the report)

Every task accumulates an append-only NOTE journal via the Spec Server notes API. These notes are the
SOURCE the HTML report is built from — report-writer reads `GET .../tasks/<id>/notes` and
assembles each report tab from the journal; do not hand-narrate the report.

**Four `kind=` types (every note body is prefixed `kind=<type>;` — machine-parseable):**
- `kind=request` — the ask. The ORCHESTRATOR (`author=main`) posts the user's request that spawned
  the task, and the brief it hands to each agent.
- `kind=report` — what was done. EVERY agent posts one on completion: approach, files changed,
  findings/evidence — concise.
- `kind=response` — the verdict/decision. Reviewers / security / data-reviewer / ui-reviewer /
  architecture-reviewer / performance-reviewer / reliability-reviewer post their PASS/FAIL/CHANGES
  verdict + key points. The ORCHESTRATOR (`main`) posts decisions made and what was reported back to
  the user.
- `kind=model` — per-agent model + token telemetry: `model=<exact-id>; tokens_in=<N>; tokens_out=<N>;
  tokens_total=<N>`. Every agent posts one. The git commit footer is a hardcoded string and does NOT
  reflect which sub-agent ran on which model — these notes are the auditable cost signal.

**`author`** = your agent slug (matches your frontmatter `name:` field) or `main` for the orchestrator.

**Epic-level notes too** (symmetric with task notes): `POST|GET /projects/<project-name>/epics/<key>/notes`
for epic-scope journaling — `main` posts epic-spanning `kind=request`/`response`/summary notes here. The
project feed `GET /projects/<project-name>/notes` merges task + epic notes (newest-first, each row tagged with
`scope` = task|epic and its key), filterable by `scope=task|epic|all`, `epic=<key>`, `author`, `since`.
report-writer builds epic-level report sections from the epic notes + this feed; per-task work still
groups by `epic_key`.

Notes API:
```
curl -s -X POST http://localhost:8080/api/v1/projects/<project-name>/tasks/<task-id>/notes \
  -H 'Content-Type: application/json' \
  -d '{"body":"kind=report; <text>","author":"<agent-slug>"}'
# GET the same URL lists a task's notes (oldest first); notes are append-only.
```

report-writer BUILDS/UPDATES each report tab by reading `GET .../tasks/<id>/notes`: the tab is
assembled from `kind=request` (what was asked), `kind=report` (what each agent did), `kind=response`
(verdicts/decisions), and `kind=model` telemetry — never from a free-form description.

## Evaluation is part of definition-of-done

**Every model change MUST run the project's recommended evals on the LOCAL machine
(Mac, `--device mps`/`cpu`) AFTER the GPU box is shut down.** The GPU is for
*training only*; it is terminated the moment weights are published, and must never
idle through an eval. The required sequence for any model change is:
`train (GPU) → publish weights → TERMINATE GPU → pull weights to Mac → eval (local) → record results`.
A model change is NOT complete until its evals have run locally and the metrics are
recorded in `results/EVAL_REPORT.md` (with per-run JSON/CSV under `results/<eval>/`).
What "the recommended evals" means is defined in `docs/deepdives/EVAL_STRATEGY_DEEPDIVE.md` and
implemented by `pipeline/eval_detector.py`, `pipeline/eval_classifier.py`, and
`pipeline/eval_pipeline.py`.

You have built an HTML report under report.html. Keep it up to date with before and after images after every change, under a new tab with the change description.

## Spec Server — task management (migrating off SPEC.md)

Task state for this repo is migrating from `SPEC.md` to the local **Spec Server**
(`/Users/mrdavis/source/spec-server`; API `http://localhost:8080/api/v1`; project slug
**`<project-name>`**). **Read `spec-server/INTEGRATION_GUIDE.md` before your first task** (endpoint
recipes: `spec-server/AGENTS_API.md`).

One-time migration — safe, idempotent, and it does NOT modify `SPEC.md`:

```bash
cd /Users/mrdavis/source/spec-server && docker compose up -d   # ensure the server is running
scripts/migrate-repo.sh <project-name> /Users/mrdavis/source/<project-name>-visualisation/SPEC.md "Bird Song Visualisation"
```

Then drive each atomic increment through the API instead of hand-editing `SPEC.md`:
- **Pick the next task** → `POST /projects/<project-name>/tasks/claim-next {"agent":"<you>"}` — never
  scan-and-pick a `[ ]` box (two agents would collide); claim is atomic and collision-proof.
- **Mark a task done** (the "flip the checkbox to `[x]`" step) →
  `POST /projects/<project-name>/tasks/<id>/complete {"commit_sha":"…","test_summary":"…","proof_cmd":"…"}`.
- **Reserve a SQL migration number** → `POST /projects/<project-name>/reservations {"namespace":"migration"}`
  — never choose a number by writing a `MIGRATION 0NN reserved` stub by hand (this is the LOC-10 /
  FLEET-9 "both grabbed 024" bug, now eliminated).
- **Your own specs** → `GET /projects/<project-name>/tasks?owner=<you>`.

**Also update every sub-agent config (`.claude/agents/*.md`) as part of this migration** — otherwise
agents keep hand-editing `SPEC.md` and drift from the server. The critical one is **`spec-keeper.md`**
(make it drive the API — claim-next / complete / reserve — instead of "only edit SPEC.md / flip the
checkbox"); also sweep `planner`, `implementer`, `reviewer`, `test-engineer`, `documentation`,
`report-writer`, and the reviewer panel. Run `grep -ril 'SPEC\.md' .claude/agents/` to find every file,
and use `spec-server/.claude/agents/spec-keeper.md` as the template. (Details: `spec-server/INTEGRATION_GUIDE.md` §1b.)

`SPEC.md` stays a **mirror**: refresh it any time with
`curl -s http://localhost:8080/api/v1/projects/<project-name>/export > SPEC.md`. Everything else in this
file still applies (incl. the Miro board sync and eval rules). If the server is unreachable, fall
back to the `SPEC.md` workflow below — nothing is lost.

Work in atomic increments:
1. Read SPEC.md before changing code.
2. Claim exactly one task via the Spec Server — `POST .../projects/<project-name>/tasks/claim-next {"agent":"<you>"}` (atomic, collision-proof; 204 = backlog empty). Only fall back to scanning SPEC.md for an unchecked `[ ]` box if the server is unreachable.
3. Restate the task in one sentence.
4. Make the smallest code change that completes only that task.
5. Run the narrowest relevant test/check. For MODEL changes, additionally run the recommended evals locally AFTER the GPU box is shut down (see "Evaluation is part of definition-of-done") and record metrics in results/EVAL_REPORT.md.
6. Commit the changes with a very descriptive commit description and a short tldr
   - make sure we are on the branch 'real-time-video-tracking'
7. Mark the task done in the Spec Server — `POST .../projects/<project-name>/tasks/<id>/complete
   {"commit_sha":"…","test_summary":"…","proof_cmd":"…"}` (the server is the source of truth; this is
   the "flip the checkbox" step). Add any discovered follow-ups via `POST .../projects/<project-name>/tasks {…}`.
   Then:
   - refresh the SPEC.md mirror: `curl -s http://localhost:8080/api/v1/projects/<project-name>/export > SPEC.md`
   - **Post the journal notes** (see "Spec Server task notes are the work JOURNAL" above): at
     dispatch `main` posts `kind=request`; each agent posts `kind=report` on completion;
     reviewers/security post `kind=response`; every agent posts `kind=model` telemetry. Then
     report-writer refreshes the tab from `GET .../tasks/<id>/notes`.
   - **ALWAYS sync the Miro board after any task-status change** — the board mirrors the live backlog.
     Run: `python -m tools.miro.spec_board --board-id uXjVHA6tRFA= --status todo,in_progress
     --group-by epic` (needs `MIRO_ACCESS_TOKEN`; strictly single-board — see
     docs/deepdives/MIRO_BOARD_AGENT_DEEPDIVE.md). Idempotent — pushes only the deltas.
   - (If the Spec Server is unreachable, fall back to hand-editing SPEC.md: mark `[x]`, move to the
     completed section, add follow-ups — then sync Miro.)
8. Record decisions in DECISIONS.md if any
9. Append entry to AGENT_LOG.md
10. Update SESSION_REPORT.md
11. Update the  HTML report with before and after images under a new tab.
12. **Tidy-up & git hygiene (definition-of-done — a task is NOT complete until ALL of these hold):**
    - `git status --porcelain` is EMPTY (clean tree). Every file you created or changed —
      including files changed OUTSIDE the Edit tool (terraform fmt, chmod, generators, installs,
      renames) — is either committed or covered by `.gitignore`. New files MUST be `git add`ed and
      committed, not left untracked.
    - No scratch left in the repo: temp/scratch goes under `/tmp` or the ignored `/scratch/` dir,
      never into tracked paths.
    - The SPEC checkbox for this task is FLIPPED to `[x]` by spec-keeper (do not merely "suggest" an
      entry — the box must actually change).
    - One logical commit for the task (descriptive message + tldr), on `real-time-video-tracking`,
      footer `Co-Authored-By: Claude Opus 4.8`.
    - The mandated chain actually ran: for code changes, reviewer AND security AND report-writer
      were invoked (or it is explicitly recorded WHY one was skipped). A deferred `[SECURITY-REVIEW]`
      tag is NOT a substitute for running security before commit.
13. Stop and report: files changed · test result · `git status` is clean · next recommended task.

Do not batch unrelated tasks.
Do not refactor unless SPEC.md explicitly asks for it.
If the spec is wrong or incomplete, update SPEC.md first, then continue.
A task is not complete until all documentation is updated.

For tasks that require permission multiple times, always write a script and ask permission once.

## Parallel-agent coordination
- **Migration numbers are reserved, not chosen.** Reserve the next number ATOMICALLY via the Spec
  Server — `POST .../projects/<project-name>/reservations {"namespace":"migration","reserved_by":"<you>"}`
  — which allocates a unique, monotonic number, so two agents never collide (the LOC-10/FLEET-9 "both
  grabbed 024" bug, now eliminated). Create the migration file only after the reservation returns.
  (Fallback if the server is down: the legacy SPEC.md `[ ] MIGRATION 0NN reserved by <task>` stub via
  spec-keeper.)
- **Task state is coordinated by the Spec Server, not by file locks.** `claim-next` (each agent gets a
  distinct task via `FOR UPDATE SKIP LOCKED`), `reservations` (unique numbers), and owner/lease replace
  the old "one writer at a time" dance for TASK state; `SPEC.md` is now a GENERATED MIRROR — never
  hand-edit it concurrently, regenerate it from the server (`/export`). For the remaining shared files
  (DECISIONS.md, AGENT_LOG.md, SESSION_REPORT.md, report.html — or the server's `/decisions`
  + `/events` endpoints), still only ONE agent at a time; prefer a new dated section over editing
  existing lines.

## AWS container/image builds — ALWAYS use CodeBuild

NEVER build-and-push container images for AWS from this machine with local `docker build`
/ `docker buildx --push`. This Mac is arm64, the AWS compute is x86_64, so a local build
is a slow QEMU cross-build plus a multi-GB push over a flaky link (it has hung/failed).
ALWAYS build in the cloud with **AWS CodeBuild**: it runs natively on amd64 (no emulation)
and pushes to ECR from inside AWS (no giant local upload), so it's fast and reliable.
Pattern: upload a small source bundle to S3 → a CodeBuild project (privileged Docker,
`aws/codebuild/standard:*`) with a buildspec that ECR-logs-in, `docker build`s, and pushes
→ `start-build`. Prefer defining the CodeBuild project in Terraform (all-Terraform rule).

## Terraform guardrails

**All durable infra is Terraform.** Every durable AWS resource (lambdas, API Gateway, Aurora, S3,
CloudFront, SQS, Batch, IAM, EventBridge, Secrets Manager, CodeBuild) is defined in Terraform. Do not
create durable resources with the console or ad-hoc CLI — only transient spot GPU instances are
CLI/boto3-managed (by aws-infra). If you change infra outside Terraform, you've created drift; fix the
Terraform to match before moving on.

**Credentials & blast radius — TWO separate stacks, TWO principals (do not conflate).**
- The **upload-platform serverless stack** (`upload-platform/terraform/`, state key
  `upload-platform/prod/terraform.tfstate`) deploys as the **ambient default credential — IAM user
  `feeds.deployer`** (account 985722751424), which owns the tfstate backend + has the service grants.
  Do NOT set `AWS_PROFILE` for it; before applying, confirm `aws sts get-caller-identity` shows
  `arn:aws:iam::985722751424:user/feeds.deployer`.
- `AWS_PROFILE=<project-name>-infra` is ONLY for the **GPU/training foundation** (`infra/terraform/`, transient
  spot GPU boxes). That role has NO upload-platform tfstate access — forcing it on the upload-platform
  deploy fails at `terraform plan` with a backend AccessDenied (cost us an aborted deploy 2026-06-26).
- Never mutate either stack with personal/SSO creds. Reads may use a read-only profile.
- NEVER touch the protected GPU instance `i-032824e440c51c455`. It is not Terraform-managed — do not
  import it, reference it, or let any rule/reaper target it.
- Cost is the top priority: never leave a GPU box or other transient resource running after a task.

**Plan before apply — always.**
- Never `terraform apply` without reading the plan first. Prefer `terraform plan -out=tfplan` then
  `apply tfplan`. For a narrow change use `-target=...`; reserve a full apply for genuinely broad
  changes, and still read every line.
- After any apply, the post-apply `terraform plan` MUST be clean ("No changes"). A non-clean plan
  means drift or an incomplete change — resolve it, don't leave it.
- `terraform fmt` and `terraform validate` must pass before you commit Terraform source.

**The two deploy gotchas (these have bitten us repeatedly).**
- **Untracked `source_code_hash`.** Several lambdas have their `source_code_hash` untracked, so
  `terraform apply` does NOT update their code. After apply, for every lambda whose source changed,
  compare the deployed `CodeSha256` against the local zip and run `aws lambda update-function-code`
  on any that drift. Do not assume apply shipped the code.
- **Non-deterministic zips.** `build_lambdas.sh` rebuilds timestamps, so `terraform plan` shows
  perpetual `source_code_hash` drift. Reconcile to the real code state; don't chase the churn, and
  don't commit a "fix" that's only the timestamp moving.

**State safety.**
- Never hand-edit state, never `terraform state rm`/`import` as a shortcut, and never commit
  `*.tfstate*` or `.terraform/` (they are gitignored — keep it that way). `.terraform.lock.hcl` stays
  tracked.
- `terraform destroy` (or destroying a durable resource via a plan) requires explicit user consent.
- IAM least-privilege: scope every policy to specific ARNs/actions — no `"*"` resource/action grants.
  New IAM grants require explicit user consent (per the standing permissions rule).

**Parallel-agent rule (state lock).** Only ONE `terraform apply` runs at a time — concurrent applies
fight over the state lock and can corrupt/abort. Code-only agents NEVER apply; they write Terraform
SOURCE and hand off to a single coordinated deploy (see the deploy-coordinator agent). Reserve
migration numbers (above) the same way you reserve a deploy slot.

