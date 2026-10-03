# MediPoss Light Web App (Vercel Ready)

A lightweight, zero-dependency, ultra-fast client-side web application mirroring the core functionality of the MediPoss Flutter desktop & Android apps.

## Features Included:
- **Same Staff PIN Login System**:
  - `Admin` (PIN: `1234`)
  - `Dr. Sharma` (PIN: `2222`)
  - `Pharmacist Rahul` (PIN: `3333`)
  - `Cashier Amit` (PIN: `4444`)
- **Dashboard**:
  - Live Revenue KPI, total transactions, active OPD count, and low dispensing stock alert.
  - Recent OPD queue and recent sales breakdown.
- **Sales History**:
  - Filterable transaction register (search by invoice, patient name, phone).
  - Highlights Clinic Dispenses vs Retail Counter Sales with item count & payment methods.
  - CSV export.
- **OPD Queue**:
  - Today's live queue with status badges: `Waiting`, `With Doctor`, `Pharmacy Dispense`, `Completed`.
  - Token tracking, consultation fees, and doctor notes.
- **Analysis Hub**:
  1. **Stock Explorer**: Real-time store stock, clinic stock, combined dispensing stock, bulk warehouse stock, 30-day velocity, and days of stock remaining.
  2. **Replenishment Planner**: Takes **both Store and Clinic** dispensing stock into consideration against 7, 15, 30, and 45-day target buffers, computing deficits and bulk warehouse coverage with instant quick transfer actions.
  3. **Reorder & Dead Stock**: Procurement suggestions based on sales consumption velocity, depletion horizon, and zero-sales dead stock capital tracker.
  4. **Stock Reconciliation & Audit**: Dispensary baseline snapshots, net transfers, clinic dispenses, retail deductions, expected vs current stock, and variance deficit/surplus indicators with Excel-compatible scope toggles.
- **Live Sync Support**:
  - Can optionally connect directly to your live Windows Hub via Cloudflare Tunnel or local LAN (`/api/medicines`, `/api/sales`, `/api/appointments`).

## How to Deploy to Vercel in 1 Minute:

### Option A: Using Vercel CLI
From your terminal:
```bash
cd web_app
npx vercel
```

### Option B: Deploying via GitHub to Vercel
1. Commit the `web_app/` folder to your GitHub repository.
2. In the Vercel Dashboard, click **New Project** -> import your repo.
3. In the **Root Directory** setting, set it to `web_app`.
4. Click **Deploy**. Vercel will immediately deploy the light web app with zero build time and global CDN distribution!
