# Hosted Flutter Web Client Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable the Windows MediPoss Hub to host a Flutter Web client application directly from its embedded Shelf server, serving browser clients across the LAN/Internet while retaining sole, exclusive ownership of the ObjectBox database.

**Architecture:** A standalone Flutter Web client (`web_client/`) is compiled to static web assets (HTML/JS/WASM/CSS) and hosted by the Windows Hub's existing Shelf HTTP server (`LocalServerService`) via `shelf_static`. The browser client operates as an HTTP/WebSocket client querying and mutating data exclusively through the Hub's REST APIs and `/ws/updates` stream, guaranteeing that the native Windows Hub remains the only process touching the underlying ObjectBox database (`data.mdb`).

**Tech Stack:** Flutter Web (Dart 3.x), Shelf (`shelf`, `shelf_static`, `shelf_router`, `shelf_web_socket`), ObjectBox (Windows Hub only), WebSockets, JWT Authentication, Provider.

---

## 🏗️ Architecture & Database Ownership Boundary

```
  ┌────────────────────────────────────────────────────────┐
  │         Windows Hub Host Machine (mediposs.exe)        │
  │                                                        │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │   ObjectBox Engine (Native C-FFI / data.mdb)     │  │
  │  │   * SOLE & EXCLUSIVE PROCESS-LEVEL FILE LOCK *   │  │
  │  └────────────────────────▲─────────────────────────┘  │
  │                           │                            │
  │  ┌────────────────────────┴─────────────────────────┐  │
  │  │     LocalServerService (Dart Shelf on Port 8080) │  │
  │  │  • Static File Server (shelf_static -> web_dist) │  │
  │  │  • REST Endpoints (/api/medicines, /api/sales)   │  │
  │  │  • WebSocket Broadcast (/ws/updates)             │  │
  │  └────────────────────────▲─────────────────────────┘  │
  └───────────────────────────┼────────────────────────────┘
                              │ HTTP & WebSocket (Port 8080)
            ┌─────────────────┴─────────────────┐
            │                                   │
     ┌──────▼──────┐                     ┌──────▼──────┐
     │ Web Browser │                     │ Web Browser │
     │  (Chrome)   │                     │(Safari/iPad)│
     │ Flutter Web │                     │ Flutter Web │
     │ (Zero-inst) │                     │ (Zero-inst) │
     └─────────────┘                     └─────────────┘
```

### Why This Guarantees Safe Database Ownership:
1. **Zero Database Conflicts**: The web browser runs inside a sandboxed browser runtime (V8 / JavaScript / WASM) and has zero direct disk or FFI access. It physically cannot touch or lock `data.mdb`.
2. **Atomic Commits**: Every write (e.g. cart checkout, stock adjustment, patient registration) is posted to `/api/*` and processed by the Windows Hub inside an ObjectBox write transaction (`store.runInTransaction`).
3. **Instant Live Reactivity**: Whenever the Web Client or the Windows Hub commits a sale or edits stock, the Hub broadcasts change notifications over `/ws/updates`. Both the native Windows UI and all connected web browsers refresh instantly.

---

## Phase 1: Windows Hub Web Hosting Infrastructure

### Task 1: Add `shelf_static` and Configure Static File Serving in Hub

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/shared/services/local_server_service.dart`
- Create: `web_dist/index.html` (initial placeholder for testing)

**Step 1: Add `shelf_static` dependency to `pubspec.yaml`**
Under `# Local HTTP Server (Windows Hub)`:
```yaml
  # Local HTTP Server (Windows Hub)
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  shelf_web_socket: ^2.0.0
  shelf_static: ^1.1.2
  web_socket_channel: ^3.0.1
```

**Step 2: Run pub get**
Run: `flutter pub get`
Expected: Resolves `shelf_static` cleanly without conflicts.

**Step 3: Update `LocalServerService` to host static web assets with SPA Fallback**
In `lib/shared/services/local_server_service.dart`:
- Locate the web root directory (`web_dist/` in dev or `<exe_dir>/web_dist/` in prod).
- Create a `shelf_static` handler with `defaultDocument: 'index.html'`.
- Build a Cascade: Route API and WebSocket requests first. If a path is not an `/api/` or `/ws/` route and does not match a static file, fallback to serving `index.html` (SPA routing for Flutter Web).

