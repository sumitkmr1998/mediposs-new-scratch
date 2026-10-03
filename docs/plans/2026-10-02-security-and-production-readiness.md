# MediPoss security and production-readiness implementation plan

Date: 2 October 2026

## Objective and baseline

Address the findings in `docs/codebase-review-2026-10-02.md` while preserving Windows Hub, Windows Terminal, Android, offline stock workflows, existing databases, and recoverable backups.

Current verification baseline: 28 existing tests pass; full analysis reports 288 issues. These results are not proof of authorization, restore, or sync correctness.

This document plans implementation. No application fixes have been made as part of preparing it. Use focused changes and verification gates for each milestone. Existing uncommitted work must be preserved and reviewed before editing affected files. The October 1 sync/backup plan is background context; its implemented portions must not be blindly reapplied. Where it conflicts with this plan's safety requirements, follow this plan.

## Implementation rules

- Keep business rules in `lib/shared/`; keep Windows and Android screen implementations separate and dispatchers minimal.
- Follow `.agent/rules/architecture_rules.md`: relative internal imports; regenerate ObjectBox artifacts after model changes; verify shared changes with Windows and Android runs. An unavailable target is an explicitly incomplete verification gate.
- Test recovery and migrations against disposable copies and synthetic fixtures. Do not test destructive restore against a live clinic database.
- Take a recoverable snapshot before credential/database migrations; preserve entity UIDs and existing ObjectBox IDs. Never regenerate the schema from scratch.
- Do not log secrets, PINs, tokens, patient records, or entire credential-bearing settings.
- Keep each milestone independently reviewable. Do not combine a large screen refactor with authentication or stock correctness fixes.

## Milestone 1 — Stop freezes, unsafe writes, and destructive restore

Start here: these bounded fixes reduce immediate operational risk and provide a recovery foundation for subsequent migrations. The application is still not security-ready until Milestones 2–4 pass.

### 1A. Bounded outbox processing

Files: `lib/shared/services/sync_queue_service.dart`, `lib/shared/models/sync_queue_item.dart`; new queue tests.

1. Process a bounded snapshot of eligible items. Exclude quarantined items, stop when there is no progress, and always release the processing guard in `finally`.
2. Route decode errors, unsupported actions, photo failures, and network failures through explicit outcomes. Never mark a failed audit upload successful merely to unblock the queue.
3. Add capped exponential backoff with jitter; do not repeatedly retry failures within one pass. Expose pending and quarantined counts.
4. Keep ordering for dependent mutations: quarantine must also block or flag dependent work rather than allow a sale/photo update to overtake a required create. Unrelated entities may continue.
5. Provide explicit retry/discard controls with audit history. Discard must be an intentional user action, never automatic pruning of failed work.
6. Preserve existing `processingBy` metadata on migration. If dedicated retry fields are introduced, regenerate models and migrate existing retry/quarantine values once.

Gate: all-quarantined queue returns promptly; failed photo does not spin; malformed JSON cannot trap the queue; next pass works after failure; restart preserves pending items; retries do not duplicate a stock mutation; Hub never pushes to its own outbox.

### 1B. Safe upload and archive paths

Files: `lib/shared/services/local_server_service.dart`, `lib/shared/services/backup_restore_service.dart`; new shared path-validation helper and tests.

1. Generate media filenames on the hub; accept only validated media types and bounded payload sizes.
2. Validate normalized absolute destinations against the intended directory. Reject parent traversal, absolute/drive/UNC paths, alternate data streams, links, and platform-specific escaping names.
3. For archives, validate every entry and enforce entry-count, compressed/decompressed-size, and compression-ratio limits before extraction. Reject unsupported link entries.
4. Store archives and uploads in isolated staging directories; clean up in `finally` without following links outside staging.

Gate: test traversal using both slash styles, drive/UNC entries, duplicate archive entries, oversized payloads, malformed base64, and valid legacy backup layouts. No test writes outside its temporary fixture directory.

### 1C. Restore validation and rollback

Files: `lib/shared/services/backup_restore_service.dart`, `lib/shared/services/objectbox_service.dart`, restore UI in Windows/Android settings.

1. Require a recognized manifest or an explicit validated legacy import path. Missing/invalid metadata must never silently select a wipe-and-replace restore.
2. Parse every selected module, validate schemas/IDs/relations and required files, and produce a preview before deleting data. Distinguish missing files from deliberately empty modules.
3. Pause sync, mutations, scheduled backup, and cloud publishing during restore. Create and verify a recovery snapshot first.
4. Stage media separately; commit database changes atomically using a transaction after parsing. Coordinate media promotion using a persisted recovery journal so crash recovery can finish or roll back safely.
5. Restore relations and derived sales facts, validate consistency, reload providers, then resume services. Report partial failures accurately.

