# Velvet Grill — Pre-Command Code Checklist

## Documentation

- [ ] `PRD.md` reviewed
- [ ] `DESIGN_SYSTEM.md` reviewed
- [ ] `ARCHITECTURE.md` reviewed
- [ ] `AGENTS.md` reviewed
- [ ] `SECURITY_WORKFLOW.md` reviewed
- [ ] `AI_WORKFLOW.md` reviewed
- [ ] `SKILLS_PLAN.md` reviewed

## Architecture Gaps

- [ ] Testing stack documented
- [ ] Order lifecycle and allowed transitions documented
- [ ] Payment lifecycle and cash/digital payment rules documented
- [ ] Dine-in table validation and server-side table resolution documented
- [ ] Stock concurrency and atomicity strategy documented
- [ ] Idempotency strategy documented

## Repository

- [ ] `git status` clean
- [ ] current Git checkpoint known
- [ ] no secrets tracked
- [ ] `.gitignore` covers local secrets and temporary tooling files

## Command Code

- [ ] Go plan terms reviewed
- [ ] no automatic top-up
- [ ] default permission mode chosen
- [ ] YOLO/bypass disabled for normal work
- [ ] `git push` requires approval
- [ ] destructive database operations require approval
- [ ] secret reads are blocked/approved explicitly
- [ ] skills are installed selectively
- [ ] `.commandcode/settings.json` has been reviewed separately

## First Session

1. Start in plan mode.
2. Ask the agent to inspect the project and summarize its understanding.
3. Do not allow code changes during the first review.
4. Compare the agent's understanding against PRD/architecture/security documents.
5. Run one small, non-critical implementation task.
6. Review the diff.
7. Run relevant checks.
8. Commit only after human verification.