```dart
// lib/shared/services/local_server_service.dart
Handler _buildHandler(Router router) {
  final webDir = _resolveWebDistDirectory();
  Handler? staticHandler;
  if (webDir != null && webDir.existsSync()) {
    staticHandler = createStaticHandler(
      webDir.path,
      defaultDocument: 'index.html',
    );
  }

  // Fallback for SPA routing (returns index.html for unrecognized routes without extension)
  Response? spaFallback(Request request) {
    if (webDir != null && request.method == 'GET' && !request.url.path.startsWith('api/') && !request.url.path.startsWith('ws/')) {
      final indexFile = File(p.join(webDir.path, 'index.html'));
      if (indexFile.existsSync()) {
        return Response.ok(
          indexFile.openRead(),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
    }
    return null;
  }

  return (Request request) async {
    // 1. Try API router
    final response = await router.call(request);
    if (response.statusCode != 404) return response;

    // 2. Try static file handler
    if (staticHandler != null) {
      final staticResp = await staticHandler(request);
      if (staticResp.statusCode != 404) return staticResp;
    }

    // 3. Fallback to index.html for SPA routes
    final spaResp = spaFallback(request);
    if (spaResp != null) return spaResp;

    return Response.notFound('Not Found');
  };
}
```

**Step 4: Update `_secretMiddleware` to allow public static asset serving**
In `_secretMiddleware()`, allow static web files (`.html`, `.js`, `.css`, `.png`, `.wasm`, `.json`, `.ico`, `.ttf`, `.woff2`) and root `/` without `X-MediPass-Secret`:
```dart
final path = request.url.path;
final isPublicPath = path == '' ||
    path == 'health' ||
    path == 'download-apk' ||
    path == 'api/auth/login' ||
    path == 'index.html' ||
    path.startsWith('assets/') ||
    path.endsWith('.js') ||
    path.endsWith('.css') ||
    path.endsWith('.wasm') ||
    path.endsWith('.png') ||
    path.endsWith('.json') ||
    path.endsWith('.ttf') ||
    path.endsWith('.ico');

if (isPublicPath) {
  return innerHandler(request);
}
```

**Step 5: Verify static serving**
Run the Windows app, open `http://localhost:8080/` in Chrome, and verify that the placeholder `index.html` loads with HTTP 200.

---

### Task 2: Hub Web Access Link & QR Code in Windows Settings UI

**Files:**
- Modify: `lib/screens/windows/settings_windows.dart`
- Modify: `lib/screens/windows/widgets/settings_widgets.dart`

**Step 1: Display Hub Web URL in Settings**
Show the primary LAN URL (e.g. `http://192.168.1.15:8080`) in the Network / Sync section of `SettingsWindows`:
- "Open Web POS in Browser" button (uses `url_launcher`).
- "Copy Web Link" button (copies `http://<hub_ip>:8080` to clipboard).
- QR code dialog displaying the web URL for instant camera scanning on mobile/tablets.

**Step 2: Test link launching and copying**
Click "Open Web POS", verify browser opens to `http://localhost:8080/`.

---

## Phase 2: Flutter Web Client Project (`web_client/`)

### Task 3: Scaffold Flutter Web Subproject

**Files:**
- Create: `web_client/pubspec.yaml`
- Create: `web_client/web/index.html`
- Create: `web_client/web/manifest.json`
- Create: `web_client/lib/main.dart`

**Step 1: Create `web_client/pubspec.yaml`**
Include only web-safe packages:
```yaml
name: mediposs_web
description: MediPoss Flutter Web Client
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
  http: ^1.2.1
  web_socket_channel: ^3.0.1
  lucide_icons: ^0.257.0
  intl: any
  google_fonts: ^6.2.1
  shared_preferences: ^2.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

**Step 2: Create Web Entry Point (`web_client/lib/main.dart`)**
- Initialize `SharedPreferences` for token caching.
- Auto-detect Hub API URL from `Uri.base`:
  ```dart
  String get defaultApiBase {
    final uri = Uri.base;
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }
  ```
- Configure theme with MediPoss dark/light styling and launch `WebLoginScreen` or `WebAppShell`.

---

### Task 4: Web API & WebSocket Communication Layer

**Files:**
- Create: `web_client/lib/services/api_service.dart`
- Create: `web_client/lib/services/web_socket_service.dart`
- Create: `web_client/lib/models/web_models.dart` (JSON serializable models for Medicine, Sale, Patient, AppUser)

**Step 1: Implement `ApiService`**
- Manages JWT Auth token in memory and local storage.
- HTTP methods with automatic `Authorization: Bearer <token>` and `Content-Type: application/json`.
- Methods:
  - `login(String name, String pin)` -> returns token and permissions.
  - `getMedicines()` -> `GET /api/medicines`
  - `getPatients()` -> `GET /api/patients`
  - `pushSale(Map<String, dynamic> saleData)` -> `POST /api/sales/push`
  - `pushPatient(Map<String, dynamic> patientData)` -> `POST /api/patients/push`
  - `getAppointments()` -> `GET /api/appointments`

**Step 2: Implement `WebSocketService`**
- Connects to `ws://<host>:<port>/ws/updates`.
- Automatically reconnects on connection loss with exponential backoff.
- Exposes a broadcast stream for entity updates (`medicines`, `sales`, `patients`, `appointments`).

