# Task-to-script guide

Helpers for turning "I need something that does X" into a starting point quickly.

1. **Find the right category first** — `.\tools\triage\Quick-TaskRouter.ps1` suggests where the work
   belongs, and `.\tools\triage\Find-UsefulScript.ps1 -Keyword <word>` checks whether it already
   exists. It usually does.
2. **New SQL script** — there is no generator. Copy the header block from
   [`docs/templates.md`](../docs/templates.md) into `sql/<category>/<subfolder>/Get-Something.sql`,
   then scaffold its wrapper:
   `.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\<subfolder>\Get-Something.sql`
3. **New PowerShell helper** — `.\tools\scaffolding\Generate-NextPowerShell.ps1 -Task "backup age" -Category "disk-space"`
   creates a starter script under `powershell/<Category>/`.
4. **Multi-server version of an existing script** —
   `.\tools\scaffolding\New-MultiServerScript.ps1 -ScriptPath <path> -Servers "SVR01,SVR02"`. See
   [`scaffolding/README-multi-server.md`](scaffolding/README-multi-server.md).
5. **Then refine it with your real DBA logic** and check it against
   [`docs/standards.md`](../docs/standards.md) before committing —
   `.\tools\triage\Get-StandardsAudit.ps1` will tell you what is missing.
