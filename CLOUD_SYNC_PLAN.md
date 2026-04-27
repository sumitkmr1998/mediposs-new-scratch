# MediPass Cloud Sync Implementation Plan

## Overview

This document outlines implementing cloud-based sync for MediPass, enabling the Windows Hub to be accessible over the internet using Cloudflare Tunnel, with Firebase Firestore as a backup database for offline periods (5 PM - 10 AM daily when Hub is offline).

---

## Target Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│            MediPass: Dual Network + Firebase Backup                  │
├───────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   Android Device                                                      │
│   ┌───────────────────────────────────────────────────────────────┐   │
│   │               Connection Mode Selector                        │   │
│   │  ┌─────────┐  ┌─────────────┐  ┌──────────┐  ┌─────────────┐ │   │
│   │  │Local WiFi│  │Cloudflare   │  │Firebase │  │  Auto       │ │   │
│   │  │         │  │  Tunnel     │  │  Only   │  │  (Default)  │ │   │
│   │  └─────────┘  └─────────────┘  └──────────┘  └─────────────┘ │   │
│   └───────────────────────────────────────────────────────────────┘   │
│                               │                                      │
│   ┌───────────────────────────┴───────────────────────────────────┐   │
│   │  SyncService Priority Chain                                 │   │
│   │                                                           │   │
│   │  1. Local WiFi (192.168.x.x:8080)                         │   │
│   │     └► If fail                                             │   │
│   │  2. Cloudflare Tunnel (https://xxx.trycloudflare.com)   │   │
│   │     └► If fail                                             │   │
│   │  3. Firebase Firestore (Offline Backup)                    │   │
│   │                                                           │   │
│   └───────────────────────────────────────────────────────────┘   │
│                               │                                      │
└───────────────────────────────┼─────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────┐
│           Windows Hub (Desktop)              │
├───────────────────���──────────────────────────┤
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │  CloudflareService                   │   │
│  │  - Auto-install cloudflared          │   │
│  │  - Create tunnel on first launch     │   │
│  │  - Health monitoring                │   │
│  │  - Auto-repair if corrupted           │   │
│  │  - Report public URL to settings      │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  LocalServerService (REST API :8080)        │
│           │                                  │
│           │  ┌──────────────────────────┐  │
│           │  │ Firebase Mirror Service  │  │
│           │  │ (Sync to Firestore)      │  │
│           │  └──────────────────────────┘  │
│           │                                  │
│           ▼                                  │
│  ┌──────────────────────────────────────┐   │
│  │       ObjectBox Database             │   │
│  └──────────────────────────────────────┘   │
│                                             │
└──────────────────────────────────────────────┘
                               ▲
                               │ (HTTPS)
                               │
                         Cloudflare
                         Tunnel
                         (Port 443)
                               │
                               ▼
                         Internet
```

---

## Implementation Checklist

### Phase 1: Dependencies

**File: `pubspec.yaml`**

Add Firebase packages:

```yaml
dependencies:
  firebase_core: ^3.12.0
  cloud_firestore: ^5.6.0
```

### Phase 2: New Services

| File | Purpose |
|------|---------|
| `lib/shared/services/firebase_sync_service.dart` | Firebase read/write/queue |
| `lib/shared/services/cloudflare_service.dart` | Tunnel auto-setup & repair |
| `lib/shared/models/sync_queue_item.dart` | Queue item model |

### Phase 3: Modified Services

| File | Changes |
|------|---------|
| `sync_service.dart` | Add connection mode, fallback chain |
| `local_server_service.dart` | Optional: Firebase mirror push |
| `discovery_service.dart` | Update for dual network |

### Phase 4: Settings/Providers

| File | Changes |
|------|---------|
| `settings_provider.dart` | Add connection mode preference |
| `objectbox_service.dart` | Add sync_queue Box |

### Phase 5: Android UI

| File | Changes |
|------|---------|
| `lib/screens/android/connection_android.dart` | Add mode selector |

---

## Firebase Collections Schema

```
mediposs/
├── settings/
│   └── {
│       lastGlobalSync: timestamp,
│       hubOnline: boolean,
│       cloudflareUrl: string,
│       serverPort: number
│     }
│
├── devices/
│   └── {
│       id: string (UUID),
│       name: string,
│       lastSeen: timestamp,
│       isOnline: boolean,
│       platform: "android"
│     }
│
├── sync_queue/
│   └── {
│       id: string,
│       deviceId: string,
│       entity: string,      // "medicine", "patient", "sale", etc.
│       action: string,       // "create", "update", "delete"
│       data: map,
│       timestamp: timestamp,
│       synced: boolean      // false = pending
│     }
│
├── medicines/
│   └── {
│       id: string,
│       barcode: string,
│       name: string,
│       category: string,
│       unit: string,
│       purchasePrice: number,
│       sellingPrice: number,
│       mainStock: number,
│       storeStock: number,
│       lowStockThreshold: number,
│       updatedAt: timestamp,
│       syncedFrom: string  // "hub" or deviceId
│     }
│
├── patients/
│   └── {
│       id: string,
│       uhid: string,
│       name: string,
│       phone: string,
│       gender: string,
│       address: string,
│       bloodGroup: string,
│       age: number,
│       createdAt: timestamp,
│       updatedAt: timestamp
│     }
│
├── doctors/
│   └── {
│       id: string,
│       name: string,
│       specialization: string,
│       consultationFee: number,
│       qualifications: string,
│       phone: string,
│       isActive: boolean,
│       updatedAt: timestamp
│     }
│
├── appointments/
│   └── {
│       id: string,
│       patientName: string,
│       patientPhone: string,
│       doctorName: string,
│       tokenNumber: number,
│       status: string,
│       consultationFee: number,
│       scheduledAt: timestamp,
│       updatedAt: timestamp
│     }
│
├── sales/
│   └── {
│       id: string,
│       invoiceNo: string,
│       patientId: number,
│       patientName: string,
│       total: number,
│       paymentMethod: string,
│       itemsJson: string,
│       createdAt: timestamp,
│       synced: boolean,
│       sourceDevice: string
│     }
│
├── prescriptions/
│   └── {
│       id: string,
│       patientName: string,
│       doctorName: string,
│       diagnosis: string,
│       itemsJson: string,
│       createdAt: timestamp
│     }
│
└── templates/
    └── {
        id: string,
        name: string,
        diagnosis: string,
        itemsJson: string,
        createdAt: timestamp
      }
```

---

## Cloudflare Service Specification

### Auto-Setup Flow

```
1. First launch on Windows Hub
   │
   ├── Check if cloudflared exists in app directory
   │   └── If NOT: Download cloudflared.exe
   │
   ├── Check existing tunnel config
   │   ├── If CORRUPTED: Delete and recreate
   │   ├── If MISSING: Create new tunnel
   │   └── If VALID: Use existing
   │
   ├── Start tunnel on port 8080
   │
   ├── Get tunnel URL from cloudflared
   │
   ├── Save URL to Firebase settings
   │
   └── Report "hubOnline: true"
```

### Tunnel Health Monitoring

```
- Ping tunnel every 30 seconds
- If no response for 60 seconds → Auto-repair
- Repair: restart cloudflared process
- If restart fails → recreate tunnel
```

### Cloudflare Commands

```bash
# Check if cloudflared exists
test -f cloudflared.exe

# Download (Windows PowerShell)
Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-stable-windows-amd64.exe" -OutFile "cloudflared.exe"

# Create tunnel
.\cloudflared.exe tunnel create mediposs-hub

# Run tunnel
.\cloudflared.exe tunnel run --url localhost:8080 mediposs-hub

# Get tunnel info (JSON)
.\cloudflared.exe tunnel info mediposs-hub -o json

# Delete and recreate (repair)
.\cloudflared.exe tunnel delete mediposs-hub
.\cloudflared.exe tunnel create mediposs-hub
.\cloudflared.exe tunnel run --url localhost:8080 mediposs-hub
```

---

## Sync Service Priority Chain

### Connection Mode: Auto (Default)

```
1. Try Local WiFi (192.168.x.x:8080)
   └── Success → Use local
   └── Fail → Step 2

2. Try Cloudflare Tunnel (https://xxx.trycloudflare.com)
   └── Success → Use cloudflare
   └── Fail → Step 3

3. Try Firebase only (offline mode)
   └── Read from Firestore
   └── Queue writes to sync_queue
```

### Connection Mode: Local WiFi Only

```
- Use 192.168.x.x:8080 only
- If fail → Show connection error
- No Firebase fallback
```

### Connection Mode: Cloudflare Only

```
- Use https://xxx.trycloudflare.com only
- If fail → Show connection error
- No Firebase fallback (unless Hub completely down)
```

### Connection Mode: Firebase Only

```
- Use Firestore as primary database
- Queue all changes to sync_queue
- No real-time sync
```

---

## Android UI Changes

### Connection Screen (Updated)

```
┌──────────────────────────────────────────┐
│         Connection Settings              │
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  🔗 Connection Mode                │  │
│  │  ○ Auto ( Recommended)            │  │
│  │  ○ Local WiFi Only                 │  │
│  │  ○ Cloudflare Tunnel              │  │
│  │  ○ Firebase Only                 │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  📡 Hub Address                   │  │
│  │  [ Auto-detected / Manual Input ]  │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  ☁️ Cloudflare Status              │  │
│  │  URL: https://mediposs.xyz...       │  │
│  │  Status: ● Online                 │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  📥 Firebase Backup               │  │
│  │  Last Sync: 10:30 AM               │  │
│  │  Pending Items: 5                 │  │
│  │  [ Sync Now ]                      │  │
│  └────────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

---

## Settings Schema

### Local Settings (ObjectBox)

```dart
class AppSettings {
  // ... existing fields ...

  // New Cloud Sync Settings
  String connectionMode;    // "auto", "local", "cloudflare", "firebase"
  String cloudflareUrl;   // "https://xxx.trycloudflare.com"
  int lastCloudflareSync;  // timestamp
  bool firebaseEnabled;    // true
  int lastFirebaseSync;   // timestamp
  String deviceId;        // UUID for this device
}
```

## Robustness Upgrades (V2 Additions)

To make the sync system production-grade, the following upgrades are integrated into this plan:

### 1. Atomic Stock Increments (Delta Sync)
- **Mechanism**: Instead of syncing the entire `Medicine` object when a sale occurs, sync **Deltas** (e.g., `{"action": "decrement", "field": "storeStock", "value": 2}`).
- **Hub Broadcast**: After the Hub successfully processes a delta sync from one device, it must immediately broadcast the updated data to all other connected devices to ensure inventory consistency across the clinic.
- **Benefit**: Prevents "Last Write Wins" data loss and guarantees inventory accuracy regardless of offline sync order.

### 2. Transactional "Lease" for the Sync Queue
- **Mechanism**: Implement a Two-Phase Commit for the Firebase `sync_queue`. The Hub marks items as `processing_by: "hub_id"`, applies them locally, and then deletes them.
- **Benefit**: Prevents duplicate processing of sales/stock deductions if the Hub crashes midway through syncing.

### 3. Progressive Fallback with "Optimistic UI" (Local-First)
- **Mechanism**: The Android app always saves to the local ObjectBox immediately, offering a 0ms latency experience. A background worker then attempts the sync chain (Tier 1 → Tier 2 → Tier 3).
- **Benefit**: The UI never blocks waiting for network timeouts.

### 4. Smart Heartbeat & Connectivity Awareness
- **Mechanism**: Use `network_info_plus` to detect connection type. If on Mobile Data, skip the Local WiFi attempt and go straight to Cloudflare.
- **Benefit**: Saves battery and prevents unnecessary timeout delays.

### 5. Media Handling (Local-Only Storage)
- **Mechanism**: Images (e.g., Patient photos, Prescriptions) will **NOT** be stored online in Firebase or Firebase Storage to avoid hitting storage limits and high costs.
- **Storage Strategy**: Images will be saved exclusively on the Windows Hub and cached locally on Android devices.
- **Sync Rule**: Images only sync when the device is on the same Local WiFi network as the Hub or directly connected via the Cloudflare Tunnel.

### 6. Cloudflare "Zero Trust" Pinning
- **Mechanism**: Require an `X-MediPass-Secret` header on all API requests. The Hub drops any request lacking this UUID.
- **Benefit**: Prevents unauthorized internet users or bots from accessing the Hub even if they discover the `trycloudflare.com` URL.

---

## Error Handling

### Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `E001` | Hub unreachable (local) | Try Cloudflare |
| `E002` | Cloudflare unreachable | Try Firebase |
| `E003` | Firebase unavailable | Show offline notice |
| `E004` | Auth token expired | Re-login |
| `E005` | Cloudflare tunnel down | Auto-repair on Hub |
| `E006` | Sync conflict | Use timestamp resolution |

---

## Testing Checklist

### Unit Tests

- [ ] FirebaseSyncService.readEntity()
- [ ] FirebaseSyncService.writeEntity()
- [ ] FirebaseSyncService.queueWrite()
- [ ] CloudflareService.healthCheck()
- [ ] CloudflareService.autoRepair()

### Integration Tests

- [ ] Android → Local Hub sync
- [ ] Android → Cloudflare Hub sync
- [ ] Android → Firebase offline sync
- [ ] Queue → Hub sync (when online)
- [ ] Dual-device concurrent edits

### Manual Tests

- [ ] Hub offline for 17 hours
- [ ] Multiple Android devices sync
- [ ] Cloudflare tunnel auto-repair
- [ ] Conflict resolution

---

## Estimated Firebase Costs

| Daily Active Devices | Syncs/Day | Reads/Day | Writes/Day | Est. Cost/Mo |
|---------------------|----------|-----------|------------|-------------|
| 1 | 50 | 5,000 | 500 | $0.03 |
| 3 | 150 | 15,000 | 1,500 | $0.09 |
| 5 | 250 | 25,000 | 2,500 | $0.15 |
| 10 | 500 | 50,000 | 5,000 | $0.30 |

*Based on: $0.06/10,000 document reads, $0.18/10,000 writes*

---

## Implementation Order

1. **Week 1**: Firebase setup + basic sync service
2. **Week 2**: Cloudflare auto-setup service
3. **Week 3**: Android UI mode selector
4. **Week 4**: Testing + error handling refinement

---

## Notes

- Port 8080 already configured and in use
- Firebase requires google-services.json configuration file
- Cloudflare tunnel may change URL on recreation
- Keep local UDP discovery for initial setup on local WiFi
- Device ID must persist across app reinstalls

---

## Dependencies Required

### pubspec.yaml additions

```yaml
dependencies:
  firebase_core: ^3.12.0
  cloud_firestore: ^5.6.0
  firebase_auth: ^5.5.0

dev_dependencies:
  firebase_core: ^3.12.0
  cloud_firestore: ^5.6.0
```

### External Requirements

1. **Firebase Project Setup**
   - Create project at https://console.firebase.google.com
   - Enable Firestore
   - Download google-services.json

2. **Cloudflare Account**
   - Free tier sufficient
   - No account needed for tunnel creation