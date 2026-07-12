
# MediPoss Implementation Plan

**Product:** MediPoss — medical store POS (Windows hub + Android client + OPD + dual warehouse)  
**Branch context:** `v1-maintenance`  
**Goal:** Reduce structural bloat and risk without a rewrite — modularize UI, share business logic, clarify sync, protect money/stock with tests.

**Status legend:** `[ ]` todo · `[~]` in progress · `[x]` done

---

## 0. Principles

1. **No big-bang rewrite** — incremental PRs, one god file or one domain slice at a time.
2. **Move first, refactor later** — extract structure before clever redesigns.
3. **No behavior change** unless the PR title says otherwise (bugfix / intentional change).
4. **Money and stock first** — extract and test sale/inventory rules before cosmetic UI work.
5. **Leave `build/` alone** for local disk cleanup; do not commit or rely on cleaning build as part of feature work.
6. **Platform UIs stay thin** — Android/Windows differ in layout only; domain rules live once.

---

## 1. Workspace hygiene

### 1.1 Already done

| Item | Status |
|------|--------|
| Leave root `build/` untouched | `[x]` |
| Delete `firebase_cpp_sdk_windows_13.5.0.zip` | `[x]` |
| Delete `mediposs-windows-v1-stable.zip` | `[x]` |
| Delete `mediposs_windows_v1.zip` | `[x]` |
| Delete `firebase_cpp_sdk_windows/` | `[x]` |
| Remove nested `mediposs_analysis/` (~3.8 GB) | `[x]` |
| Keep `objectbox.dll` (runtime native lib) | `[x]` |

### 1.2 Optional later (not required)

- [ ] Add/confirm `.gitignore` covers: `*.zip`, release APKs, `backup_debug_log.txt`, `flutter_0*.log`, `flutter_0*.png`, `nul`
- [ ] Document in README that `build/` is local-only and can be regenerated via `flutter build`
- [ ] Remove other root clutter if unused (`ui_changes.patch`, old screenshots) only after confirming nothing needs them

---

## 2. Split god screens

**Goal:** No feature UI file permanently above ~600 lines. Easier review, less merge pain, safer edits.

### 2.1 Target layout (Windows warehouse — template for others)

```
lib/screens/windows/warehouse/
  warehouse_windows.dart       # shell + tab routing only (~150 LOC)
  tabs/
    inventory_tab.dart
    transfers_tab.dart
    purchases_tab.dart
    bulk_ops_tab.dart          # only if bulk UI is distinct
  dialogs/
    transfer_dialog.dart
    purchase_dialog.dart
    batch_details_dialog.dart
    delete_confirm.dart
    excel_import_flow.dart
  widgets/
    medicine_row.dart
    location_badge.dart
    qty_fields.dart
    stock_data_table.dart
```

Empty folders under `lib/screens/windows/warehouse/{dialogs,tabs,widgets}` already exist — use them.

### 2.2 Priority order

| Priority | File (approx LOC) | Split into |
|----------|-------------------|------------|
| P0 | `warehouse_windows.dart` (~3986) | tabs + dialogs + widgets (above) |
| P0 | `pos_windows.dart` (~2513) | cart panel, payment sheet, barcode entry, medicine search |
| P0 | `pos_android.dart` (~1485) | same slices as Windows POS |
| P1 | `analysis_hub_screen.dart` (~2917) | KPI block, charts, filters, report tables |
| P1 | `analysis_hub_android.dart` (~2141) | same as Windows analysis |
| P1 | `settings_windows.dart` (~2386) | shop, sync, backup, OTA, display sections |
| P1 | `settings_android.dart` (~1342) | same sections |
| P2 | `local_server_service.dart` (~2457) | hub routes by domain (see §4) |
| P2 | `sync_service.dart` (~2410) | connection vs pull vs push (see §4) |
| P2 | Other screens ≥1000 LOC | same pattern as above |

### 2.3 Rules for every split PR

1. Cut/paste into new files; keep public widget names and navigation entry points stable.
2. One primary god file per PR.
3. Run `flutter analyze` on touched paths.
4. Manual smoke: open the screen, exercise main actions once on target platform.
5. Do **not** mix domain extraction and UI split in the same PR unless the slice is tiny.

