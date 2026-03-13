 MediPoss Development Progress Report

## Core Architecture
- ✅ **Infrastructure:** Flutter + ObjectBox Database (Local).
- ✅ **Server & Sync:** Native Windows `shelf` server (port 8080) with real-time WebSocket syncing for Android extensions (JWT secured).
- ✅ **State Management:** Providers for Inventory, Cart, Sales, Warehouse, OPD, Patients, and Auth.
- ✅ **Responsive UI:** Dark-themed suite for desktop/mobile.

## POS & Sales System
- ✅ **Return Modes:** Fast toggle for negative values and receipt-based refund dialog for partial returns.
- ✅ **Payments:** Multi-method split payments (Cash, UPI, Card) with math validation.
- ✅ **Keyboard Speed:** Zero-mouse checkout flow (Arrow keys/Enter shortcuts).
- ✅ **Printing:** Native PDF generation and print previews on checkout.
- ✅ **Voiding:** Admin-only "Void Sale" with full inventory restock logic.

## OPD & Patient Management (Recent Enhancements)
- ✅ **Shared Dialogs:** Consolidated registration, search, and booking into `lib/widgets/patient_dialogs.dart` for reuse across POS and OPD screens.
- ✅ **OPD Queue flow:** "Add Patient" FAB on the OPD Queue screen allows registering or searching for patients directly in the queue.
- ✅ **Patient Details:** Full history (sales + prescriptions), photo gallery (with file storage), and profile management.
- ✅ **Prescription Engine:** Built a full prescription builder with vitals, medicines, lab tests, and diagnosis.
- ✅ **Deletion:** Added "Delete Patient" feature with automatic cleanup of associated visit history and physical image files.

## Authentication & Staff Control
- ✅ **User Selection Login:** Upgraded login screen to select users before PIN entry (Esc to go back).
- ✅ **Global Logout:** Added logout buttons to Sidebar (Desktop) and App Bar (Mobile) with confirmation dialogs.
- ✅ **Upgraded Permissions:** 
    - Granular OPD controls (Queue access, Doctor management, OPD Reports).
    - Comprehensive permission matrix in the Staff edit dialog.
    - Automatic UI enforcement: Sidebar icons hide if permission is missing.
    - Admin-visible PINs in the staff list.

## Important Shortcuts & Key Features
- **POS Keys:** Arrow Down (Search List), Enter (Select/Submit), Arrow Right (Payment Method).
- **Login Keys:** 0-9 (Direct PIN), Backspace (Clear), Esc (Change User).
- **Default PIN:** `1234` for Admin.
- **Data Path:** Uses `getApplicationDocumentsDirectory` for patient photos and local ObjectBox storage.
