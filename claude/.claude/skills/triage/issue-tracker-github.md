# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Pre-flight on first use in a repo

Before creating, editing, or labelling any issue in a repo for the first time in a session, ensure the canonical triage labels exist. This is idempotent — only missing labels are created.

```bash
existing=$(gh label list --json name --jq '.[].name')
declare -A canonical=(
  [bug]="d73a4a:Something is broken"
  [enhancement]="a2eeef:New feature or improvement"
  [needs-triage]="fbca04:Maintainer needs to evaluate"
  [needs-info]="d4c5f9:Waiting on reporter"
  [ready-for-agent]="0e8a16:Fully specified, AFK-ready"
  [ready-for-human]="1d76db:Needs human implementation"
  [wontfix]="cccccc:Will not be actioned"
)
for label in "${!canonical[@]}"; do
  IFS=':' read -r colour desc <<< "${canonical[$label]}"
  echo "$existing" | grep -qx "$label" || gh label create "$label" --color "$colour" --description "$desc"
done
```

If the repo has a per-repo `docs/agents/triage-labels.md` overriding any of these names, use those names instead — do not create the canonical ones in addition.

If `gh auth status` fails, stop and surface clearly — do not attempt to proceed.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