### 2.4 Tasks

- [x] **2.A** Split `warehouse_windows.dart` into tabs/dialogs/widgets; shell becomes thin
- [x] **2.B** Split `pos_windows.dart` into cart / pay / search / barcode widgets
- [x] **2.C** Split `pos_android.dart` to match POS structure (layout only)
- [x] **2.D** Split analysis hub (Windows then Android)
- [x] **2.E** Split settings (Windows then Android)
- [x] **2.F** Re-measure: list remaining files ≥1000 LOC; schedule next PR

### 2.5 Done when

- Top P0/P1 screens are modular
- Warehouse and POS changes can land without multi-thousand-line diffs
- No incomplete empty folder shells left without owners

---

## 3. Extract shared screen logic

**Goal:** Business rules live once. Android/Windows screens only build UI and bind to shared controllers/domain.

### 3.1 Target structure

```
lib/shared/
  domain/                 # pure Dart — unit-testable, no Flutter widgets
    sale_calculator.dart
    stock_rules.dart
    transfer_rules.dart
  controllers/            # or view_models/ — screen orchestration
    pos_controller.dart
    warehouse_controller.dart
    sales_history_controller.dart
    prescription_controller.dart
  providers/              # existing — app-wide data
  services/               # existing — IO, network, DB
```

### 3.2 Layer responsibilities

| Layer | Owns | Must not own |
|-------|------|----------------|
| **Domain** | Totals, tax, discount, stock deduct/revert, transfer eligibility | Widgets, HTTP, ObjectBox |
| **Controller** | Search query, selection, loading/error flags; calls providers + domain | Platform-specific layout |
| **Provider** | Cached entity lists, app-wide notify | Pixel layout |
| **Platform screen** | Scaffold, density, tables vs lists | Formulas and stock math |

### 3.3 Example: POS

```dart
// shared/domain/sale_calculator.dart
class SaleCalculator {
  static double lineTotal(...) => ...;
  static SaleTotals compute(List<CartLine> lines, double taxRate) => ...;
}

// shared/controllers/pos_controller.dart
class PosController extends ChangeNotifier {
  // add/remove lines, validate stock, checkout orchestration
}

// screens/windows/pos_windows.dart  → desktop UI bound to PosController
// screens/android/pos_android.dart  → mobile UI bound to same controller
```

### 3.4 Migration order (safe)

1. Extract pure **sale totals** → `domain/sale_calculator.dart` + tests (§5)
2. Extract **stock deduct/revert** → `domain/stock_rules.dart` (pull logic out of hub handlers)
3. Extract **transfer validation** → `domain/transfer_rules.dart`
4. Introduce `PosController`; wire Windows POS then Android POS
5. Introduce `WarehouseController` for shared ops (transfer, purchase apply)
6. Only then consider adaptive single-UI (optional, not required)

### 3.5 Anti-patterns

- Shared widgets that are 80% `if (Platform.isWindows)` — prefer shared **logic**, separate **layout**
- Dumping UI into providers
- One mega-controller for the whole app — one controller per major flow

### 3.6 Tasks

- [x] **3.A** Create `lib/shared/domain/` + `sale_calculator.dart` from POS total logic
- [x] **3.B** Create `stock_rules.dart` from hub `_deductHubInventory` / `_revertHubInventory` (and client mirrors)
- [x] **3.C** Create `transfer_rules.dart` from warehouse transfer validation
- [x] **3.D** Add `PosController`; both POS screens use it (Architected via `CartProvider`)
- [x] **3.E** Add `WarehouseController` for shared warehouse ops (Architected via `WarehouseProvider`)
- [x] **3.F** Audit: no duplicated total/stock formulas left in platform UI files

### 3.7 Done when

- Sale and stock math exist in one place and are used by both platforms
- Platform files are mostly `build()` + navigation + binding
- New feature = domain (+ controller) + two thin UIs

---

## 4. One sync story

**Goal:** One mental model for data movement; single UI-facing API; safer offline and cloud modes.

