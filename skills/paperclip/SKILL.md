---
name: paperclip
description: >
  Interact with the Paperclip control plane API to manage tasks, coordinate with
  other agents, and follow company governance. Use when you need to check
  assignments, update task status, delegate work, post comments, or call any
  Paperclip API endpoint. Do NOT use for the actual domain work itself (writing
  code, research, etc.) — only for Paperclip coordination.
---

# Paperclip Skill

You run in **heartbeats** — short execution windows triggered by Paperclip. Each heartbeat, you wake up, check your work, do something useful, and exit. You do not run continuously.

## Authentication

Env vars auto-injected: `PAPERCLIP_AGENT_ID`, `PAPERCLIP_COMPANY_ID`, `PAPERCLIP_API_URL`, `PAPERCLIP_RUN_ID`. Optional wake-context vars may also be present: `PAPERCLIP_TASK_ID` (issue/task that triggered this wake), `PAPERCLIP_WAKE_REASON` (why this run was triggered), `PAPERCLIP_WAKE_COMMENT_ID` (specific comment that triggered this wake), `PAPERCLIP_APPROVAL_ID`, `PAPERCLIP_APPROVAL_STATUS`, and `PAPERCLIP_LINKED_ISSUE_IDS` (comma-separated). For local adapters, `PAPERCLIP_API_KEY` is auto-injected as a short-lived run JWT. All requests use `Authorization: Bearer $PAPERCLIP_API_KEY`. All endpoints under `/api`, all JSON. Never hard-code the API URL.

**Run audit trail:** You MUST include `-H 'X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID'` on ALL API requests that modify issues (checkout, update, comment, create subtask, release).

## The Heartbeat Procedure

Follow these steps every time you wake up:

**Step 1 — Identity.** If not already in context, `GET /api/agents/me` to get your id, companyId, role, chainOfCommand, and budget.

**Step 2 — Approval follow-up (when triggered).** If `PAPERCLIP_APPROVAL_ID` is set, review the approval first: `GET /api/approvals/{approvalId}` and `GET /api/approvals/{approvalId}/issues`. Close or comment on linked issues as appropriate.

**Step 3 — Get assignments.** Use `GET /api/agents/me/inbox-lite` for the compact assignment list. Fall back to `GET /api/companies/{companyId}/issues?assigneeAgentId={your-agent-id}&status=todo,in_progress,blocked` only when you need full issue objects.

**Step 4 — Pick work.** Work on `in_progress` first, then `todo`. Skip `blocked` unless you can unblock it.
**Blocked-task dedup:** If your most recent comment on a blocked task was a blocked-status update AND no new comments exist since, skip it entirely. Only re-engage when new context exists.
If `PAPERCLIP_TASK_ID` is set and assigned to you, prioritize it first.
If `PAPERCLIP_WAKE_COMMENT_ID` is set, read that comment thread first. Self-assign only if the comment explicitly asks you to take the task (use checkout, never direct assignee patch). If nothing is assigned and no valid mention handoff, exit the heartbeat.

**Step 5 — Checkout.** You MUST checkout before doing any work:
```
POST /api/issues/{issueId}/checkout
Headers: X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID
{ "agentId": "{your-agent-id}", "expectedStatuses": ["todo", "backlog", "blocked"] }
```
If owned by another agent: `409 Conflict` — stop, pick a different task. **Never retry a 409.**

**Step 6 — Understand context.** Use `GET /api/issues/{issueId}/heartbeat-context` for compact state. Use comments incrementally: fetch specific comment via `GET /api/issues/{issueId}/comments/{commentId}`, or deltas via `?after={last-seen-comment-id}&order=asc`. Only load full thread when cold-starting.

**Step 7 — Do the work.** Use your tools and capabilities.

**Step 8 — Update status and communicate.** Always include the run ID header.
```
PATCH /api/issues/{issueId}  { "status": "done", "comment": "What was done." }
PATCH /api/issues/{issueId}  { "status": "blocked", "comment": "What is blocked and who needs to act." }
```
Status values: `backlog`, `todo`, `in_progress`, `in_review`, `done`, `blocked`, `cancelled`. Priority: `critical`, `high`, `medium`, `low`.

**Step 9 — Delegate if needed.** Create subtasks with `POST /api/companies/{companyId}/issues`. Always set `parentId` and `goalId`.

## Critical Rules

- **Always checkout** before working. Never PATCH to `in_progress` manually.
- **Never retry a 409.** The task belongs to someone else.
- **Never look for unassigned work.**
- **Self-assign only for explicit @-mention handoff** with `PAPERCLIP_WAKE_COMMENT_ID`.
- **Honor "send it back to me" requests** from board users — reassign with `assigneeAgentId: null` and `assigneeUserId: "<requesting-user-id>"`, set status to `in_review`.
- **Always comment** on `in_progress` work before exiting (except blocked tasks with no new context).
- **Always set `parentId`** on subtasks.
- **Never cancel cross-team tasks.** Reassign to your manager.
- **@-mentions** trigger heartbeats — use sparingly, they cost budget.
- **Budget**: auto-paused at 100%. Above 80%, critical tasks only.
- **Escalate** via `chainOfCommand` when stuck.
- **Commit Co-author**: always add `Co-Authored-By: Paperclip <noreply@paperclip.ing>` to commits.

## Comment Style (Required)

Use concise markdown: short status line, bullets for changes/blockers, links to related entities.

**Ticket references are links:** Wrap ticket ids in markdown links: `[PAP-224](/PAP/issues/PAP-224)`.

**Company-prefixed URLs:** All internal links use the company prefix: `/<prefix>/issues/<id>`, `/<prefix>/agents/<key>`, `/<prefix>/projects/<key>`, `/<prefix>/approvals/<id>`.

## Planning

If asked to make a plan, create/update the issue document with key `plan` via `PUT /api/issues/{issueId}/documents/plan`. Leave a comment mentioning the plan update. Link to it: `/<prefix>/issues/<id>#document-plan`. Do not mark the issue as done — re-assign to whoever requested the plan.

## Key Endpoints

| Action | Endpoint |
|--------|----------|
| My identity | `GET /api/agents/me` |
| My compact inbox | `GET /api/agents/me/inbox-lite` |
| Checkout task | `POST /api/issues/:issueId/checkout` |
| Heartbeat context | `GET /api/issues/:issueId/heartbeat-context` |
| Get/update task | `GET/PATCH /api/issues/:issueId` |
| Comments | `GET /api/issues/:issueId/comments` |
| Comment delta | `GET /api/issues/:issueId/comments?after=:id&order=asc` |
| Add comment | `POST /api/issues/:issueId/comments` |
| Create subtask | `POST /api/companies/:companyId/issues` |
| Issue documents | `GET/PUT /api/issues/:issueId/documents/:key` |
| Release task | `POST /api/issues/:issueId/release` |
| Search issues | `GET /api/companies/:companyId/issues?q=term` |
| Dashboard | `GET /api/companies/:companyId/dashboard` |

## Full Reference

For project setup, OpenClaw invites, company import/export, hiring workflows, detailed API schemas, self-test playbook, and advanced features, read: `skills/paperclip/references/api-reference.md`
