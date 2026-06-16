# Contributing

Seed Box uses a simple branch-and-pull-request workflow.

## Branches

- `main` is the stable branch and should stay buildable.
- Use one branch per feature, fix, or GitHub issue.
- Prefer branch names like `codex/issue-21-accessibility-pass` or
  `codex/pr-workflow`.
- Do not use a permanent `develop` branch.

Tiny documentation-only edits may go directly to `main`, but Swift code,
entitlements, release changes, migrations, App Store/privacy work, and user
facing features should use a branch and pull request.

## Pull Requests

Open a pull request for each meaningful change. A good pull request includes:

- the issue or task it addresses;
- a short summary of what changed;
- the verification performed;
- screenshots for visible UI changes;
- notes for security, sandboxing, privacy, App Store, or release behavior when
  relevant.

Use draft pull requests for larger work that needs an early checkpoint.

## Verification

Before merging behavior changes, run the relevant checks. For most Swift
changes, the default check is:

```sh
xcodebuild test -project SeedBox.xcodeproj -scheme "Seed Box" -destination "platform=macOS"
```

For release or packaging changes, also use the checks documented in
`Docs/Release.md`.

## Merging

Squash merge pull requests into `main` so each completed task becomes one clean
main-branch commit. Tag public releases from `main`.