Gate: missing module, malformed JSON, invalid relation, interrupted media promotion, and simulated write failure leave the original data intact or recoverable. Full and incremental restores preserve relationships and do not trigger duplicate sync.

## Milestone 2 — Repair the hub authentication boundary

Files: `lib/shared/services/local_server_service.dart`, `lib/shared/services/hub/`, `lib/shared/services/sync_service.dart`, `lib/shared/models/app_user.dart`, `lib/shared/services/objectbox_service.dart`, onboarding and connection screens on both platforms. Introduce focused credential/token and route-authorization services.

### 2A. Separate pairing, signing, and synchronized settings

1. Generate a cryptographically random hub-only signing key; store it in OS-protected credential storage. Keep it out of ObjectBox serializers, backups intended for sharing, cloud documents, QR payloads, and client settings.
2. Provision individually revocable device credentials through a short-lived pairing code approved at the hub. A client receives its device credential, never the signing key.
3. Replace `AppSettings.toJson()` on network paths with an allowlisted sync serializer. Introduce public staff profiles that contain neither plaintext PINs nor password verifiers. Use separate explicit backup serializers.
4. Use a token protocol version. Issue short-lived user sessions (initial target: 30 minutes) with issuer, audience, expiry, stable principal ID, and session version; renew through a revocable authenticated mechanism. Device identity alone cannot authorize clinical/user writes.
5. Remove secret query parameters and redact HTTP/WebSocket logging. Authenticate WebSocket upgrades with device/session credentials appropriate to their data scope.

### 2B. Deny-by-default route permissions

1. Resolve the token principal against active hub users on every sensitive request; enforce session revocation and account status.
2. Inventory all routes and require an explicit policy. Keep only minimal health, pairing/login, and deliberately public distribution endpoints accessible before staff login.
3. Require `canManageUsers` for staff changes, `canAccessSettings` for settings, and matching clinical, inventory, sale/return, export, and deletion permissions elsewhere. Reject unauthorized writable fields.
4. Derive the audit actor from the authenticated principal. Reject attempted role elevation, unauthorized price changes, and self-granted permissions.
5. Reconcile permissions with client sync: a device needing a complete inventory cache does not automatically need complete clinical/financial caches. Design scoped pulls and clear disallowed caches on revocation.

Gate: a paired client cannot forge tokens; cashier cannot create Admin or modify settings; revoked/deactivated users are rejected; missing/expired/wrong-audience tokens fail; formerly secret-only routes require user permission; settings/profile responses and logs contain no credentials.

Compatibility gate: update Hub and clients as a coordinated protocol migration. Unsupported clients receive a clear upgrade/re-pairing response. Do not preserve an insecure legacy bypass. Retain unsent local operations for an authenticated recovery flow.

## Milestone 3 — Staff credentials, offline access, and encrypted transport

Files: auth/sync providers and services, `migration_service.dart`, `sync/pull_users.dart`, login/onboarding screens, Android manifest, credential-storage integration.

1. Remove `1234`/`xxxx` fallback authentication and automatic masked-PIN reset. New hubs require Admin credential setup; existing default credentials require reset through a controlled migration.
2. Replace plaintext PIN storage with salted verifiers using a vetted slow KDF. Add attempt throttling and lockout/backoff appropriate to short numeric PINs. Migrate existing usable PINs locally without exporting them.
3. Require an initial successful online login before enabling offline access. Cache a protected, device-bound offline authorization grant with credential verifier, permissions and expiry; never reuse a masked hub profile as a credential.
4. Default offline policy: grants expire after 24 hours, privileged staff/settings operations require online hub authorization, and cached account state is revalidated on reconnect. Local offline access cannot guarantee instant revocation while disconnected; document that limitation clearly.
5. Replace saved auto-login PINs with protected, revocable session credentials. Sign out when account state or allowed device scope changes.
6. Move LAN transport to HTTPS/WSS. Pair the client to the hub certificate/key and define renewal and re-pairing behavior; reject certificate changes rather than disable validation. Preserve authenticated tunnel support separately.
7. Disable broad Android cleartext traffic after transport migration. Verify discovery, foreground/background sync, Windows Terminal, Android, and Wear client behavior.

Gate: default/masked PINs cannot log in; inactive users fail; offline grants expire; clock rollback cannot extend grants indefinitely; credential reset invalidates old grants on reconnect; network traffic carries no plaintext credentials; changed hub certificates fail safely.

## Milestone 4 — Cloud isolation and protected backups

Files: `firebase_sync_service.dart`, `subscription_service.dart`, Firebase project configuration/rules and emulator tests, Drive/backup/settings services.

