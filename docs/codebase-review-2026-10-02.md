# MediPoss codebase review

Reviewed: 2 October 2026. Scope: current working tree, including existing uncommitted changes. Application code was not changed by this review.

## Assessment

MediPoss has a useful foundation: shared Flutter logic with separate Windows and Android screens, ObjectBox persistence, batch-aware inventory, pure stock and transfer rules, a durable client outbox, and paginated exports. It is a substantial application rather than a starter project.

However, the authentication boundary, permissions, file handling, sync failure handling, and restore safety need significant work. I would not approve this build for broader production deployment with real patient data until the critical and high-priority findings below are addressed. Cosmetic polish should follow security and data integrity fixes.

## Verification and limits

- `flutter test --no-pub test/domain test/services test/utils`: **28 tests passed**.
- `flutter analyze --no-pub`: **288 issues**, exit code 1. Examples include unused code, deprecated API calls, and `use_build_context_synchronously` findings across screens.
- Read the authentication, server routes, sync/outbox, Firebase integration, backup/restore, update and release configuration, domain rules, and representative screen/test code.
- This is a source review, not a live penetration test. No production database was opened, no live Firebase data was queried, and no exploit was sent to a running hub. Findings described as confirmed mean the relevant source path is present; deployment exploitability depends on reachability and configuration.
- No deployed Firestore rules were available. Cloud tenant isolation remains unverified.
- This is not a complete dependency advisory audit. The resolved JWT dependency is 2.17.0, despite the lower bound in pubspec.yaml. No dependency CVE is asserted in this report.
- Visual appearance and device behavior were not verified by running Windows/Android UI journeys.

## Security findings

### S1 — Critical: paired clients receive the JWT signing key

Evidence: `lib/shared/services/local_server_service.dart:212`, `:290`, `:498`, `:2467`; `lib/shared/models/app_user.dart:399`, `:451`.

The global middleware requires the hub secret from `X-MediPass-Secret` or a query parameter. The same value signs and verifies JWTs. Every paired client therefore possesses the signing key and can create its own accepted bearer token. The settings constructor uses a fixed default secret; initialization creates those default settings, and no random provisioning path was found. `/api/settings` also serializes the signing key back to any accepted token holder.

Fix: separate device pairing credentials from user authentication. Keep the signing key exclusively on the hub, generate installation-specific secrets, rotate existing credentials, and strip secrets from sync responses. Asymmetric token signing is one option when clients need to verify tokens without signing them.

### S2 — High: hub APIs do not enforce staff permissions

Evidence: `lib/shared/services/local_server_service.dart:466`, `:2467`.

`_withAuth` only verifies the token signature. It discards the decoded identity and does not load an active user or enforce permissions. `/api/users/push` accepts role, PIN, and permission fields from the request and creates or replaces users by name. A token holder can submit an administrator profile without `canManageUsers`. Other routes similarly expose patient, financial, and inventory data or changes without their corresponding permission checks.

Fix: resolve the authenticated principal on the hub, reject inactive/deleted accounts, apply an explicit permission to each route, and restrict writable fields. Audit changes using the authenticated principal, never a client-supplied actor.

### S3 — High: sensitive routes need only the device secret

Evidence: `lib/shared/services/local_server_service.dart:89`–`:94`, `:1387`, `:1425`, `:1619`.

Doctor write/delete routes, patient/medicine/prescription delete routes, and prescription reads omit `_withAuth`. They are covered by the global shared-secret middleware, so these are **not completely unauthenticated routes**. Nevertheless, a paired device can read prescriptions or delete records without staff login or individual permissions.

Fix: protect every sensitive route with both user authentication and the required permission. Reserve pre-login access for a deliberately minimal pairing/login surface.

### S4 — High: fixed offline PIN fallback bypasses individual credentials

Evidence: `lib/shared/services/sync_service.dart:249`–`:273`; `lib/shared/services/local_server_service.dart:324`–`:333`; `lib/shared/services/objectbox_service.dart:115`–`:149`.

User pulls mask PINs as `xxxx`, but offline/cloud login accepts `1234` for those profiles. It also accepts literal `xxxx` through the direct equality branch. This path does not check `isActive`. Desktop initialization replaces masked PINs with `1234`, and an empty database seeds an Admin account with that PIN. A synced profile can therefore gain access through a known shared fallback rather than its actual credential.

Fix: remove fallback credentials; require first-run admin setup. Implement an explicit offline authorization policy using a protected local credential verifier and expiry, with account-status checks.

