# AI Health Assessment — Setup and Usage Guide

The healthcheck exists so that **two reviewers** can look at your SQL Server: the rules
engine (fast, deterministic thresholds) and an AI (correlation, root cause, judgment).
This guide explains how to plug the AI in — at home or inside a company — in plain words.

## The workflow

```powershell
# 1. Collect — 39 scripts, one CSV each
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01

# 2. Rules review — deterministic CRITICAL / WARNING / INFO findings
.\powershell\reporting\Review-HealthCheckOutput.ps1

# 3. AI assessment — correlation, root cause, prioritized written report
.\powershell\reporting\Invoke-AiAssessment.ps1
```

Step 3 needs an AI to talk to. There are **two ways** to give it one, and you can use
either or both. Nothing about your AI account is ever stored in this repo — that is what
makes it safe to clone anywhere.

---

## Way 1 — Claude Code in your editor (easiest, no key handling)

**What it is:** Claude Code is an AI assistant that runs inside VS Code (or a terminal).
You sign in once, and it can read this repo and run its scripts for you.

**Like you're five:** the repo is a toy box. Claude Code is a friend who comes to your
house and plays with the toys. The friend brings their own library card (their sign-in) —
the toy box doesn't keep it. At your house, your friend uses your family's card. At school,
they use the school's card. Same friend, same toys, different card.

**Setup:**

1. Install the **Claude Code** extension in VS Code (or `npm install -g @anthropic-ai/claude-code` for the terminal version).
2. Open this repo folder and start Claude Code. It asks you to sign in — a browser window opens.
3. Sign in with:
   - **Home:** your personal Claude account.
   - **Work:** your company Claude account (Team/Enterprise), or whatever sign-in your
     company's IT has approved. If your company uses Claude via Amazon Bedrock, Google
     Vertex, or an internal gateway, Claude Code supports those too — IT sets a couple of
     environment variables and the sign-in step changes; ask them for their standard setup.
4. Ask it: *"Run the healthcheck against SERVERNAME and write the AI assessment."*
   The repo's `CLAUDE.md`, `docs/ai-playbook.md`, and
   `powershell/reporting/ai-assessment-rubric.md` already tell it exactly how.

**Repointing between home and work is just signing in with a different account on that
machine.** The repo carries the instructions; the machine carries the identity.

---

## Way 2 — the API script (scriptable, schedulable)

**What it is:** `Invoke-AiAssessment.ps1` sends the healthcheck CSVs to the Claude API
directly and saves the report as a markdown file. No editor involved — it can run from a
scheduled task.

**Like you're five:** instead of a friend visiting, you mail the toy box a letter and get
a letter back. To mail letters you need a stamp (an **API key**) and an address (the
**API URL**). Both live in envelopes on your machine called *environment variables* —
never inside the toy box itself.

**Setup — two environment variables at most:**

| Variable | Home | Work |
|---|---|---|
| `ANTHROPIC_API_KEY` | Your personal key from platform.claude.com | The key your company issues you |
| `ANTHROPIC_BASE_URL` | Leave unset (defaults to api.anthropic.com) | Set **only if** IT gives you a gateway/proxy URL |

```powershell
# Current session only (disappears when the window closes)
$env:ANTHROPIC_API_KEY = 'sk-ant-...'

# Permanently for your Windows user (new terminals pick it up)
setx ANTHROPIC_API_KEY "sk-ant-..."

# Work example with a corporate gateway
setx ANTHROPIC_API_KEY "the-key-IT-gave-you"
setx ANTHROPIC_BASE_URL "https://ai-gateway.yourcompany.com"
```

Then:

```powershell
.\powershell\reporting\Invoke-AiAssessment.ps1
# Report lands in output-files\assessments\<server>-<timestamp>.md
```

**Repointing between home and work = different values in those two variables.** The script
is identical on both machines.

---

## The corporate data question (read this before running at work)

Step 3 sends healthcheck data — server names, database names, login names, file paths,
query text from the plan cache — to whatever AI endpoint you configured. At home that's
your call. At work, get sign-off first, and use the built-in preview:

```powershell
# Builds the exact prompt and writes it to a file WITHOUT calling any API
.\powershell\reporting\Invoke-AiAssessment.ps1 -DryRun
```

Hand the preview file (`output-files\assessments\prompt-preview-*.txt`) to whoever approves
tooling — it is byte-for-byte what would be sent. Points that usually satisfy a review:

- Nothing is sent until you run step 3; steps 1–2 are fully local.
- No credentials or table data are collected — the healthcheck reads metadata and DMVs.
- Keys live in environment variables, never in the repo, so a clone contains no secrets.
- `output-files/` is gitignored — collected data and reports never end up in git.
- With a corporate gateway (`ANTHROPIC_BASE_URL`), traffic follows the company's own
  logging, retention, and egress rules.

---

## What the AI is told to do

The instructions live in one file: `powershell/reporting/ai-assessment-rubric.md`. Both
ways use the same rubric, so a Claude Code assessment and an API assessment have the same
structure: Verdict, Instance Profile, Priority Issues (with evidence and fixes), Security
Posture, Performance Notes, Backup & Recovery Readiness, Watch List, Checked and Clean.
Edit the rubric to change what every future assessment looks like — that file is the product.

## Costs (Way 2)

A full assessment of one instance is roughly 30–60K input tokens and a few thousand output
tokens. At `claude-opus-4-8` rates ($5 input / $25 output per million tokens) that is
**well under $1 per server per run**. The script prints exact token usage and estimated
cost after every call.