### 4.1 Current pieces (as-is)

| Component | Role |
|-----------|------|
| ObjectBox | Local source of truth |
| `LocalServerService` | Windows hub: HTTP + WebSocket, inventory side-effects on sale push |
| `SyncService` | Client connect, JWT, pull/push, reconnect, cloud mode |
| `SyncQueueService` | Offline queue when hub unreachable |
| `FirebaseSyncService` | Cloud / multi-shop path |
| `BackgroundSyncService` | Android background drain/sync |
| `DiscoveryService` | LAN hub discovery |
| `CloudflareService` | Remote reachability / tunnel support |

### 4.2 Target model

```
                 ┌─────────────────┐
                 │    ObjectBox     │  always local truth
                 └────────┬────────┘
                          │
      ┌───────────────────┼───────────────────┐
      ▼                   ▼                   ▼
 LAN Hub path       Offline queue        Cloud path
 (hub + SyncService) (queue → drain)   (Firebase when cloud mode)
```

### 4.3 Documented rules (write into `SYNC.md` or expand `CLOUD_SYNC_PLAN.md`)

1. **Hub role:** Only Windows with server started; Android is client (or pure cloud client).
2. **Write path:** Local write → ObjectBox → push or enqueue → ack → mark clean.
3. **Read path:** UI always reads ObjectBox; network pull only merges into local.
4. **Conflict policy:** Explicit (e.g. last-write-wins by `updatedAt`, or hub wins for stock).
5. **Cloud vs LAN:** Exclusive modes; no dual-push of same sale without idempotency keys.
6. **Background:** Queue drain / light pull only; document ObjectBox single-writer / stop-service-on-main behavior.

### 4.4 Target code layout

```
lib/shared/services/sync/
  sync_facade.dart              # only public API for UI
  connection_manager.dart       # IP, JWT, WS, reconnect
  entity_pullers/               # medicines, sales, patients, ...
  entity_pushers/
  cloud_sync_adapter.dart
  queue_drain.dart

lib/shared/services/hub/
  hub_server.dart               # start/stop, router mount
  routes/sales_routes.dart
  routes/medicine_routes.dart
  routes/patient_routes.dart
  routes/... 
  inventory_effects.dart        # deduct/revert — uses domain/stock_rules
```

### 4.5 Phases

| Phase | Work | Risk |
|-------|------|------|
| 4a | Write `SYNC.md` (modes, entities, conflicts, sequences) | None |
| 4b | Add `SyncFacade` that only delegates to existing services | Low |
| 4c | Point UI at facade; stop scattering direct `SyncService` pulls | Low |
| 4d | Split pull/push files; keep method signatures | Medium |
| 4e | Idempotent sale push (invoiceNo / uuid) on hub + client | Medium–high |
| 4f | Unified `SyncStatus { mode, connected, queueDepth, lastError }` for UI | Low |

### 4.6 Tasks

- [x] **4.A** Author `SYNC.md` from current behavior (LAN, queue, cloud, background)
- [x] **4.B** Implement `SyncFacade` (delegate-only)
- [x] **4.C** Migrate app shell / settings / POS sync triggers to facade
- [ ] **4.D** Split `sync_service.dart` into connection + entity pull/push modules
- [ ] **4.E** Split `local_server_service.dart` into hub routes + `inventory_effects.dart`
- [ ] **4.F** Sale push idempotency + tests
- [ ] **4.G** `SyncStatus` model + UI indicators use it only

### 4.7 Done when

- “Android sells offline” is answerable from one doc
- UI depends on facade + status, not five services
- Hub inventory mutation is isolated and covered by tests

---

## 5. Tests that protect money and stock

**Goal:** Fast regression suite for money, stock, and sync contracts — not 100% widget coverage.

### 5.1 Baseline

- App: ~67k LOC (excl. generated)
- Tests today: ~5 files / ~272 lines — treat as near-zero for critical paths

### 5.2 Test layout

