// Firebase Configuration matching lib/firebase_options.dart
const FIREBASE_CONFIG = {
  apiKey: "AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs",
  authDomain: "mediposs-64841.firebaseapp.com",
  projectId: "mediposs-64841",
  storageBucket: "mediposs-64841.firebasestorage.app",
  messagingSenderId: "363693923093",
  appId: "1:363693923093:android:38f68ec56eeaac9b79271c"
};

// MediPoss State Management, Realtime Firestore Sync & Analytics
class MediPossState {
  constructor() {
    this.currentUser = JSON.parse(localStorage.getItem('mediposs_user')) || null;
    this.medicines = JSON.parse(localStorage.getItem('mediposs_meds')) || DEFAULT_MEDICINES;
    this.sales = JSON.parse(localStorage.getItem('mediposs_sales')) || DEFAULT_SALES;
    this.appointments = JSON.parse(localStorage.getItem('mediposs_appointments')) || DEFAULT_APPOINTMENTS;
    this.transfers = JSON.parse(localStorage.getItem('mediposs_transfers')) || DEFAULT_TRANSFERS;
    this.users = JSON.parse(localStorage.getItem('mediposs_users_list')) || DEFAULT_USERS;
    this.baselineDate = localStorage.getItem('mediposs_baseline_date') || null;
    this.baselineStock = JSON.parse(localStorage.getItem('mediposs_baseline_stock')) || {};
    
    // Cloud Shop ID partition
    this.shopId = localStorage.getItem('mediposs_shop_id') || 'default_shop';
    this.hubUrl = localStorage.getItem('mediposs_hub_url') || '';
    this.hubSecret = localStorage.getItem('mediposs_hub_secret') || '';
    
    this.isFirebaseConnected = false;
    this.isLiveConnected = false;
    this.firestoreDb = null;
    this.unsubscribers = [];

    // Initialize Firebase
    this.initFirebase();
  }

  save() {
    localStorage.setItem('mediposs_user', JSON.stringify(this.currentUser));
    localStorage.setItem('mediposs_meds', JSON.stringify(this.medicines));
    localStorage.setItem('mediposs_sales', JSON.stringify(this.sales));
    localStorage.setItem('mediposs_appointments', JSON.stringify(this.appointments));
    localStorage.setItem('mediposs_transfers', JSON.stringify(this.transfers));
    localStorage.setItem('mediposs_users_list', JSON.stringify(this.users));
    if (this.baselineDate) localStorage.setItem('mediposs_baseline_date', this.baselineDate);
    localStorage.setItem('mediposs_baseline_stock', JSON.stringify(this.baselineStock));
    localStorage.setItem('mediposs_shop_id', this.shopId);
  }

  async initFirebase() {
    try {
      if (!window.firebase || !window.firebase.apps) {
        console.warn('Firebase SDK not loaded, working in cached/local mode.');
        this.updateSyncBadge(false, 'Local Offline Mode');
        return;
      }

      if (!window.firebase.apps.length) {
        window.firebase.initializeApp(FIREBASE_CONFIG);
      }

      this.firestoreDb = window.firebase.firestore();
      
      // Attempt anonymous auth if enabled
      try {
        await window.firebase.auth().signInAnonymously();
      } catch (authErr) {
        console.warn('Firebase anonymous auth note:', authErr.message);
      }

      this.isFirebaseConnected = true;
      this.updateSyncBadge(true, `Cloud: ${this.shopId}`);

      // Auto-listen to real-time collections for this shop
      this.subscribeToShopData(this.shopId);
    } catch (err) {
      console.error('Firebase initialization error:', err);
      this.isFirebaseConnected = false;
      this.updateSyncBadge(false, 'Local Offline Mode');
    }
  }

  updateSyncBadge(online, text) {
    const dot = document.getElementById('topbarSyncDot');
    const label = document.getElementById('topbarSyncText');
    if (dot) dot.style.background = online ? '#22c55e' : '#f59e0b';
    if (label) label.innerText = text;
  }

