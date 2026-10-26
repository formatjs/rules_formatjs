# CI

BuildBuddy runs full tests in the root workspace, `examples/simple`, and
`examples/aggregate`. A separate action cross-builds extraction, compilation,
aggregation, and CLI targets for Linux x64/ARM64, macOS x64/ARM64, and Windows x64.
The CLI is prebuilt; these builds check target-platform independence while
running build tools on Linux.

GitHub Actions runs native CLI smoke tests on macOS, Windows, and Linux ARM64.
Windows also checks extraction from a large source list.

Link `formatjs/rules_formatjs` in the FormatJS BuildBuddy organization's Workflows
page. Workflow authentication comes from BuildBuddy; GitHub Actions needs no
BuildBuddy secret.

The active `main` ruleset requires these checks:

- `Test all targets` (BuildBuddy app, ID 317600)
- `Cross-build all platforms` (BuildBuddy app, ID 317600)
- `ci` (GitHub Actions, ID 15368; requires every native smoke job)
- `verify-hooks` (GitHub Actions, ID 15368)

Keep these names in sync with workflow files and repository settings. Missing,
failed, cancelled, or skipped native jobs cannot pass the `ci` gate. Both CI
systems also handle merge-queue commits.
