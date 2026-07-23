# Q1: [DECISION] Should we use minisign for bootstrapping scripts?

**Status:** Closed
**Date opened:** 2026-07-19
**Date closed:** 2026-07-20

## Why this question
The `minisign` is the format used by zig compiler, which we can resolve
dynamically based on each `URL` rather than pinning the hashes, but it
introduces a dependency that is unlikely to be present on the user's
machine, unlike other dependencies used in the scripts.

So we need to evaluate whether it is better to use `minisign` at the cost
of added friction(user) for dynamic resolution or pin the version of zig compiler
by hardcoding hashes?

## Options considered
| Option | Description |
|---|---|
| A | Using `minisign` |
| B | Using pinned, hardcoded `sha-256` hashes |

## Tradeoffs
| Criteria | Minisign | Hashes |
|---|---|---|
| Cost | Added friction for user to install `minisign` | Higher maintenance cost due to hardcoded hashes |
| Maintenance (Dev) | Low - Dynamic Resolution | High - Hardcoded Hashes, manual update required |
| Friction (User) | High - install an unlikely dependency | Less - uses only commonly available dependencies |

## Decision
The Hardcoding hashes approach is better for our use-case, as the added
maintenance cost act as gatekeeping for version bumping the zig version
for more cautious approach - as there are breaking changes between versions.

Also, the core spirit of the bootstrapping script is an easy, friction-less,
way to use the project. Such that, the experience feels like an "out-of-box"
experience. Adding a dependency that the user most likely has to install
themselves goes against the core of the spirit.

With the above reasons, the 2nd approach - Hardcoding Hashes approach is chosen.
For the process to follow in case of version bump, follow the "NB" comment
provided in the script.

## Follow-up questions raised
None
