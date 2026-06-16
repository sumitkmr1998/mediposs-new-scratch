# MediPoss v2.0.3 Release
"testing update"

# MediPoss v2.0.2 Release
"OTA Update Installer Fixes"


## 🚀 What's New
- **Android Package Installer Permission**: Added `REQUEST_INSTALL_PACKAGES` permission in `AndroidManifest.xml` so the system package installer can install downloaded APKs automatically.
- **Robust Windows Updater Script**: Replaced buggy process waiting in the Windows PowerShell script with native `Wait-Process`, and added try-catch error logging (`updater_error.log`) to guarantee reliability.

# MediPoss v2.0.1 Release
"OPD Receipt Voiding & Audit Log Sync Enhancements"


## 🚀 What's New
- **Automated OPD Receipt Voiding**: Cancelling an appointment in the OPD queue now automatically voids the linked consultation fee receipt (Sale record), updates the inventory/cash registers, and propagates the cancellation to all sync clients.
- **Audit Log Synchronization**: Implemented full synchronization of audit logs from the Hub server back to client terminals, allowing companion devices to see a unified verifiable trail of actions.

# MediPoss v1.8.0 Release
"Advanced Business Analytics & Cross-Device Sync Improvements"


## 🚀 What's New
- **Vibrant Analytics Dashboard (Android)**: Ported the full Windows Analytics Hub to Android, including stacked layout structures and category pie charts.
- **Premium KPI Cards**: Redesigned Sales Trends and Patient Analytics KPI components with subtle progress metrics, trend percentages, and context descriptions.
- **Schedule H1 Compliance**: Integrated Schedule H1 Drug registers with spreadsheet exports (.xlsx) on Windows and Android companion devices.
- **Vibrant Custom Date Filtering**: Added custom date range pickers to Category sales, Explorer, and Compliance registers.
- **UI & Padding Polish**: Removed bottom header divider lines and improved margins for a borderless, modern aesthetic.

# MediPoss v1.0.0 Stable
"A cinema-grade medical POS and clinic management system."

## 🚀 What's New
- **Real-time Patient Timing**: Live "Wait" and "Consultation" timers in the OPD Queue (Android & Windows).
- **Global Sales Search**: Search any historical bill by Name, ID, or Phone without date filters.
- **Unified Dashboard Filtering**: Balanced financial reports that sync Today, Yesterday, 7D, and All-Time data across devices.
- **Enhanced Mobile Experience**: Modernized queue status badges and optimized search interface on Android.

## ✨ Core Features
- **Cinematic Dark UI**: "Void Black" design system for eye-comfort in clinical environments.
- **High-Speed POS**: Keyboard-optimized sales terminal with thermal printing support.
- **Hub-Client Sync**: Seamless real-time data synchronization between Windows and Android.
- **Inventory Management**: Comprehensive stock tracking with Batch & Expiry support.
- **Prescription Hub**: Integrated doctor workflow with remote high-res camera capture.
- **Zero-Config Setup**: Windows Hub acts as a local server for your mobile devices automatically.
- **Secure Architecture**: JWT-based auth and Offline-first local database (ObjectBox).
