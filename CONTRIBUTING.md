# Contributing · 贡献指南

Thanks for helping keep Beijing's tech community informed! 感谢你的贡献！

## What belongs here

Tech-related events in Beijing (or online events organized by Beijing communities): meetups, conferences, hackathons, workshops, talks. Free and paid events are both welcome.

## Option 1: issue form (no Git needed)

[Open the form](https://github.com/bovi/beijing-events/issues/new?template=new-event.yml), fill it in and submit. A bot checks the details and opens a pull request. If something is wrong it comments on your issue, and you just edit the issue.

填写 [表单](https://github.com/bovi/beijing-events/issues/new?template=new-event.yml) 并提交即可，机器人会自动检查并创建 Pull Request。

## Option 2: pull request

1. Copy [events/_template.yml](events/_template.yml) to `events/<year>/<date>-<short-title>.yml`, e.g. `events/2026/2026-11-15-ai-builders-meetup.yml`. You can do this directly in the GitHub web editor.
2. Fill in the fields. Required: `title`, `date`, `location`, `url`, `category`.
3. Open a pull request. A check validates the file automatically.

Don't edit the tables in `README.md`, `calendar/` or `past/`. They are regenerated automatically after merge.

## Automatic discovery

Once a day the [discover-events workflow](.github/workflows/discover-events.yml) uses GitHub Copilot CLI to search the web for upcoming tech events in Beijing. Events that are not yet listed (and not already tracked in an issue or pull request) are filed as `new-event` issues labeled `ai-discovered`, and the normal issue-to-PR pipeline takes over. Every event still goes through pull request review before it appears in the list.

Notes for maintainers:

- The workflow needs the `COPILOT_CLI_TOKEN` repository secret: a fine-grained PAT of an account with a Copilot subscription, with the account permission **Copilot Requests** and **Issues: read and write** on this repository. The PAT (not `GITHUB_TOKEN`) creates the issues so that the issue-to-PR workflow is triggered.
- Each run uses premium requests from that account's Copilot plan.
- Test it from the Actions tab with **Run workflow** and *dry run* enabled: the job summary lists what would be created without opening issues.
- The script verifies every event URL and skips duplicates, but WeChat-only events are invisible to it - those still need humans.
- If the bot filed something wrong, close the issue; it will not be re-filed (closed `new-event` issues count as known).

### Check locally (optional)

Only Ruby is needed, no gems:

```sh
ruby scripts/validate.rb events/2026/2026-11-15-ai-builders-meetup.yml
ruby scripts/build.rb   # preview the README tables
```

## Fields

| Field | Required | Example |
|---|---|---|
| `title` | yes | `Beijing AI Builders Meetup` (max 100 chars) |
| `date` | yes | `2026-11-15` |
| `end_date` | no | `2026-11-16` |
| `time` | no | `"19:00-21:30"` (Beijing time, keep the quotes) |
| `location` | yes | `Zhongguancun, Haidian` |
| `address` | no | `中关村创业大街 1号` |
| `online` | no | `true` / `false` |
| `language` | no | `[en, zh]` |
| `category` | yes | `[ai, startup]`: one or more of `ai, web, mobile, cloud, devops, data, security, hardware, open-source, startup, design, gaming, other` |
| `price` | no | `free`, `¥50` |
| `url` | yes | `https://...` |
| `organizer` | no | `Beijing AI Builders` |
| `description` | no | max 300 chars |

Updating or cancelling an event? Edit or delete its file in a pull request.
