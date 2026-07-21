# MediPoss Codebase Brain Map (BRAIN.md)

This document is the index map for the MediPoss project. Read this file first to understand the layout and architecture before performing searches.

## 🏗️ Architecture Overview
- **Core Technology**: Flutter (Dart) for Windows & Android.
- **Database**: ObjectBox (fast local NoSQL database).
- **State Management**: Provider model using `ChangeNotifier`.
- **Sync Topology**: Local server (Shelf HTTP / WebSocket server on Windows Hub) + Android Clients synchronizing database states.
- **Secondary Sync**: Firebase Sync Service.

---

## 📂 Project Structure Map

### 1. State Management Providers (`lib/shared/providers/`)
Holds application state, reactive logic, and triggers synchronization queues.
* [auth_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/auth_provider.dart) - Handles user login, permissions, and session state.
* [cart_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/cart_provider.dart) - POS cart calculations, item quantities, taxes, and checkout logic.
* [inventory_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/inventory_provider.dart) - Stock management, batch codes, medicines library, and adjustments.
* [opd_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/opd_provider.dart) - OPD queue, tokens, visits, doctor assignations.
* [patient_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/patient_provider.dart) - Patient registration, search, and fuzzy duplicate checking (`findPotentialDuplicates`).
* [prescription_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/prescription_provider.dart) - Patient prescriptions, templates, and clinical files.
* [sales_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/sales_provider.dart) - Sales transaction logs, refund processing, and invoice generation hooks.
* [settings_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/settings_provider.dart) - Theme selection, billing config, store parameters.
* [warehouse_provider.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/providers/warehouse_provider.dart) - Transfers and rules for moving stock between stores and main warehouse.

### 2. Core Services (`lib/shared/services/`)
Utility classes, network bindings, and database helpers.
* [objectbox_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/objectbox_service.dart) - Database initializer, boxes instantiation (`patientBox`, `medicineBox`, etc.).
* [local_server_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/local_server_service.dart) - Host Shelf server implementation running on Windows.
* [sync_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/sync_service.dart) - Bidirectional synchronization engine (Hub/Client).
* [firebase_sync_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/firebase_sync_service.dart) - Offsite backup and multi-branch cloud sync.
* [sync_queue_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/sync_queue_service.dart) - Local outbox tracking unsynced mutations on Android client.
* [invoice_generator.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/invoice_generator.dart) - PDF creation templates for bills, receipts, and print orders.
* [printing_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/printing_service.dart) - Thermal printer drivers, ESC/POS commands, and A4 print bridges.
* [audit_service.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/shared/services/audit_service.dart) - Action logging for user actions (CREATE, DELETE, etc.).

### 3. Models (`lib/shared/models/`)
Entities stored inside the ObjectBox database.
- `Patient`, `Medicine`, `Sale`, `SaleItem`, `User`, `Prescription`, `Doctor`, `Appointment`, `StockAdjustment`.

### 4. UI Elements (`lib/widgets/`)
Common shared components and dialog flows.
* [patient_dialogs.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/widgets/patient_dialogs.dart) - Patient search modal, new registration, duplicate checker modal.
* [return_dialog.dart](file:///c:/Users/sumit/Downloads/mediposs%20new%20scratch/lib/widgets/return_dialog.dart) - POS sales return/refund entry interface.

### 5. Multi-Platform Screen Trees (`lib/screens/`)
* **Windows View (`lib/screens/windows/`)** - Optimized for desktop mouse/keyboard use (POS Grid, Analytics, Stock Reports, Reorder tabs).
* **Android View (`lib/screens/android/`)** - Optimized for touch, barcode scanning, and companion photo uploads.
