# MediPass Sync Story (SYNC.md)

This document describes the offline-first, dual-sync architecture of MediPass. It details how data flows between the local ObjectBox database, local LAN Hub (Windows Server), Cloudflare Tunnels, and Firebase Firestore (Backup Cloud Storage).

---

## 1. Sync Modes and Topologies

MediPass operates in four primary synchronization modes, configured on a per-device basis (typically on Android client devices):

```
1. Local WiFi Mode     : Android Client ──(Direct LAN HTTP)────────► Windows Hub (ObjectBox)
2. Cloudflare Tunnel   : Android Client ──(Cloudflare HTTPS)───────► Windows Hub (ObjectBox)
3. Firebase Only Mode  : Android Client ──(Firestore Sync)────────► Firebase Cloud (Fallback)
4. Auto Mode (Default) : Priority-based chain (Local WiFi -> Cloudflare -> Firebase Only)
```

---

## 2. Priority-Based Connectivity Chain (Auto Mode)

In **Auto Mode**, client requests follow this fallback priority chain:

1. **Local WiFi**: Attempt to connect directly to the Windows Hub on the LAN (e.g., `http://192.168.x.x:8080`).
2. **Cloudflare Tunnel**: If WiFi is unreachable, attempt connection via the Cloudflare Tunnel URL (e.g., `https://xxx.trycloudflare.com`).
3. **Firebase Firestore**: If both LAN and Tunnel are offline (e.g., outside clinic hours between 5 PM and 10 AM daily when the Windows Hub machine is powered off), read/write to the Firebase Cloud mirroring layer.

---

## 3. Data Flow and Read/Write Paths

To ensure zero latency and full offline operation, MediPass strictly uses an **offline-first** database model:

### 3.1 Write Path
1. **Local Write**: UI initiates saving a sale or modifying stock.
2. **ObjectBox Save**: The change is written immediately to the local ObjectBox database. This is the source of truth for the local device.
3. **Push/Enqueue**:
   - If a connection is active (WiFi/Tunnel/Cloud), push the change directly to the Hub.
   - If offline, serialize and push the item to the `SyncQueueService` database table.
4. **Queue Drain**: A background worker constantly checks connection status and drains the queue once connectivity is restored, marking items as `synced` upon Hub acknowledgment.

### 3.2 Read Path
* The UI **always** reads data from the local ObjectBox database.
* The UI never blocks on network requests to display lists.
* Network pull tasks merge remote data directly into the local ObjectBox database in the background, which then triggers UI updates via stream listeners.

---

## 4. Conflict Resolution Policy

1. **Last-Write-Wins (Timestamp-based)**: Most entities (such as patients or doctor templates) resolve conflicts using the `updatedAt` ISO-8601 timestamp.
2. **Hub-Wins (Inventory Stock)**: For critical stock counts and medicine quantity deductions, the Hub acts as the final arbiter.
3. **Idempotency Keys**: Sales transactions are registered with a unique `invoiceNo` / UUID. Pushing the same sale multiple times does not duplicate the record; the Hub recognizes the existing invoice and performs an update instead of a new insert.
