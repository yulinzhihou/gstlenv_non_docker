# Repository Instructions

## CodeGraph

If a `.codegraph/` directory exists at the repository root, use CodeGraph before
grep, file searches, or source reads to locate or understand code. Prefer the
`codegraph_explore` MCP tool, or use `codegraph explore "<question>"`. Skip
CodeGraph when the repository is not indexed; do not create an index implicitly.

## Commit and Publish

The user requires automatic commits and publication for work in this repository.
After each completed batch of project modifications:

1. Review the diff and run verification appropriate to the changes.
2. Stage only the intended project changes, preserving unrelated user changes.
3. Create a descriptive Git commit on the current branch.
4. Push that commit explicitly to all three existing remotes: `origin`, `gitee`,
   and `github`. Preserve their configured URLs and the current upstream.
5. Verify each remote branch tip matches the local committed HEAD. Report the
   commit identifier, verification performed, and publication results.

Use ordinary non-force pushes. Never rewrite published history, bypass failed
checks, include credentials or ignored offline binaries, or commit unfinished
intermediate edits merely to satisfy this workflow. If a remote rejects a push
or authentication fails, preserve the local commit and successful pushes, and
clearly report the remaining failure instead of claiming all remotes are synced.

These instructions apply to completed agent work, not a background filesystem
watcher. Honor an explicit user request to pause work or not commit/push a
particular change.