  // Real-time Firestore Listeners
  subscribeToShopData(shopId) {
    if (!this.firestoreDb) return;

    // Unsubscribe previous listeners if any
    this.unsubscribers.forEach(unsub => {
      try { unsub(); } catch (_) {}
    });
    this.unsubscribers = [];

    const shopRef = this.firestoreDb.collection('shops').doc(shopId);

    // 1. Listen to Medicines
    const unsubMeds = shopRef.collection('medicines').onSnapshot(snapshot => {
      const cloudMeds = [];
      snapshot.forEach(doc => {
        const d = doc.data();
        cloudMeds.push({
          id: d.id || doc.id,
          name: d.name || 'Unnamed',
          barcode: d.barcode || '',
          category: d.category || 'General',
          unit: d.unit || 'Unit',
          purchasePrice: parseFloat(d.purchasePrice) || 0,
          sellingPrice: parseFloat(d.sellingPrice) || 0,
          storeStock: parseInt(d.storeStock, 10) || 0,
          mainStock: parseInt(d.mainStock, 10) || 0,
          bulkStoreStock: parseInt(d.bulkStoreStock, 10) || 0,
          bulkClinicStock: parseInt(d.bulkClinicStock, 10) || 0,
          lowStockThreshold: parseInt(d.lowStockThreshold, 10) || 20,
          batches: Array.isArray(d.batches) ? d.batches : []
        });
      });
      if (cloudMeds.length > 0) {
        this.medicines = cloudMeds;
        this.save();
        this.updateSyncBadge(true, `Live: ${shopId} (${cloudMeds.length} meds)`);
        if (window.renderCurrentPage) window.renderCurrentPage();
      }
    }, err => {
      console.warn('Realtime medicines sync err:', err.message);
      if (err.code === 'permission-denied') {
        this.updateSyncBadge(false, 'Firestore Permission Denied');
      }
    });
    this.unsubscribers.push(unsubMeds);

    // 2. Listen to Sales
    const unsubSales = shopRef.collection('sales').onSnapshot(snapshot => {
      const cloudSales = [];
      snapshot.forEach(doc => {
        const s = doc.data();
        const saleTotal = parseFloat(s.total != null ? s.total : s.totalAmount) || 0;
        const payMode = s.paymentMethod || s.paymentMode || 'Cash';
        const isClinic = !!(s.isClinicalDispense != null ? s.isClinicalDispense : s.isClinicDispense);
        
        let parsedItems = [];
        if (Array.isArray(s.items)) {
          parsedItems = s.items;
        } else if (typeof s.itemsJson === 'string' && s.itemsJson.trim().length > 0) {
          try { parsedItems = JSON.parse(s.itemsJson); } catch (_) { parsedItems = []; }
        }

        cloudSales.push({
          id: s.id || doc.id,
          invoiceNo: s.invoiceNo || doc.id,
          createdAt: s.createdAt || s.updatedAt || new Date().toISOString(),
          patientName: s.patientName || 'Counter Sale',
          patientPhone: s.patientPhone || '',
          patientUhid: s.patientUhid || '',
          total: saleTotal,
          totalAmount: saleTotal,
          paymentMethod: payMode,
          paymentMode: payMode,
          isReturn: !!s.isReturn,
          isClinicalDispense: isClinic,
          isClinicDispense: isClinic,
          items: parsedItems
        });
      });
      if (cloudSales.length > 0) {
        cloudSales.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
        this.sales = cloudSales;
        this.save();
        if (window.renderCurrentPage) window.renderCurrentPage();
      }
    }, err => {
      console.warn('Realtime sales sync err:', err.message);
      if (err.code === 'permission-denied') {
        this.updateSyncBadge(false, 'Firestore Permission Denied');
      }
    });
    this.unsubscribers.push(unsubSales);

    // 3. Listen to Appointments (OPD Queue)
    const unsubAppts = shopRef.collection('appointments').onSnapshot(snapshot => {
      const cloudAppts = [];
      snapshot.forEach(doc => {
        const a = doc.data();
        const tokenNum = parseInt(a.tokenNumber != null ? a.tokenNumber : a.tokenNo, 10) || 1;
        cloudAppts.push({
          id: a.id || doc.id,
          tokenNumber: tokenNum,
          tokenNo: tokenNum,
          patientName: a.patientName || 'Patient',
          patientPhone: a.patientPhone || '',
          patientUhid: a.patientUhid || '',
          doctorName: a.doctorName || 'Doctor',
          status: a.status || 'waiting',
          scheduledAt: a.scheduledAt || new Date().toISOString(),
          consultationFee: parseFloat(a.consultationFee) || 0,
          paymentMethod: a.paymentMethod || 'cash',
          notes: a.notes || ''
        });
      });
      if (cloudAppts.length > 0) {
        cloudAppts.sort((a, b) => (a.tokenNumber || 0) - (b.tokenNumber || 0));
        this.appointments = cloudAppts;
        this.save();
        if (window.renderCurrentPage) window.renderCurrentPage();
      }
    }, err => {
      console.warn('Realtime appointments sync err:', err.message);
    });
    this.unsubscribers.push(unsubAppts);

    // 4. Listen to Stock Transfers
    const unsubTransfers = shopRef.collection('stock_transfers').onSnapshot(snapshot => {
      const cloudTransfers = [];
      snapshot.forEach(doc => {
        const t = doc.data();
        cloudTransfers.push({
          id: t.id || doc.id,
          uuid: t.uuid || doc.id,
          medicineId: t.medicineId,
          medicineName: t.medicineName || 'Medicine',
          qty: parseInt(t.qty, 10) || 0,
          fromWarehouse: t.fromWarehouse || 'main',
          toWarehouse: t.toWarehouse || 'store',
          batchNo: t.batchNo || '',
          transferredAt: t.transferredAt || new Date().toISOString(),
          transferredBy: t.transferredBy || '',
          note: t.note || ''
        });
      });
      if (cloudTransfers.length > 0) {
        cloudTransfers.sort((a, b) => new Date(b.transferredAt) - new Date(a.transferredAt));
        this.transfers = cloudTransfers;
        this.save();
        if (window.renderCurrentPage) window.renderCurrentPage();
      }
    }, err => {
      console.warn('Realtime transfers sync err:', err.message);
    });
    this.unsubscribers.push(unsubTransfers);

    // 5. Listen to Users (Staff credentials)
    const unsubUsers = shopRef.collection('users').onSnapshot(snapshot => {
      const cloudUsers = [];
      snapshot.forEach(doc => {
        const u = doc.data();
        if (u.name && u.pin) {
          cloudUsers.push({
            id: u.id || doc.id,
            name: u.name,
            role: u.role || 'Staff',
            pin: String(u.pin),
            isActive: u.isActive !== false
          });
        }
      });
      if (cloudUsers.length > 0) {
        this.users = cloudUsers;
        this.save();
        if (window.renderSidebar) window.renderSidebar();
      }
    }, err => {
      console.warn('Realtime users sync err:', err.message);
    });
    this.unsubscribers.push(unsubUsers);

    // 6. Listen to Hub Status (Cloudflare Tunnel & Online check)
    const unsubHub = shopRef.collection('settings').doc('hub_status').onSnapshot(doc => {
      if (doc.exists) {
        const h = doc.data();
        if (h.cloudflareUrl && !this.hubUrl) {
          this.hubUrl = h.cloudflareUrl;
          localStorage.setItem('mediposs_hub_url', this.hubUrl);
        }
        const isOnline = !!h.hubOnline;
        this.updateSyncBadge(true, isOnline ? `Hub Online: ${shopId}` : `Cloud: ${shopId}`);
      }
    }, err => console.warn('Realtime hub_status sync err:', err.message));
    this.unsubscribers.push(unsubHub);
  }

  // Switch shop partition (e.g. if clinic has a custom shopId)
  setShopId(newShopId) {
    this.shopId = (newShopId || 'default_shop').trim();
    this.save();
    this.updateSyncBadge(true, `Cloud: ${this.shopId}`);
    this.subscribeToShopData(this.shopId);
  }

  login(user, pin) {
    if (String(user.pin) === String(pin)) {
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
