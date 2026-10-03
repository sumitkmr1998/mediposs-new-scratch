// MediPoss State Management, Auth & Calculations
class MediPossState {
  constructor() {
    this.currentUser = JSON.parse(localStorage.getItem('mediposs_user')) || null;
    this.medicines = JSON.parse(localStorage.getItem('mediposs_meds')) || DEFAULT_MEDICINES;
    this.sales = JSON.parse(localStorage.getItem('mediposs_sales')) || DEFAULT_SALES;
    this.appointments = JSON.parse(localStorage.getItem('mediposs_appointments')) || DEFAULT_APPOINTMENTS;
    this.transfers = JSON.parse(localStorage.getItem('mediposs_transfers')) || DEFAULT_TRANSFERS;
    this.baselineDate = localStorage.getItem('mediposs_baseline_date') || null;
    this.baselineStock = JSON.parse(localStorage.getItem('mediposs_baseline_stock')) || {};
    
    // Hub connection settings
    this.hubUrl = localStorage.getItem('mediposs_hub_url') || '';
    this.hubSecret = localStorage.getItem('mediposs_hub_secret') || '';
    this.isLiveConnected = false;
  }

  save() {
    localStorage.setItem('mediposs_user', JSON.stringify(this.currentUser));
    localStorage.setItem('mediposs_meds', JSON.stringify(this.medicines));
    localStorage.setItem('mediposs_sales', JSON.stringify(this.sales));
    localStorage.setItem('mediposs_appointments', JSON.stringify(this.appointments));
    localStorage.setItem('mediposs_transfers', JSON.stringify(this.transfers));
    if (this.baselineDate) localStorage.setItem('mediposs_baseline_date', this.baselineDate);
    localStorage.setItem('mediposs_baseline_stock', JSON.stringify(this.baselineStock));
  }

  login(user, pin) {
    if (user.pin === pin) {
      this.currentUser = user;
      this.save();
      return true;
    }
    return false;
  }

  logout() {
    this.currentUser = null;
    localStorage.removeItem('mediposs_user');
  }

  // Dispensing stock helper (Clinic + Store dispensing, excluding bulk)
  getDispensingStock(med) {
    return (med.storeStock || 0) + (med.mainStock || 0);
  }

  // Bulk stock helper
  getTotalBulkStock(med) {
    return (med.bulkStoreStock || 0) + (med.bulkClinicStock || 0);
  }

  // Consumption velocity over 30 days
  getDailyRate(med, days = 30) {
    const medNameLower = med.name.toLowerCase().trim();
    let unitsSold = 0;
    for (const sale of this.sales) {
      if (sale.isReturn) continue;
      for (const item of (sale.items || [])) {
        if (!item.isProcedure && item.medicineName && item.medicineName.toLowerCase().trim() === medNameLower) {
          unitsSold += (item.qty || 0);
        }
      }
    }
    return unitsSold / days;
  }

  // Stock Remaining Days
  getDaysRemaining(med) {
    const daily = this.getDailyRate(med);
    const dispensing = this.getDispensingStock(med);
    if (daily <= 0) return 999;
    return dispensing / daily;
  }

  // Reset Audit Baseline
  setBaseline() {
    this.baselineDate = new Date().toISOString();
    const stocks = {};
    for (const med of this.medicines) {
      stocks[med.id] = {
        clinic: med.mainStock || 0,
        store: med.storeStock || 0,
        total: (med.mainStock || 0) + (med.storeStock || 0)
      };
    }
    this.baselineStock = stocks;
    this.save();
  }

  clearBaseline() {
    this.baselineDate = null;
    this.baselineStock = {};
    localStorage.removeItem('mediposs_baseline_date');
    localStorage.removeItem('mediposs_baseline_stock');
    this.save();
  }

  // Adjust stock
  adjustStock(medId, clinicStock, storeStock) {
    const med = this.medicines.find(m => m.id === medId);
    if (med) {
      if (clinicStock !== undefined) med.mainStock = parseInt(clinicStock, 10);
      if (storeStock !== undefined) med.storeStock = parseInt(storeStock, 10);
      this.save();
    }
  }

  // Quick live sync with Windows Hub if user enters Cloudflare or LAN URL
  async syncWithHub(url, secret) {
    try {
      this.hubUrl = url.replace(/\/$/, '');
      this.hubSecret = secret || '';
      localStorage.setItem('mediposs_hub_url', this.hubUrl);
      localStorage.setItem('mediposs_hub_secret', this.hubSecret);

      const headers = { 'Content-Type': 'application/json' };
      if (this.hubSecret) headers['X-MediPass-Secret'] = this.hubSecret;

      const healthRes = await fetch(`${this.hubUrl}/health`, { headers, mode: 'cors' });
      if (!healthRes.ok) throw new Error('Hub health check failed');

      const medsRes = await fetch(`${this.hubUrl}/api/medicines`, { credentials: 'omit', headers, mode: 'cors' });
      if (medsRes.ok) {
        const medsData = await medsRes.json();
        if (Array.isArray(medsData)) {
          this.medicines = medsData;
        }
      }

      const salesRes = await fetch(`${this.hubUrl}/api/sales`, { credentials: 'omit', headers, mode: 'cors' });
      if (salesRes.ok) {
        const salesData = await salesRes.json();
        if (Array.isArray(salesData)) {
          this.sales = salesData;
        }
      }

      const apptRes = await fetch(`${this.hubUrl}/api/appointments`, { credentials: 'omit', headers, mode: 'cors' });
      if (apptRes.ok) {
        const apptData = await apptRes.json();
        if (Array.isArray(apptData)) {
          this.appointments = apptData;
        }
      }

      this.isLiveConnected = true;
      this.save();
      return { success: true };
    } catch (e) {
      this.isLiveConnected = false;
      return { credentials: false, error: e.message };
    }
  }
}

window.appState = new MediPossState();
