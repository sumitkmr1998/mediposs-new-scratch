# MediPoss performance notes

## Scale goals

| Metric | Target |
|--------|--------|
| Cold open (Year5 seed) | Interactive &lt; 3s |
| Dashboard smart low-stock | O(sales window + SKUs), 30-day sales only |
| Sales history | DB page size 30; no full-table materialization for list |
| OPD queue | Today + open yesterday only |
| Patient search | DB query limit 50 |

## What changed (Phase A)

1. **ObjectBox indexes** on sale/patient/medicine/appointment/prescription/audit fields
2. **MigrationService** — one-shot batch dedup + sale invoice dedup (not on every load)
3. **SaleRepository** — `salesInRange`, `salesLastDays`, paginated search
4. **ConsumptionAggregator** — single-pass JSON decode for smart stock / reorder
5. **SalesProvider** — page from DB; analytics window 30–90 days (never all history)
6. **OpdProvider.loadQueue** — scoped appointments
7. **PatientProvider** — search/recent with limits
8. **SyncDelta** — selective provider reload after sync

## What changed (Phase B)

1. **Repositories** — medicine, appointment, prescription (+ sale/patient from A)
2. **DailyMedicineSalesFact** + `SalesFactService` — durable rollups; migration v3 backfill
3. Checkout / void / sync pull keep facts updated
4. Smart stock / reorder prefer facts when present
5. **ChunkedBoxIo** — backup JSON export streams large boxes; audit export chunks sales
6. **apply_merge.dart** helpers + hub `json_handlers.dart` (start of service split)
7. Android `analysis/analysis_consumption.dart` helper

## Seed / bench (manual)

```bash
# Domain + aggregator tests
flutter test test/domain test/utils

# Scale seed (uses terminal DB path) — BACK UP FIRST
dart run tool/seed_scale_data.dart --profile=smoke
dart run tool/seed_scale_data.dart --profile=year5

# Query budgets
dart run tool/perf_bench.dart

# Analyze
flutter analyze --no-fatal-infos
```

## Upgrade note

First launch after upgrade may rebuild indexes and run data migrations once (`mediposs_data_migration_version` in SharedPreferences).  
Migration **v3** rebuilds sales fact rollups from history (one-time; may take a while on large DBs).
