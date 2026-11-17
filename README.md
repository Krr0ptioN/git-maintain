# git-maintain

GitHub Action that runs `git maintenance`, repacks with `--cruft`, publishes the compaction statistics as a Markdown table, and notifies maintainers.

## Quick start

Copy [`templates/git-maintain.yml`](templates/git-maintain.yml) to `.github/workflows/git-maintain.yml` in your repository, or paste:

```yaml
name: Git Maintenance

on:
  schedule:
    - cron: "0 5 * * 0" # Sundays 05:00 UTC
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  maintenance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: Krr0ptioN/git-maintain@v1
        with:
          notify-users: your-username
```

`fetch-depth: 0` is required so maintenance sees the full history. `issues: write` is only needed when `create-issue` is `true`.

## Inputs

| Input | Default | Description |
|:---|:---|:---|
| `notify-users` | `""` | Comma-separated usernames to `@mention`. The first is assigned to the tracking issue. |
| `create-issue` | `true` | Create the tracking issue, or comment on it if it already exists. |
| `issue-title` | `🛠️ Git Maintenance Statistics` | Title used to find/create the tracking issue. |
| `step-summary` | `true` | Append the report to the job summary. |
| `enable-cruft` | `true` | Pack unreachable objects separately (`--cruft`). |
| `threads` | auto | Threads for delta compression. |
| `github-token` | `${{ github.token }}` | Token used for issue operations. |

## Outputs

| Output | Description |
|:---|:---|
| `report-markdown` | Full Markdown report. |
| `total-objects` | Objects in the main pack. |
| `total-cruft` | Objects in the cruft pack. |

## Sample report

```markdown
| Operation | Value |
|:---|:---|
| Enumerating objects | 1459 |
| Counting objects | 100% (1459/1459) |
| Delta compression | 8 threads |
| Compressing objects | 100% (676/676) |
| Writing objects | 100% (1459/1459) |
| Reused objects | 1459 (delta 723) |
| pack-reused | 0 (from 0) |
| Total objects | `1459` |
| Enumerating cruft objects | 1501, |
| Counting objects | 100% (42/42) |
| Delta compression | using up to 8 threads |
| Compressing objects | 100% (33/33) |
| Writing objects | 100% (42/42) |

Total 42 (delta 6), reused 42 (delta 6), pack-reused 0 (from 0)
```

## License

[MIT](LICENSE)
