# Blog — sqldba.blog post drafts

This folder contains draft blog posts for [sqldba.blog](https://sqldba.blog). Each post has its own folder containing `index.md` (the post) and `images/` (screenshots and demo output used in the post).

**Repo:** https://github.com/peterwhyte-lgtm/dba-scripts

## Post index

| Folder | Title | Category | Scripts featured |
|--------|-------|----------|-----------------|
| [wait-statistics/](wait-statistics/index.md) | SQL Server Wait Statistics Explained | Performance | Get-WaitStatistics |
| [backup-coverage/](backup-coverage/index.md) | How to Audit SQL Server Backup Coverage | Backups | Get-BackupCoverage |
| [health-check-workflow/](health-check-workflow/index.md) | One-Command SQL Server Health Check | Monitoring | Invoke-HealthCheckCollection, Review-HealthCheckOutput |
| [blocking-sessions/](blocking-sessions/index.md) | Finding and Diagnosing SQL Server Blocking | Performance | Get-BlockingSummary, Get-BlockingSessions |
| [missing-indexes/](missing-indexes/index.md) | Finding Missing Indexes in SQL Server | Performance | Get-MissingIndexes |

## Folder structure

```text
blog/
  README.md                          this file
  _template/
    index.md                         template — copy this for new posts
    images/                          placeholder for template images
  [post-slug]/
    index.md                         post content
    images/                          screenshots and demo output for this post
      [slug]-output.png              example naming convention
```

## How to add a new post

1. Copy the `_template/` folder and rename it to the post slug (e.g. `tempdb-usage/`)
2. Rename nothing else — the post file is always `index.md` inside the folder
3. Fill in the frontmatter in `index.md` — title, slug, seo fields, and which scripts it features
4. Write the post following the template sections
5. Add screenshots to the `images/` subfolder and update the `<img>` tags in the post
6. Fill in the SEO block at the bottom before publishing
7. Add a row to the index table above
8. Publish to sqldba.blog when ready

## Content guidelines

- Lead with the DBA problem, not the script
- Include the complete SQL so readers can copy it into SSMS without visiting the repo
- Show the `run.ps1` command for readers who have the repo cloned
- Use `<img src="images/filename.png" alt="..." title="...">` for all post images (not Markdown `![]()`)
- Alt text ≤125 chars, descriptive, includes the focus keyphrase naturally
- Image title ≤60 chars
- Meta description 150–160 chars
- Explain each output column that is non-obvious
- Give threshold guidance — what counts as a problem and what to do about it
- End with the GitHub link and related scripts
