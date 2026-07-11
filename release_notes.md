## Version 3.0.0 Changes

**Features & Onboarding Improvements:**
* **Parallel Hub & Cloud Discovery**: Implemented local UDP hub discovery and Firestore cloud tunnel checks in parallel. It aggregates all active hub instances and presents a clean selection card listing local/cloud badges and their Shop IDs.
* **First-Launch Auto-Detect**: Automatically launches the network scan on initial startup if no prior connection IP is configured, directing the user straight to active local or cloud hubs.
* **Shop Partition History (One-Tap Entry)**: Automatically saves a local history of the 5 most recently connected shop partitions. Exposes these as quick-select **Action Chips** at the top of the selector dialog, eliminating manual typing.
* **Windows Sidebar Pairing QR Code**: Clicking the "Hub Active" badge in the Windows Hub sidebar now pops up a pairing QR code containing all credentials (local IP, Cloudflare url, Shop ID, secret JWT) for instant Android scanning.
* **Auto-Wipe & Full-Sync Reset**: Wipes local data, logs out, and resets sync timestamps automatically when pairing with a different Hub address or Shop ID partition to prevent data contamination.
* **Wear OS Companion Integration (Watch Support)**:
  * Added dedicated watch app companion (`lib/main_wear.dart`, `wear_dashboard.dart`).
  * Implemented a native Kotlin `WearSummaryTileService` for rendering daily sales, transaction totals, and store vs. clinic breakdowns directly on watch face tiles.
  * Added custom watch layout dependencies and target JVM compilation rules to Gradle build files.

**Security, API & Sync Enhancements:**
* **Granular Role-Based Access (RBAC)**: Enforced custom role permissions, ensuring restricted actions (like manual stock adjustment) require corresponding credentials (`canAddStock`, `isAdmin`, etc.).
* **Connection & Client Streaming**: Integrated dynamic WebSocket connection client count streams on the Hub server.
* **Purchase REST Endpoints & Sync**: Implemented `/api/purchases` and `/api/purchases/push` APIs, routing client-side purchase records through the sync queue back to the central Hub.
* **Stock cap boundary protection**: The POS cart automatically restricts added quantities to the maximum available main/store stock levels (unless in return mode) to prevent checkout oversells.
* **Audit-based Void Sync**: Voiding/deleting an OPD invoice triggers an `AuditLog` entry that other nodes process to incrementally delete the voided sale locally.

**Bug Fixes & Network Optimizations:**
* **Data-Protection Triggered Offline Overlay**: Restricted the blocking "Hub Connection Lost" full-screen overlay to trigger strictly when a data upload operation fails (e.g. sync queue fails to push). This prevents intrusive popup interruptions during idle browsing and navigation while fully protecting data integrity.
* **WebSocket Client Heartbeat Tolerance**: Upgraded the client heartbeat checks to tolerate up to 3 consecutive failures (60 seconds of downtime) before force-disconnecting, eliminating false-positive drops caused by network flutters or busy server loops.
* **Hub Connection Leak Fix**: Implemented a periodic 15-second write keep-alive ping loop on the Windows Hub to force pruning of dead WebSocket channels (e.g. silent drops behind Cloudflare tunnels).
* **PIN Saving & Alignment**: Masked security edits to prevent overwriting existing PINs and enforced 4-digit PIN validations to prevent admin lockout.

