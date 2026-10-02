# Sync Queue & Incremental Backup Overhaul Implementation Plan

> **For Antigravity:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the sync queue into a resilient, fault-tolerant, auto-purging queue (resolving poison pills, missing entities, and deletion ID risks across Hub, Terminal, and Android) and build a production-grade automated daily incremental backup engine (local disk + Google Drive).

**Architecture:** 
- **Sync Queue:** Outbox queue on clients (Android & Windows Terminal) with per-item retry limits and dead-letter quarantine (preventing head-of-line blocking), full coverage for all entities/actions (`user`, `settings`, `sale update`, `procedure_record`), entity-safe natural-key deletions for `Doctor` and `Prescription`, Hub auto-sync guards, and 24-hour processed-item pruning.
- **Incremental Daily Backup:** Calendar-day scheduled automated backup engine in `SettingsProvider` decoupled from cloud status (guaranteeing local daily backups), generating daily incremental delta packages (`mediposs_delta_YYYY-MM-DD.zip`) containing only modified entities and new photos since the last baseline/backup, alongside weekly full snapshots (`mediposs_full_YYYY-MM-DD.zip`), with retention pruning and seamless upload to Google Drive with refreshed credentials.

**Tech Stack:** Flutter / Dart, ObjectBox NoSQL, Shelf HTTP & WebSockets, Google Drive v3 API, Archive (Zip), Path Provider.

---

### Task 1: Fix `SyncQueueService` Poison Pill, Retry Count, & Missing Entity Handlers

**Files:**
- Modify: `lib/shared/services/sync_queue_service.dart`
- Reference: `lib/shared/models/sync_queue_item.dart`
- Reference: `lib/shared/services/sync_service.dart`

**Step 1: Inspect and Add In-Place Retry Tracking & Quarantine to `SyncQueueItem`**
- In `SyncQueueItem`, use `processingBy` to store retry metadata (e.g., `retries:N:last_error`) without requiring a schema break or build_runner regeneration.
- Provide helper getters/methods on `SyncQueueItem` or in `SyncQueueService`:
  - `int get retryCount` (parse from `processingBy`)
  - `void recordFailure(String error)`: increment retry counter and record error.
  - Max retries threshold: 5. When `retryCount >= 5`, mark item as quarantined (`quarantined = true` or `processingBy = 'quarantined:error'`), log to `debugPrint` and `AuditService`, and proceed to the next item instead of blocking the entire queue with `break;`!

**Step 2: Add Missing Entity & Action Handlers to `_pushItem`**
- `case 'sale'`:
  - Handle `action == 'update'` (call `syncService.pushSale(Sale.fromJson(data))` which handles Hub upsert/inventory deduplication).
- `case 'user'`:
  - Add `case 'user': return await syncService.pushUser(AppUser.fromJson(data));`
- `case 'settings'`:
  - Add `case 'settings': return await syncService.pushSettings(AppSettings.fromJson(data));`
- `case 'procedure_record'`:
  - Add `case 'procedure_record': return await syncService.pushProcedureRecord(ProcedureRecord.fromJson(data));`

**Step 3: Add Processed Queue Pruning**
- In `SyncQueueService.processQueue()`, add `_pruneProcessedItems()`:
  - Query items where `processed == true`.
  - If processed item timestamp is older than 24 hours (or immediately on success if no dependent audit), remove it from `syncQueueBox` in batches to keep `data.mdb` compact.

**Step 4: Guard Windows Hub from Client Outbox Auto-Sync**
- In `SyncQueueService.init()`:
  - If `SyncService.instance.isHub` is true, do not start `_syncTimer`. Hub is the master server, not an outbox client.

---

### Task 2: Fix Safe Entity Identifiers on LocalServerService & SyncService

**Files:**
- Modify: `lib/shared/services/local_server_service.dart`
- Modify: `lib/shared/services/sync_service.dart`
- Modify: `lib/shared/providers/opd_provider.dart`
- Modify: `lib/shared/providers/prescription_provider.dart`

**Step 1: Fix Doctor Deletion on Hub & Client**
- In `local_server_service.dart`: Update `_doctorsDeleteHandler` to accept `name` as well as `id`. Query `Doctor_.name.equals(name)` first to ensure the exact matching doctor is removed, avoiding local synthetic ObjectBox ID collision.
- In `sync_service.dart`: Update `pushDoctorDelete(int id, String name)` to pass `{'id': id, 'name': name}`.
- In `sync_queue_service.dart`: Pass doctor name and id in `pushDoctorDelete`.

