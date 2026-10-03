# Implementation status — 2 October 2026

The companion [production-readiness plan](2026-10-02-security-and-production-readiness.md) remains the full scope. This file records the implementation completed in the current working tree and the gates that remain open.

## Implemented

- Client outbox now runs one bounded pass, retries with persisted delay, quarantines repeated failures, and preserves ordering after a blocked non-photo mutation. It no longer marks failed audit uploads or unsupported entities as successful.
- Hub uploads validate image names, content signatures and sizes. Backup import validates paths, manifest, module presence and JSON structure before modifying data, writes a recovery copy, and runs database changes in a transaction. Sales facts are restored with sales history.
- Hub login tokens use a persistent Hub-only random signing key, separate from the shared device secret. Protected routes resolve the current active user and apply explicit permissions to staff, settings, clinical, inventory, stock transfer, purchase, sale, and delete paths. Settings/profile responses omit saved PINs, token signing material and Google credentials. Medicine sync omits cost prices for staff without that permission.
- Fixed offline masked-PIN fallback and automatic masked-PIN reset are removed. New Windows Hubs require an administrator PIN setup; an existing Hub using the old default is sent through the same reset screen. Hub logins are rate limited and do not log attempted PINs.
- Saved auto-login PINs are cleared at startup, omitted from settings sync and removed from newly restored settings. Staff enter their PIN again after reopening the app. Request logs no longer include WebSocket secret URLs.
- Hub sale and stock updates now commit together. Stock rules reject missing products, insufficient stock, and expired named batches instead of swallowing failures. This is a safety improvement, not yet complete authority over prices/discounts/returns.
- Android release configuration no longer selects the debug signing identity. CI requires release keystore secrets, runs analyzer/tests, and creates draft releases.

## Verified

- ObjectBox generator completed successfully after model method changes; no schema properties changed.
- 39 domain/service/utility tests passed.
- Full analyzer gate passed with existing warnings and infos allowed. The repository still has 288 analyzer findings in the uncensored report.
- Windows and Android debug builds pass. No physical Android device is connected, and neither platform was run against a disposable database for UI verification.

## Remaining release blockers

1. Replace plaintext user PIN storage with protected credential verifiers and revocable sessions. Bearer tokens still have no expiry. Complete offline authorization and revocation behavior.
2. Replace the shared default device pairing secret, enforce authenticated TLS/WSS for LAN traffic, and remove WebSocket secrets from URLs. Existing clients still use HTTP/WS on LAN.
3. Audit every route and cloud mutation for field-level authorization. The new checks cover the highest-risk paths, but this is not a complete policy. Hub sale prices, discounts, payment splits and return limits are not yet authoritatively recalculated.
4. Inspect and deploy Firestore rules that enforce shop membership. Anonymous cloud authentication and locally selected shop IDs remain; deployed rules were unavailable during this work.
5. Encrypt backup packages, version/checksum incremental chains, test full and incremental restoration against disposable databases and crash cases, and add a recovery UI. Recovery ZIPs currently contain sensitive data and depend on OS file permissions.
6. Configure CI signing secrets and test an upgrade from existing debug-signed Android installations. Draft releases are intentionally unpublished. Windows update authenticity and rollback remain unfinished.
7. Run Windows Hub/Terminal and Android journeys with test data, including pairing, cashier permissions, offline mode, stock conflicts, backup recovery, and app restart. An Android device was not available.

Until these gates pass, this branch should not be promoted as a production security release.
