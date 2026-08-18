# Branch rulesets

`main-protection.json` is the ruleset that clears GitHub's "Your main branch isn't protected"
banner. Import it, don't hand-build it:

**Settings → Rules → Rulesets → New ruleset → Import a ruleset** → pick
`.github/rulesets/main-protection.json` → **Create**.

## What it does, and why each rule is here

| Rule | Why |
| --- | --- |
| Restrict deletions | `main` cannot be deleted. This is the one that actually matters. |
| Block force pushes (non-fast-forward) | A bad `git push --force` from a stale clone cannot rewrite published history. |
| Require status checks | A pull request into `main` cannot merge until CI is green. |

**Bypass: Repository admin, always.** This repo is a one-person repo and `main` takes direct
pushes (219 commits, 2 of them merges). Without the bypass, requiring status checks blocks
`git push` to `main` outright — GitHub has no green check for a commit that has not been pushed
yet. The bypass keeps the daily flow working; the deletion and force-push guards still stand for
anything that is not an admin session.

If the workflow ever changes to branch-and-PR only, drop the `bypass_actors` block and add
`{"type": "pull_request", "parameters": {"required_approving_review_count": 0, ...}}`.

## Checks deliberately NOT required

`MCP server / Test (Python 3.10)` and `3.13` are **path-filtered** (`paths: [ 'mcp/**' ]`). A PR
that touches no `mcp/` file never runs them, and a required check that never runs leaves the PR
stuck "Expected — waiting for status" forever. Leave them out.

Same reasoning applies to any future path-filtered workflow: filter or require, not both.
