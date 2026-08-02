# Q1: [DECISION] Should we use minisign for bootstrapping scripts?

**Status:** Closed
**Date opened:** 2026-07-19
**Date closed:** 2026-07-20

## Why this question
Zig distributes release artifacts with minisign signatures, allowing download
integrity to be verified without pinning artifact hashes. However, verifying
these signatures requires the `minisign binary`,
which is unlikely to be installed on a typical developer's machine.

This [DECISION] evaluates whether the bootstrap scripts should depend on `minisign`
for dynamic verification or instead pin the expected `SHA-256` hashes of supported Zig releases.

## Options considered
| Option | Description                                  |
| ------ | -------------------------------------------- |
| A      | Verify downloads using `minisign` signatures |
| B      | Verify downloads using pinned SHA-256 hashes |


## Tradeoffs
| Criteria        | Minisign                             | Pinned hashes                          |
| --------------- | ------------------------------------ | -------------------------------------- |
| User experience | Requires installing `minisign`       | No extra dependency                    |
| Maintenance     | Low; signatures resolve dynamically  | Manual hash updates                    |
| Security        | Uses upstream signature verification | Relies on repository-maintained hashes |
| Version control | Easier to support arbitrary versions | Intentional version pinning            |


## Decision
Pinned SHA-256 hashes are chosen.

Although this introduces additional maintenance whenever the Zig version changes,
that maintenance is intentional rather than a drawback. The project targets specific
Zig versions, and updating those versions should be an explicit, reviewed change
rather than something that occurs implicitly.

Requiring users to install minisign would make the first experience with the project more cumbersome. 
The primary goal of the bootstrap scripts is to provide an out-of-the-box setup experience with
minimal prerequisites. Avoiding uncommon dependencies better aligns with that goal.

Version updates should therefore be performed by updating the pinned hashes according
to the process documented in the script.

## Follow-up questions raised
None