```
test/
  domain/
    sale_calculator_test.dart
    stock_rules_test.dart
    transfer_rules_test.dart
  sync/
    queue_test.dart
    sale_idempotency_test.dart
  integration/                 # optional, ObjectBox temp dir
    checkout_flow_test.dart
    transfer_flow_test.dart
  fixtures/
    sample_medicines.dart
    sample_sales.dart
```

### 5.3 Priority suites

| Priority | Suite | Must assert |
|----------|-------|-------------|
| P0 | Sale calculator | Line totals, discount, tax, multi-tender, returns |
| P0 | Stock rules | Deduct store/clinic/bulk; no negative; revert restores |
| P0 | Transfer rules | From/to qty; reject invalid warehouse pairs |
| P1 | Sync queue | Order, retry, no double-apply on drain |
| P1 | Sale push idempotency | Same invoice twice → one stock hit |
| P2 | Checkout integration | Sale persisted + stock down |
| P2 | Transfer integration | Source down, dest up |

### 5.4 Workflow

1. Extract domain (§3) → write tests in same PR when possible.
2. Every production money/stock bug gets a regression test before the fix merges.
3. CI: `flutter test` on every PR (local minimum: always before merge).

### 5.5 Tasks

- [x] **5.A** Add `test/domain/sale_calculator_test.dart` (with 3.A)
- [x] **5.B** Add `stock_rules_test.dart` (with 3.B)
- [x] **5.C** Add `transfer_rules_test.dart` (with 3.C)
- [x] **5.D** Add queue + idempotency tests (with 4.F)
- [x] **5.E** Optional ObjectBox integration tests for checkout + transfer
- [x] **5.F** Document how to run: `flutter test` in README

### 5.6 Done when

- Core sale/stock math cannot regress silently
- Idempotent sale push is proven by test
- Suite runs in under ~30s without a device

---

## 6. Suggested schedule

| Week | Focus | Deliverables |
|------|--------|--------------|
| **1** | Domain + tests foundation | `sale_calculator`, `stock_rules`, unit tests; start `SYNC.md` |
| **2** | God-file split P0 | `warehouse_windows` fully modular; smoke warehouse |
| **3** | Shared POS | `PosController` on Windows + Android; checkout tests |
| **4** | Sync facade | `SyncFacade`, UI migration start, queue tests |
| **Ongoing** | Hygiene | One god file per PR until top 10 are under ~600 LOC |

Adjust weeks to real capacity; keep PR size small over schedule rigidity.

---

## 7. PR checklist (use on every change)

- [ ] Scope matches one row from this plan (or a single bugfix)
- [ ] No unrelated refactors
- [ ] `flutter analyze` clean on touched code
- [ ] New/changed domain logic has tests when applicable
- [ ] Manual smoke of affected flow (POS / warehouse / sync)
- [ ] No secrets or large binaries committed
- [ ] Plan task checkbox updated when the work lands

---

## 8. Out of scope (for this plan)

- Full UI redesign / design-system rewrite
- Migrating off ObjectBox or Provider
- iOS product support
- Deleting root `build/` as a recurring process requirement
- Rewriting Firebase from scratch
- 100% widget/E2E coverage

---

## 9. Success metrics

| Metric | Baseline (approx) | Target |
|--------|-------------------|--------|
| God files ≥1000 LOC | ~20 | &lt;5 (then 0 for UI) |
| Largest UI file | ~4k LOC | ≤600 LOC |
| Critical domain tests | ~0 | ≥20 focused tests (sale/stock/transfer/queue) |
| Nested junk projects | 0 after cleanup | Stay 0 |
| Sync entry points from UI | Many services | 1 facade + status |

---

## 10. Quick reference — task index

| ID | Area | Task |
|----|------|------|
| 2.A–2.F | UI split | Warehouse → POS → analysis → settings → remeasure |
| 3.A–3.F | Shared logic | Domain calculators → controllers → audit dupes |
| 4.A–4.G | Sync | SYNC.md → facade → split services → idempotency → status |
| 5.A–5.F | Tests | Domain → queue/idempotency → optional integration → docs |

---

*Last updated: 2026-07-12 — All tasks (Hygiene, Modularization, Shared Logic Extraction, Sync Facade, and Unit Tests) are successfully completed.*