---

### Task 5: Web State Providers & Reactive Sync

**Files:**
- Create: `web_client/lib/providers/web_auth_provider.dart`
- Create: `web_client/lib/providers/web_inventory_provider.dart`
- Create: `web_client/lib/providers/web_cart_provider.dart`
- Create: `web_client/lib/providers/web_sales_provider.dart`
- Create: `web_client/lib/providers/web_patient_provider.dart`

**Step 1: Wire providers to `WebSocketService`**
- When `WebSocketService` receives an event for `medicines`, `WebInventoryProvider.fetchMedicines()` triggers automatically in the background.
- When `WebSocketService` receives an event for `patients`, `WebPatientProvider.fetchPatients()` updates the patient search cache.

**Step 2: Implement `WebCartProvider`**
- Item addition, quantity adjustments, discount calculations, GST/Tax calculations.
- Seamless atomic checkout calling `ApiService.pushSale()`.

---

### Task 6: Web UI Screens

**Files:**
- Create: `web_client/lib/screens/web_login_screen.dart`
- Create: `web_client/lib/screens/web_app_shell.dart`
- Create: `web_client/lib/screens/web_pos_screen.dart`
- Create: `web_client/lib/screens/web_inventory_screen.dart`
- Create: `web_client/lib/screens/web_patient_screen.dart`

**Step 1: Web Login Screen**
- Grid of registered users fetched from `/api/users`.
- PIN entry keypad (desktop numpad or touch).
- Quick sign-in returning JWT and loading permissions.

**Step 2: Web App Shell**
- Responsive sidebar navigation (Dashboard, POS Billing, Stock, Patients).
- Live connection indicator showing green when WebSocket is connected to the Windows Hub.
- Current user badge and logout button.

**Step 3: Web POS Billing Screen**
- Fast keyboard-accessible medicine search (barcode scanning or name typing).
- Batch selection dropdown showing real-time available stock.
- Right-side active cart with instant total, tax, discount calculations.
- Patient selector (search by phone or name, or quick add).
- "Complete Sale" action that submits directly to `/api/sales/push` and presents printable receipt dialog.

---

## Phase 3: Automated Build & Packaging Pipeline

### Task 7: Build Script & Windows Distribution Integration

**Files:**
- Create: `scripts/build_web_client.ps1`
- Create: `scripts/build_web_client.bat`

**Step 1: Create PowerShell script `scripts/build_web_client.ps1`**
```powershell
Write-Host "Compiling MediPoss Flutter Web Client..." -ForegroundColor Cyan
Set-Location "web_client"
flutter pub get
flutter build web --release --output="../web_dist"
Set-Location ".."
Write-Host "Web client successfully compiled to web_dist!" -ForegroundColor Green
```

**Step 2: Test the build pipeline**
Run: `powershell -ExecutionPolicy Bypass -File scripts/build_web_client.ps1`
Expected: Produces `web_dist/` containing `index.html`, `main.dart.js`, `flutter.js`, and `assets/`.

**Step 3: Verification End-to-End**
1. Start MediPoss on Windows (Hub mode).
2. Open Chrome on the same PC or another machine on the LAN at `http://<hub_ip>:8080/`.
3. Log in with user PIN.
4. Perform a POS sale in the browser.
5. Verify on the Windows Hub that the sale appears immediately in Sales History, the stock decrements in ObjectBox, and no database locks or errors occur.

---

## Summary of Guarantees
- **Sole Database Ownership**: `mediposs.exe` is the single exclusive writer and reader of ObjectBox.
- **Zero Client Install**: Accessible from any modern browser (desktop, tablet, mobile).
- **Atomic Operations**: All state mutations run as atomic Hub transactions.
- **Real-Time Sync**: Instant WebSocket synchronization keeps web browsers and the Hub completely aligned.