### S5 — High: settings responses disclose Google credentials and saved PINs

Evidence: `lib/shared/services/local_server_service.dart:498`; `lib/shared/models/app_user.dart:451`–`:467`; `lib/shared/providers/settings_provider.dart:72`.

The settings response uses the storage serializer, which includes `googleAuthData`, `autoLoginPin`, and `jwtSecret`. Google access credentials are persisted in `googleAuthData`. If Drive is linked, a permitted settings request exposes those credentials to a connected client. Backups export the same settings and raw user PINs into an ordinary ZIP.

Fix: separate persistence, public sync, and backup serializers. Store tokens in platform-protected credential storage. Exclude credentials from ordinary sync and protect sensitive backup contents with authenticated encryption and a defined key-recovery policy.

### S6 — High: prescription photo upload permits path traversal

Evidence: `lib/shared/services/local_server_service.dart:2245`–`:2260`.

The request's filename is directly appended to `prescription_photos` and written without containment validation. Parent-directory components can escape the intended photo folder and overwrite a writable file. This endpoint requires the device secret and a bearer token, subject to S1/S2.

Fix: generate filenames on the hub, validate media format and size, normalize the destination, and require it to remain inside the intended directory. Do not trust filenames supplied by a client.

### S7 — High: backup archive extraction permits path traversal

Evidence: `lib/shared/services/backup_restore_service.dart:221`–`:231`.

Archive entry names are joined to the staging directory and written directly. A malicious archive with parent-directory or escaping paths can write outside staging when the user imports it. The custom extraction loop does not perform path containment checks. The archive is also fully decoded in memory without a visible decompressed-size budget.

Fix: validate each entry before any write; reject escaping paths, unsupported links, excessive entry counts, and excessive decompressed sizes. Validate an entire package before changing application data.

### S8 — High: LAN sync sends credentials and patient data without encryption

Evidence: `lib/shared/services/sync_service.dart:134`, `:2935`; `android/app/src/main/AndroidManifest.xml:16`; `lib/shared/services/local_server_service.dart:138`.

The LAN transport uses HTTP and WebSocket rather than HTTPS/WSS, and Android enables cleartext traffic. The hub secret, PIN login requests, bearer tokens, and clinical data travel over this transport. The WebSocket URL also embeds the secret in a query string, while server request logging is enabled.

Fix: use authenticated encrypted transport with a documented local pairing/trust mechanism. Stop placing secrets in URLs and redact sensitive request details.

### S9 — Medium: indefinite tokens and plaintext authentication data

Evidence: `lib/shared/services/local_server_service.dart:275`–`:291`; `lib/shared/models/app_user.dart:15`; `lib/shared/providers/auth_provider.dart:110`.

Login explicitly logs the attempted PIN. PINs are stored and compared as plaintext. Issued JWTs do not specify an expiry, and verification does not re-check whether the user is active. No login throttling was found on this path. A stolen token can remain usable after staff deactivation unless the signing key changes.

Fix: use salted password/PIN verifiers with an appropriate slow KDF, rate limiting, finite sessions, revocation/account re-checks, and credential-redacted logs. Short numeric PINs need particularly careful attempt controls.

### S10 — Medium: Android releases use debug signing

Evidence: `android/app/build.gradle.kts:39`; `.github/workflows/release.yml`.

The release build explicitly selects the debug signing configuration, and the release workflow builds that configuration. This lacks a managed production signing identity and undermines a reliable upgrade/distribution process.

Fix: configure a protected release keystore and CI secrets, document signing-key recovery, and verify update compatibility. Windows updates also deserve signature verification, staged installation, and rollback before overwriting installed files.

### Cloud isolation — high-priority verification gap

Evidence: `lib/shared/services/firebase_sync_service.dart:36`, `:56`, `:193`, `:217`.

Firebase authentication uses anonymous accounts while document paths derive from a locally selected shop ID. That code does not itself prove access to another shop is possible: deployed Firestore rules determine authorization. No rules file or emulator authorization tests were found. A rule checking only that authentication exists would not establish shop membership.

