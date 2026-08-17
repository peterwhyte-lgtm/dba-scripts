# Docs

Everything here supports one goal: getting you from "I have this repo" to "I have an answer about my
SQL Server". Start at whichever row matches what you are trying to do.

## Start here

| I want to… | Read |
|------------|------|
| Get from a fresh clone to a first query, in five minutes | [quick-start.md](quick-start.md) |
| Install prerequisites, set permissions, fix a connection problem | [../SETUP.md](../SETUP.md) |
| Find the script that answers my question | [script-catalog.md](script-catalog.md) |
| Understand what is in which folder | [repo-structure.md](repo-structure.md) |
| Run the health check and have an AI review the results | [ai-assessment.md](ai-assessment.md) |
| Work out which scripts to run for the symptom in front of me | [ai-playbook.md](ai-playbook.md) |
| Plan or execute a migration, upgrade, or failover | [ops/](ops/) |
| Look something up mid-incident | [ops/dba-quickref.md](ops/dba-quickref.md) |
| Write a script that fits the repo's standards | [standards.md](standards.md) and [templates.md](templates.md) |
| See what is planned next | [roadmap.md](roadmap.md) |

## The AI health assessment

The repo's headline workflow is three steps: collect, apply fixed rules, then have an AI read the whole
collection and correlate what the rules cannot.

- **[ai-assessment.md](ai-assessment.md)** — how to plug an AI in, at home or inside a company. Covers
  both routes (Claude Code in your editor, or the API script), and the corporate data-review question
  including the `-DryRun` preview that shows byte-for-byte what would be sent.
- **[ai-playbook.md](ai-playbook.md)** — symptom-to-script decision support. "The database is slow" →
  which scripts, in what order, and what to do with the output. Written for an AI agent working in the
  repo, and just as usable by a person.

The rubric that drives every assessment is
[`powershell/reporting/ai-assessment-rubric.md`](../powershell/reporting/ai-assessment-rubric.md).
Edit that file and every future assessment changes shape.

## Reference

| Doc | What it is |
|-----|------------|
| [script-catalog.md](script-catalog.md) | Every SQL script and every PowerShell script with real logic, grouped by folder, described by its own header, with a link to its companion blog post where one exists |
| [repo-structure.md](repo-structure.md) | The folder map and what belongs in each area |
| [standards.md](standards.md) | Header format, safety annotations, naming, and the rules a script has to meet |
| [templates.md](templates.md) | Copy-paste starting points for a new SQL script, wrapper, or orchestrator |
| [roadmap.md](roadmap.md) | Current state and what is being worked on |

Folder-level detail lives next to the scripts, not here: [`sql/README.md`](../sql/README.md),
[`sql/collectors/README.md`](../sql/collectors/README.md),
[`sql/traces/README.md`](../sql/traces/README.md),
[`sql/migration/README.md`](../sql/migration/README.md),
[`powershell/README.md`](../powershell/README.md),
[`tools/README.md`](../tools/README.md), and
[`tests/README.md`](../tests/README.md).

## Planned work — `ops/`

`docs/ops/` covers the work you schedule rather than the work that ambushes you: change orders,
execution checklists, runbooks, rollback playbooks, and SQL change templates. See
[ops/change-templates/README.md](ops/change-templates/README.md) for the full index and the
order to use them in.

## This repo and sqldba.blog

The scripts live here. The write-ups live on [sqldba.blog](https://sqldba.blog).

- **Repo → blog.** Where a script has a companion post, the post URL is recorded in the script's own
  header on the `Author` line, and [script-catalog.md](script-catalog.md) collects them all into one
  **Post** column. 143 of the 181 SQL scripts have one today. A script with no post works exactly the
  same way — it just has not been written up yet.
- **Blog → repo.** <https://sqldba.blog/scripts/> is the project page for this repo; the posts that
  link here start from there. Landing from a post, the useful next stops are the
  [root README](../README.md) for what the toolkit is,
  [quick-start.md](quick-start.md) to run something in five minutes, and
  [script-catalog.md](script-catalog.md) to find the neighbours of whichever script sent you.

Documentation of a script's behaviour always lives in the script header first. The blog post explains
the problem and how to read the output; the header is what stays correct.