**Step 2: Fix Prescription Deletion on Hub & Client**
- In `local_server_service.dart`: Update `_prescriptionsDeleteHandler` to accept `patientUhid` + `createdAt` / `id` to resolve the exact prescription on Hub.
- In `sync_service.dart`: Update `pushPrescriptionDelete` to include `patientUhid` and `createdAt`.

**Step 3: Implement `ProcedureRecord` Endpoint on LocalServerService**
- Add router endpoints:
  - `router.get('/api/procedure-records', _withAuth(_procedureRecordsGetHandler));`
  - `router.post('/api/procedure-records/push', _withAuth(_procedureRecordsPushHandler));`
- Implement handlers to save `ProcedureRecord` into Hub's `procedureRecordBox` and broadcast `'procedures_updated'`.
- In `sync_service.dart`: Add `pushProcedureRecord(ProcedureRecord r)`.

---

### Task 3: Overhaul Backup & Restore Service for Daily Incremental Delta Backups

**Files:**
- Modify: `lib/shared/services/backup_restore_service.dart`
- Modify: `lib/shared/services/google_drive_service.dart`

**Step 1: Add Incremental Export Method in `BackupRestoreService`**
- Create `exportIncrementalBackup({DateTime? since})`:
  - When `since == null`, create a full baseline backup.
  - When `since != null`:
    - Filter each box by `updatedAt > since` or `createdAt > since` (e.g. Sales, Patients, Medicines, Appointments, Prescriptions, Purchases, Attendance, etc.).
    - Only export modified entities into delta files (`medicine.json`, `sale.json`, etc.).
    - Filter media files (`patient_photos`, `prescriptions`) by file modification date `stat.modified.isAfter(since)`.
    - Include a `manifest.json` with metadata:
      ```json
      {
        "type": "incremental",
        "timestamp": "2026-10-01T23:30:00",
        "since": "2026-09-30T23:30:00",
        "counts": { "sales": 14, "medicines": 3, "patients": 5 }
      }
      ```
    - Pack into `mediposs_delta_YYYYMMDD_HHmmss.zip`.

**Step 2: Add Incremental Restore / Replay in `BackupRestoreService`**
- Support importing both baseline and delta backups:
  - If archive contains `manifest.json` with `"type": "incremental"`, perform upsert without clearing existing records!
  - Match entities by natural keys (`barcode`/`name` for medicines, `uhid` for patients, `invoiceNo` for sales) and update/insert records cleanly.

**Step 3: Update `GoogleDriveService` for Daily Incremental Uploads & Folder Organization**
- In `google_drive_service.dart`:
  - Organize Google Drive files under `MediPoss Backups/daily/` and `MediPoss Backups/full/`.
  - Add `uploadIncrementalBackup({DateTime? since})`:
    - Generates local incremental zip.
    - Saves offline copy in local `backups/daily/`.
    - If Google Drive is connected, uploads file with metadata tag `type: incremental`.
    - Auto-prunes local and cloud daily files older than retention policy (default: 14 days) while keeping weekly baselines.

---

### Task 4: Fix Automatic Daily Scheduling & Decouple Local Auto-Backup in `SettingsProvider`

**Files:**
- Modify: `lib/shared/providers/settings_provider.dart`
- Modify: `lib/screens/windows/app_shell_windows.dart`

**Step 1: Fix Daily Math Bug & Decouple from Google Drive**
- In `SettingsProvider.checkAndPerformAutoBackup(String trigger)`:
  - Remove the early return `if (!_settings.googleDriveSyncEnabled) return;`.
  - Fix daily check using calendar date boundaries:
    ```dart
    final isDifferentDay = last.year != now.year || last.month != now.month || last.day != now.day;
    if (isDifferentDay && isPastScheduledTime) shouldBackup = true;
    ```
  - If `trigger == 'Periodic'` and `isDifferentDay && isPastScheduledTime`, allow backup to run even if `autoBackupLogic` was set to `'At Startup'` or `'On Close'` (safety fallback so machines that stay on 24/7 don't skip days).
  - Execute local backup ALWAYS.
  - If `googleDriveSyncEnabled` is true and Drive is linked, upload to Google Drive.

**Step 2: Wire Incremental Logic into Auto-Backup**
- If last full backup was within 7 days, generate and upload an **Incremental Daily Backup** (`uploadIncrementalBackup(since: lastBackupTime)`).
- If it has been more than 7 days (or no backup exists), generate a **Full Baseline Backup**.

---

### Task 5: End-to-End Verification & Static Analysis

**Files:**
- Run `flutter analyze` on touched files.
- Verify no regressions or compiler errors.
- Verify safe operation with existing background Windows Flutter instance.