Review deployed rules, establish server-controlled shop membership and role claims, and test cross-shop read/write denial. Firebase explicitly distinguishes authentication from authorization in its [security guidance](https://firebase.google.com/docs/rules/insecure-rules) and [Firestore security overview](https://firebase.google.com/docs/firestore/security/overview).

## Reliability and data-integrity findings

### R1 — High: quarantined outbox entries cause an endless loop

Evidence: `lib/shared/services/sync_queue_service.dart:74`–`:133`.

The outer loop repeatedly fetches all unprocessed items. Quarantined items are skipped but remain unprocessed. Once only quarantined items remain, the list never becomes empty and the loop has no exit or awaited push. This can spin on the UI isolate, leave `_isProcessing` set, and prevent future queue work. Failed photo items are also left eligible for immediate repeated processing.

Fix: query only eligible items, end a processing pass when no progress occurs, bound work per pass, and schedule retries with backoff. Make quarantine visible and recoverable to users. Add tests for all-quarantined queues, failed photos, mixed failure/success, and restart recovery.

### R2 — High: restore deletes live records before validating replacements

Evidence: `lib/shared/services/backup_restore_service.dart:237`–`:245`, `:351`–`:445`.

Full restore removes existing records before parsing their replacement files. Missing files become empty lists; a missing or unreadable manifest defaults to a full restore. An incomplete ZIP can silently clear selected modules. A later decoding or media-copy error can leave a partially restored database. There is no transaction around the full restore sequence.

Fix: require a valid manifest and all selected module files, parse and validate everything first, take a recovery snapshot, and restore into a separate database or a transaction with rollback. Coordinate media replacement and pause sync throughout the operation.

### R3 — High: hub accepts sale totals without authoritative validation

Evidence: `lib/shared/services/local_server_service.dart:992`–`:1082`; `lib/shared/domain/stock_rules.dart:83`–`:179`.

The hub accepts supplied totals, discounts, payment amounts, and item JSON. It stores the sale separately from stock deduction, and stock-rule errors are caught and logged rather than returned to the caller. Unsatisfied remaining stock quantities are not rejected. A malformed or inconsistent sale can be acknowledged successfully while inventory remains incorrect. Exact-batch deduction also lacks the expiry check used by the fallback loop.

Fix: validate the complete sale on the hub, recompute amounts from approved prices and permissions, enforce stock/expiry and return rules, and commit sale plus stock atomically. Test insufficient stock, expired exact batches, malformed items, duplicate retries, and concurrent devices.

## What polish is required

1. **Security and recovery first.** Address S1–S8 and R1–R3 before expanding real-world access. Deploy testable Firestore rules and production signing.
2. **Make sync status actionable.** Show pending count, last successful sync, failure reason, quarantined entries, retry controls, and which device is authoritative. Backup/restore needs progress, validation feedback, and recovery messaging.
3. **Break up large files.** Android analytics is 4,156 lines, the local server is 3,217, and sync is 3,087. Extend the existing extracted routes/helpers into focused services with a central authorization layer. Preserve platform-specific screen layouts while sharing business rules.
4. **Resolve consequential analyzer findings first.** Fix screen-context access after asynchronous gaps, then unused code and deprecated calls. These findings deserve more attention than cosmetic lint churn.
5. **Strengthen tests at actual boundaries.** Current tests cover useful arithmetic, stock rules, and serialization. The clinic reconciliation tests use hand-written arithmetic without importing the reconciliation service; they cannot establish service correctness. Add API permission tests, queue/restore integration tests, cloud isolation tests, and Windows/Android checkout journeys.
6. **Add release gates.** The current workflow builds and publishes without analyzer or test steps. Require checks before releases, pin a tested Flutter version, and validate backup and migration compatibility.
7. **Improve UI consistency through device testing.** Reuse existing page/action/status components; verify keyboard navigation and scanner focus on Windows, touch targets and large text on Android, validation, loading states, and empty/error states. This is a polish recommendation, not a claim about unobserved rendered screens.
8. **Replace the starter README.** Document setup, hub/client pairing, offline behavior, role permissions, cloud provisioning, backup recovery, signing, and support diagnostics. Move scripts that inspect personal application databases from `test/` to an explicit diagnostics area with configurable paths.
9. **Review financial representation.** Monetary values use doubles; plan integer minor units or decimal arithmetic with an explicit rounding policy. Keep tax, discount, and receipt rounding consistent at the hub and clients.

## Recommended implementation order

First: redesign authentication and enforce permissions; remove fixed credential fallbacks and credential serialization. Second: contain all file writes, validate restores, and repair the queue loop. Third: make sale/stock commits atomic, establish cloud tenant rules and release signing, and add boundary tests. Finally: improve sync/recovery UX, reduce large-file complexity, clean analyzer findings, and perform device-based visual polish.