1. Obtain and review deployed rules before asserting cloud isolation. Define server-controlled shop membership and roles using verified identities or backend-minted claims. Anonymous authentication and a user-entered shop ID cannot establish membership.
2. Default-deny cross-shop reads/writes. Validate entity fields and allowable queue actions; device identifiers and claimed actors are untrusted input. Apply equivalent authorization when the hub replays cloud mutations.
3. Remove credential-bearing profiles/settings from cloud broadcasts and define clinical-data access/retention. Verify failed authentication never downgrades requests into public access.
4. Protect backup packages with authenticated encryption; put tokens/signing keys outside ordinary backups. Establish a user-held recovery-key/export procedure before enabling encrypted backup by default.
5. Version manifests; include shop identity, schema version, package ID, checksums, full-baseline ID and predecessor ID. Maintain deletion tombstones and stable entity identifiers for incremental replay.
6. Preserve a complete baseline-plus-delta chain during retention; verify uploaded packages before advancing the backup watermark. Local backup success and Drive upload success are separate states.

Gate: emulator tests deny another shop even to authenticated users; arbitrary anonymous accounts cannot access shop data; unauthorized cloud operations fail on hub replay; encrypted backup round-trips; missing/corrupt/out-of-order deltas are rejected; deletions replay once; retention never removes a required baseline.

External configuration: cloud rule deployment and any identity/backend configuration are rollout work after local tests. They are not assumed completed merely because files exist.

## Milestone 5 — Authoritative sale and stock commits

Files: `local_server_service.dart`, `hub/sales_routes.dart`, `shared/domain/stock_rules.dart`, `sale_calculator.dart`, cart/sales/warehouse providers; new transaction service and integration tests.

1. Validate quantities, prices, discounts, tax inputs, payment splits, batch ownership/expiry, available stock, return limits and permissions before writing. Recompute totals at the authority using an explicit money/rounding policy.
2. Use stable operation IDs plus entity revisions for idempotent retries and conflict detection. Record acknowledgement in the same transaction as the mutation.
3. Commit sale, stock movement and related records atomically. Exceptions and unsatisfied quantities must return an explicit failure; emit broadcasts only after commit.
4. For returns/edits, reference the original sale and batch allocations rather than restoring into an arbitrary/latest batch.
5. Handle offline overselling through visible reconciliation: do not silently clamp or change the sale. Keep rejected/conflicting transactions available for an authorized resolution.

Gate: duplicate delivery deducts stock once; concurrent devices cannot silently oversell; insufficient/expired stock is rejected; malformed items change nothing; edits/returns preserve original allocations; payment totals and printed amounts agree; interruption cannot leave half a sale.

## Milestone 6 — Release gates and product polish

1. Configure production Android signing with protected CI credentials and key-recovery documentation. Verify upgrade compatibility; debug-signed existing installs may require a managed migration that preserves local pending data.
2. Verify Windows update signatures with an application-trusted key, download to staging, validate before replacing files, and support rollback. A checksum fetched from the same untrusted channel is not sufficient authenticity verification.
3. Add analyzer/tests to pull-request and release workflows; pin a tested Flutter version. Block new errors and relevant warnings initially, then reduce the 288-issue baseline. Prioritize asynchronous screen-context misuse.
4. Add actual reconciliation-service tests rather than arithmetic-only examples, API permission tests, restore/queue integration tests, and device smoke journeys.
5. Split the server, sync engine, and analytics screens by responsibility in later focused changes. Reuse existing shared UI components without combining platform screen implementations.
6. Show actionable pending/quarantine/sync/backup status, restore previews, progress and recovery errors. Verify keyboard/scanner focus on Windows and large text/touch behavior on Android.
7. Replace the starter README with setup, pairing, roles, offline policy, cloud configuration, backup recovery, release signing and troubleshooting instructions. Separate personal database inspection tools from automated tests.

Gate: signed upgrade tested with a populated disposable database; Windows and Android checkout/pairing/offline/reconnect/backup smoke tests pass; release workflow blocks failures; no credentials appear in diagnostics.

## Rollout and completion criteria

For each milestone: run focused tests, applicable analyzer checks, and the existing domain/service/utils suite; regenerate and validate models when changed; complete Windows Hub/Terminal and Android verification for shared changes. Build success does not substitute for required device runs.

Pilot with a disposable cloned shop dataset before deploying to real stores. Record migration version, verify a recovery backup, drain or preserve pending work, upgrade the hub and clients together, rotate compromised/shared credentials, and verify expected permissions. Rollback must restore the matching database and application version without bringing back known shared-secret vulnerabilities.

Complete only when critical/high findings have verified fixes, cloud authorization is tested and deployed, credentials are absent from sync/logs, stock/restore/queue failure tests pass, signing and recovery are verified, and both supported platform journeys have evidence. Any unavailable device or external cloud/signing step remains an explicit release blocker.

The first implementation batch is Milestone 1A–1C: bounded queue processing, path containment, and validated recoverable restore. Authentication redesign follows immediately; visual polish comes after these gates.
