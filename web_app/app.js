// MediPoss Web App - UI Controller & Rendering Engine

document.addEventListener('DOMContentLoaded', () => {
  initApp();
});

let currentView = 'dashboard';
let currentAnalysisTab = 'explorer';
let activeUserForPin = null;
let currentEnteredPin = '';
let replenishmentDays = 15;
let reorderTrendDays = 30;
let reorderDepletionDays = 90;
let reorderTargetDays = 365;
let reconcileScope = 'all'; // all, clinic, store
let reconcileSearch = '';

function initApp() {
  renderSidebar();
  checkAuthAndRender();
}

function checkAuthAndRender() {
  const loginOverlay = document.getElementById('loginOverlay');
  if (!appState.currentUser) {
    loginOverlay.style.display = 'flex';
    renderLoginScreen();
  } else {
    loginOverlay.style.display = 'none';
    renderCurrentPage();
  }
}

// ----------------- LOGIN SCREEN -----------------
function renderLoginScreen() {
  const container = document.getElementById('loginContainer');
  if (!activeUserForPin) {
    // User Selection view
    container.innerHTML = `
      <div style="margin-bottom: 20px;">
        <div class="logo-badge" style="margin: 0 auto 12px; width: 44px; height: 44px;">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 2v20M2 12h20"/></svg>
        </div>
        <h2 style="font-size: 20px; font-weight: 800;">MediPoss Cloud Web</h2>
        <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Select staff profile to sign in</p>
      </div>

      <div style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 16px;">
        ${(appState.users || DEFAULT_USERS).map(u => `
          <button class="btn btn-outline" style="justify-content: flex-start; padding: 12px 16px; border-radius: var(--radius-md);" onclick="selectUserForLogin(${u.id})">
            <div class="user-avatar" style="width: 28px; height: 28px; font-size: 12px;">${u.name.substring(0, 1)}</div>
            <div style="text-align: left; margin-left: 6px;">
              <div style="font-weight: 700; font-size: 13px;">${u.name}</div>
              <div style="font-size: 11px; color: var(--text-dim);">${u.role} (PIN: ${u.pin})</div>
            </div>
            <svg style="margin-left: auto; width: 16px; height: 16px; color: var(--text-dim);" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>
          </button>
        `).join('')}
      </div>

      <div style="font-size: 11px; color: var(--text-dim); border-top: 1px solid var(--border-subtle); padding-top: 12px;">
        Default Admin PIN: <strong style="color: var(--primary-light);">1234</strong>
      </div>
    `;
  } else {
    // PIN entry view
    container.innerHTML = `
      <div style="margin-bottom: 12px;">
        <button class="btn btn-outline btn-sm" style="margin-bottom: 12px;" onclick="cancelUserPin()">← Change User</button>
        <div class="user-avatar" style="margin: 0 auto 8px; width: 44px; height: 44px; font-size: 16px;">${activeUserForPin.name.substring(0,1)}</div>
        <h3 style="font-size: 16px; font-weight: 800;">${activeUserForPin.name}</h3>
        <p style="font-size: 12px; color: var(--text-muted);">${activeUserForPin.role} • Enter 4-digit PIN</p>
      </div>

      <div class="pin-dots" id="pinDots">
        <div class="pin-dot ${currentEnteredPin.length >= 1 ? 'filled' : ''}"></div>
        <div class="pin-dot ${currentEnteredPin.length >= 2 ? 'filled' : ''}"></div>
        <div class="pin-dot ${currentEnteredPin.length >= 3 ? 'filled' : ''}"></div>
        <div class="pin-dot ${currentEnteredPin.length >= 4 ? 'filled' : ''}"></div>
      </div>

      <div id="pinError" style="color: var(--danger); font-size: 12px; height: 18px; margin-bottom: 6px;"></div>

      <div class="numpad-grid">
        ${[1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => `
          <div class="num-key" onclick="pressPinDigit('${n}')">${n}</div>
        `).join('')}
        <div class="num-key" onclick="clearPin()" style="font-size: 13px; color: var(--text-muted);">C</div>
        <div class="num-key" onclick="pressPinDigit('0')">0</div>
        <div class="num-key" onclick="backspacePin()">⌫</div>
      </div>
    `;
  }
}

window.selectUserForLogin = (userId) => {
  activeUserForPin = DEFAULT_USERS.find(u => u.id === userId);
  currentEnteredPin = '';
  renderLoginScreen();
};

window.cancelUserPin = () => {
  activeUserForPin = null;
  currentEnteredPin = '';
  renderLoginScreen();
};

window.pressPinDigit = (digit) => {
  if (currentEnteredPin.length < 4) {
    currentEnteredPin += digit;
    renderLoginScreen();
    if (currentEnteredPin.length === 4) {
      setTimeout(verifyPinAndLogin, 120);
    }
  }
};

window.clearPin = () => {
  currentEnteredPin = '';
  renderLoginScreen();
};

window.backspacePin = () => {
  if (currentEnteredPin.length > 0) {
    currentEnteredPin = currentEnteredPin.slice(0, -1);
    renderLoginScreen();
  }
};

function verifyPinAndLogin() {
  const errElem = document.getElementById('pinError');
  if (appState.login(activeUserForPin, currentEnteredPin)) {
    activeUserForPin = null;
    currentEnteredPin = '';
    checkAuthAndRender();
  } else {
    if (errElem) errElem.innerText = 'Incorrect PIN. Please try again.';
    currentEnteredPin = '';
    setTimeout(renderLoginScreen, 600);
  }
}

// ----------------- SIDEBAR NAVIGATION -----------------
function renderSidebar() {
  const user = appState.currentUser;
  const userRole = user ? user.role : 'Guest';
  const userName = user ? user.name : 'Not Logged In';

  document.getElementById('sidebarUserPill').innerHTML = `
    <div class="user-pill">
      <div class="user-avatar">${userName.substring(0, 1)}</div>
      <div class="user-info">
        <div style="font-size: 12px; font-weight: 700;">${userName}</div>
        <div style="font-size: 10px; color: var(--text-dim);">${userRole}</div>
      </div>
    </div>
    ${user ? `<button class="btn btn-outline btn-sm" onclick="appState.logout(); checkAuthAndRender();" title="Log Out" style="padding: 6px 8px;">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
    </button>` : ''}
  `;

  const navItems = [
    { id: 'dashboard', label: 'Dashboard', icon: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>' },
    { id: 'sales', label: 'Sales History', icon: '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/>' },
    { id: 'opd', label: 'OPD Queue', icon: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>' },
    { id: 'analysis', label: 'Analysis Hub', icon: '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>' }
  ];

  document.getElementById('navItemsContainer').innerHTML = navItems.map(item => `
    <div class="nav-item ${currentView === item.id ? 'active' : ''}" onclick="switchView('${item.id}')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">${item.icon}</svg>
      <span>${item.label}</span>
    </div>
  `).join('');
}

window.switchView = (viewId) => {
  currentView = viewId;
  renderSidebar();
  renderCurrentPage();
};

function renderCurrentPage() {
  const container = document.getElementById('pageContent');
  const titleBox = document.getElementById('topPageTitleBox');

  switch (currentView) {
    case 'dashboard':
      titleBox.innerHTML = `<h1>Dashboard</h1><p>Real-time overview of clinic and store metrics</p>`;
      renderDashboard(container);
      break;
    case 'sales':
      titleBox.innerHTML = `<h1>Sales History</h1><p>Full transaction register & clinical dispenses</p>`;
      renderSalesHistory(container);
      break;
    case 'opd':
      titleBox.innerHTML = `<h1>OPD Queue</h1><p>Daily patient queue, doctor visit & dispensing status</p>`;
      renderOpdQueue(container);
      break;
    case 'analysis':
      titleBox.innerHTML = `<h1>Analysis Hub</h1><p>Stock explorer, replenishment, reorder & audit reconciliation</p>`;
      renderAnalysisHub(container);
      break;
  }
}

// ----------------- DASHBOARD -----------------
function renderDashboard(container) {
  const totalRevenue = appState.sales.reduce((sum, s) => sum + s.total, 0);
  const totalSalesCount = appState.sales.length;
  const opdCount = appState.appointments.length;
  
  // Replenishment Count: Store + Clinic stock below 15-day buffer
  let lowDispensingCount = 0;
  for (const med of appState.medicines) {
    const dispensing = appState.getDispensingStock(med);
    const daily = appState.getDailyRate(med, 30);
    const required = daily > 0 ? Math.ceil(daily * 15) : med.lowStockThreshold;
    if (dispensing < required) lowDispensingCount++;
  }

  container.innerHTML = `
    <div class="grid-cards">
      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-title">Total Revenue</span>
          <div class="kpi-icon" style="background: var(--emerald-bg); color: var(--emerald);">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
          </div>
        </div>
        <div class="kpi-value">₹${totalRevenue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</div>
        <div class="kpi-footer"><span style="color: var(--emerald); font-weight: 700;">▲ +8.2%</span> from last period</div>
      </div>

      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-title">Transactions</span>
          <div class="kpi-icon" style="background: var(--cyan-bg); color: var(--cyan);">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
          </div>
        </div>
        <div class="kpi-value">${totalSalesCount}</div>
        <div class="kpi-footer"><span style="color: var(--cyan); font-weight: 700;">Retail + Clinic</span> invoices</div>
      </div>

      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-title">OPD Patients</span>
          <div class="kpi-icon" style="background: var(--indigo-bg); color: var(--indigo);">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><polyline points="17 11 19 13 23 9"/></svg>
          </div>
        </div>
        <div class="kpi-value">${opdCount}</div>
        <div class="kpi-footer"><span style="color: var(--indigo); font-weight: 700;">Active queue</span> today</div>
      </div>

      <div class="kpi-card" onclick="switchView('analysis'); selectAnalysisTab('replenishment');" style="cursor: pointer;">
        <div class="kpi-top">
          <span class="kpi-title">Replenish Needed</span>
          <div class="kpi-icon" style="background: var(--orange-bg); color: var(--orange);">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
          </div>
        </div>
        <div class="kpi-value" style="color: var(--orange);">${lowDispensingCount} Meds</div>
        <div class="kpi-footer">Store+Clinic below 15-day buffer →</div>
      </div>
    </div>

    <!-- Quick Overview Tables -->
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
      <div class="table-container">
        <div class="table-toolbar">
          <div style="font-weight: 800; font-size: 14px;">Recent OPD Queue</div>
          <button class="btn btn-outline btn-sm" onclick="switchView('opd')">View All</button>
        </div>
        <table class="app-table">
          <thead>
            <tr>
              <th>Token</th>
              <th>Patient</th>
              <th>Status</th>
              <th>Doctor</th>
            </tr>
          </thead>
          <tbody>
            ${appState.appointments.slice(0, 4).map(a => `
              <tr>
                <td><strong style="color: var(--primary-light);">#${a.tokenNumber}</strong></td>
                <td>
                  <div style="font-weight: 700;">${a.patientName}</div>
                  <div style="font-size: 11px; color: var(--text-dim);">${a.patientPhone}</div>
                </td>
                <td>${getApptStatusBadge(a.status)}</td>
                <td style="color: var(--text-muted);">${a.doctorName}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>

      <div class="table-container">
        <div class="table-toolbar">
          <div style="font-weight: 800; font-size: 14px;">Recent Sales & Dispenses</div>
          <button class="btn btn-outline btn-sm" onclick="switchView('sales')">View All</button>
        </div>
        <table class="app-table">
          <thead>
            <tr>
              <th>Invoice</th>
              <th>Patient</th>
              <th>Type</th>
              <th>Amount</th>
            </tr>
          </thead>
          <tbody>
            ${appState.sales.slice(0, 4).map(s => `
              <tr>
                <td><strong style="font-size: 12px;">${s.invoiceNo}</strong></td>
                <td>${s.patientName}</td>
                <td><span class="badge ${s.isClinicalDispense ? 'badge-indigo' : 'badge-emerald'}">${s.isClinicalDispense ? 'Clinic' : 'Retail'}</span></td>
                <td><strong style="color: var(--emerald);">₹${s.total.toFixed(2)}</strong></td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>
  `;
}

// ----------------- SALES HISTORY -----------------
function renderSalesHistory(container) {
  container.innerHTML = `
    <div class="table-container">
      <div class="table-toolbar">
        <div class="search-input-box">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
          <input type="text" id="salesSearchInput" placeholder="Search invoice, patient, or phone..." oninput="filterSalesTable()">
        </div>
        <div style="display: flex; gap: 8px;">
          <button class="btn btn-outline btn-sm" onclick="downloadSalesCSV()">Export CSV</button>
        </div>
      </div>

      <table class="app-table">
        <thead>
          <tr>
            <th>Invoice No</th>
            <th>Date & Time</th>
            <th>Patient Details</th>
            <th>Type</th>
            <th>Payment</th>
            <th>Items Count</th>
            <th>Total Amount</th>
          </tr>
        </thead>
        <tbody id="salesTableBody">
          ${renderSalesRows(appState.sales)}
        </tbody>
      </table>
    </div>
  `;
}

function renderSalesRows(salesList) {
  if (salesList.length === 0) {
    return `<tr><td colspan="7" style="text-align: center; color: var(--text-dim); padding: 30px;">No transactions found</td></tr>`;
  }
  return salesList.map(s => `
    <tr>
      <td>
        <strong style="color: var(--primary-light);">${s.invoiceNo}</strong>
      </td>
      <td style="color: var(--text-muted); font-size: 12px;">${new Date(s.createdAt).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}</td>
      <td>
        <div style="font-weight: 700;">${s.patientName}</div>
        <div style="font-size: 11px; color: var(--text-dim);">${s.patientPhone || s.patientUhid || 'Walk-in'}</div>
      </td>
      <td>
        <span class="badge ${s.isClinicalDispense ? 'badge-indigo' : 'badge-emerald'}">
          ${s.isClinicalDispense ? 'Clinic Dispense' : 'Retail Sale'}
        </span>
      </td>
      <td><span class="badge badge-cyan">${s.paymentMethod}</span></td>
      <td>${(s.items || []).length} items</td>
      <td><strong style="color: var(--emerald); font-size: 14px;">₹${s.total.toFixed(2)}</strong></td>
    </tr>
  `).join('');
}

window.filterSalesTable = () => {
  const query = (document.getElementById('salesSearchInput').value || '').toLowerCase().trim();
  const filtered = appState.sales.filter(s => 
    s.invoiceNo.toLowerCase().includes(query) ||
    s.patientName.toLowerCase().includes(query) ||
    (s.patientPhone && s.patientPhone.includes(query))
  );
  document.getElementById('salesTableBody').innerHTML = renderSalesRows(filtered);
};

window.downloadSalesCSV = () => {
  let csv = "Invoice,Date,Patient,Phone,Type,Payment,Total\n";
  for (const s of appState.sales) {
    csv += `"${s.invoiceNo}","${s.createdAt}","${s.patientName}","${s.patientPhone || ''}","${s.isClinicalDispense ? 'Clinic' : 'Retail'}","${s.paymentMethod}",${s.total}\n`;
  }
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.setAttribute('href', url);
  a.setAttribute('download', `Sales_History_${Date.now()}.csv`);
  a.click();
};

// ----------------- OPD QUEUE -----------------
function renderOpdQueue(container) {
  const waiting = appState.appointments.filter(a => a.status === 'waiting');
  const withDoctor = appState.appointments.filter(a => a.status === 'with_doctor');
  const pharmacy = appState.appointments.filter(a => a.status === 'pharmacy');
  const done = appState.appointments.filter(a => a.status === 'done');

  container.innerHTML = `
    <!-- KPI Row -->
    <div class="grid-cards" style="grid-template-columns: repeat(4, 1fr); margin-bottom: 20px;">
      <div class="kpi-card" style="border-left: 4px solid var(--orange);">
        <div class="kpi-title">Waiting</div>
        <div class="kpi-value" style="color: var(--orange);">${waiting.length}</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--indigo);">
        <div class="kpi-title">With Doctor</div>
        <div class="kpi-value" style="color: var(--indigo);">${withDoctor.length}</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--cyan);">
        <div class="kpi-title">Pharmacy Dispense</div>
        <div class="kpi-value" style="color: var(--cyan);">${pharmacy.length}</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--emerald);">
        <div class="kpi-title">Completed</div>
        <div class="kpi-value" style="color: var(--emerald);">${done.length}</div>
      </div>
    </div>

    <!-- OPD Queue Table -->
    <div class="table-container">
      <div class="table-toolbar">
        <div style="font-weight: 800; font-size: 14px;">Today's Live Queue</div>
        <span class="badge badge-emerald">Real-time sync</span>
      </div>

      <table class="app-table">
        <thead>
          <tr>
            <th>Token</th>
            <th>Time</th>
            <th>Patient</th>
            <th>UHID</th>
            <th>Consultation Fee</th>
            <th>Status</th>
            <th>Clinical Notes</th>
          </tr>
        </thead>
        <tbody>
          ${appState.appointments.map(a => `
            <tr>
              <td><span class="badge badge-indigo" style="font-size: 13px; padding: 4px 10px;">Token #${a.tokenNumber}</span></td>
              <td style="color: var(--text-muted); font-size: 12px;">${a.scheduledAt}</td>
              <td>
                <div style="font-weight: 700;">${a.patientName}</div>
                <div style="font-size: 11px; color: var(--text-dim);">${a.patientPhone}</div>
              </td>
              <td style="font-family: monospace; font-size: 12px; color: var(--text-muted);">${a.patientUhid}</td>
              <td><strong>₹${a.consultationFee.toFixed(2)}</strong> <span style="font-size: 11px; color: var(--text-dim);">(${a.paymentMethod})</span></td>
              <td>${getApptStatusBadge(a.status)}</td>
              <td style="color: var(--text-muted); font-size: 12px; max-width: 260px;">${a.notes || '—'}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function getApptStatusBadge(status) {
  switch (status) {
    case 'waiting': return `<span class="badge badge-orange">⏳ Waiting</span>`;
    case 'with_doctor': return `<span class="badge badge-indigo">🩺 In Cabin</span>`;
    case 'pharmacy': return `<span class="badge badge-cyan">💊 Pharmacy Dispense</span>`;
    case 'done': return `<span class="badge badge-emerald">✓ Completed</span>`;
    default: return `<span class="badge">${status}</span>`;
  }
}

// ----------------- ANALYSIS HUB -----------------
function renderAnalysisHub(container) {
  container.innerHTML = `
    <!-- Analysis Sub-Tabs -->
    <div class="sub-tabs">
      <button class="sub-tab-btn ${currentAnalysisTab === 'explorer' ? 'active' : ''}" onclick="selectAnalysisTab('explorer')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        Stock Explorer
      </button>
      <button class="sub-tab-btn ${currentAnalysisTab === 'replenishment' ? 'active' : ''}" onclick="selectAnalysisTab('replenishment')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg>
        Replenishment Planner
      </button>
      <button class="sub-tab-btn ${currentAnalysisTab === 'reorder' ? 'active' : ''}" onclick="selectAnalysisTab('reorder')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
        Reorder & Dead Stock
      </button>
      <button class="sub-tab-btn ${currentAnalysisTab === 'reconcile' ? 'active' : ''}" onclick="selectAnalysisTab('reconcile')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
        Reconciliation & Audit
      </button>
    </div>

    <div id="analysisTabBody"></div>
  `;

  renderAnalysisTabContent();
}

window.selectAnalysisTab = (tabName) => {
  currentAnalysisTab = tabName;
  document.querySelectorAll('.sub-tab-btn').forEach(btn => btn.classList.remove('active'));
  renderAnalysisTabContent();
};

function renderAnalysisTabContent() {
  const tabBody = document.getElementById('analysisTabBody');
  if (!tabBody) return;

  switch (currentAnalysisTab) {
    case 'explorer': renderStockExplorer(tabBody); break;
    case 'replenishment': renderReplenishment(tabBody); break;
    case 'reorder': renderReorder(tabBody); break;
    case 'reconcile': renderReconcile(tabBody); break;
  }
}

// 1. Stock Explorer Tab
function renderStockExplorer(tabBody) {
  tabBody.innerHTML = `
    <div class="table-container">
      <div class="table-toolbar">
        <div class="search-input-box">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
          <input type="text" id="explorerSearch" placeholder="Search medicine name or category..." oninput="filterExplorerTable()">
        </div>
        <div style="font-size: 12px; color: var(--text-muted);">
          Total Medicines: <strong>${appState.medicines.length}</strong>
        </div>
      </div>

      <table class="app-table">
        <thead>
          <tr>
            <th>Medicine Name</th>
            <th>Category</th>
            <th>Store Dispensing</th>
            <th>Clinic Dispensing</th>
            <th>Combined Dispensing</th>
            <th>Bulk Warehouse</th>
            <th>30d Velocity</th>
            <th>Days Left</th>
          </tr>
        </thead>
        <tbody id="explorerTableBody">
          ${renderExplorerRows(appState.medicines)}
        </tbody>
      </table>
    </div>
  `;
}

function renderExplorerRows(meds) {
  return meds.map(m => {
    const dispensing = appState.getDispensingStock(m);
    const bulk = appState.getTotalBulkStock(m);
    const daily = appState.getDailyRate(m, 30);
    const daysLeft = appState.getDaysRemaining(m);

    return `
      <tr>
        <td><strong style="color: var(--text-main);">${m.name}</strong></td>
        <td><span class="badge">${m.category}</span></td>
        <td>${m.storeStock}</td>
        <td>${m.mainStock}</td>
        <td><strong style="color: var(--primary-light);">${dispensing} units</strong></td>
        <td style="color: var(--text-dim);">${bulk} units</td>
        <td>${daily.toFixed(1)} /day</td>
        <td>
          <span class="badge ${daysLeft < 15 ? 'badge-danger' : (daysLeft < 30 ? 'badge-orange' : 'badge-emerald')}">
            ${daysLeft >= 999 ? 'No sales' : `${Math.round(daysLeft)} days`}
          </span>
        </td>
      </tr>
    `;
  }).join('');
}

window.filterExplorerTable = () => {
  const query = (document.getElementById('explorerSearch').value || '').toLowerCase().trim();
  const filtered = appState.medicines.filter(m => 
    m.name.toLowerCase().includes(query) || m.category.toLowerCase().includes(query)
  );
  document.getElementById('explorerTableBody').innerHTML = renderExplorerRows(filtered);
};

// 2. Replenishment Tab (BOTH Store + Clinic in consideration)
function renderReplenishment(tabBody) {
  const items = [];
  for (const med of appState.medicines) {
    const dispensingStock = appState.getDispensingStock(med); // Store + Clinic
    const daily = appState.getDailyRate(med, 30);
    const requiredStock = daily > 0 ? Math.ceil(daily * replenishmentDays) : med.lowStockThreshold;
    const deficit = requiredStock > dispensingStock ? (requiredStock - dispensingStock) : 0;
    const isLow = dispensingStock < requiredStock;
    const bulkStock = appState.getTotalBulkStock(med);

    if (isLow) {
      items.push({
        med,
        dispensingStock,
        daily,
        requiredStock,
        deficit,
        bulkStock,
        canFulfill: bulkStock >= deficit
      });
    }
  }

  items.sort((a, b) => b.deficit - a.deficit);
  const totalDeficit = items.reduce((sum, i) => sum + i.deficit, 0);

  tabBody.innerHTML = `
    <!-- Top Configuration Header -->
    <div style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: var(--radius-lg); padding: 18px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px;">
      <div>
        <div style="font-weight: 800; font-size: 15px;">Store & Clinic Replenishment Planner</div>
        <p style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">
          Evaluates shortages across combined <strong>Store + Clinic</strong> dispensing stock against consumption velocity.
        </p>
      </div>

      <div style="display: flex; align-items: center; gap: 10px;">
        <span style="font-size: 12px; font-weight: 700; color: var(--text-muted);">Target Buffer:</span>
        ${[7, 15, 30, 45].map(d => `
          <button class="btn ${replenishmentDays === d ? 'btn-primary' : 'btn-outline'} btn-sm" onclick="setReplenishmentBuffer(${d})">
            ${d} Days
          </button>
        `).join('')}
      </div>
    </div>

    <!-- KPI Summary Row -->
    <div class="grid-cards" style="grid-template-columns: repeat(3, 1fr); margin-bottom: 20px;">
      <div class="kpi-card" style="border-left: 4px solid var(--orange);">
        <div class="kpi-title">Meds Needing Replenishment</div>
        <div class="kpi-value" style="color: var(--orange);">${items.length}</div>
        <div class="kpi-footer">Store+Clinic below ${replenishmentDays}d target</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--primary-light);">
        <div class="kpi-title">Total Transfer Deficit</div>
        <div class="kpi-value" style="color: var(--primary-light);">${totalDeficit} Units</div>
        <div class="kpi-footer">Combined units required on floor</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--emerald);">
        <div class="kpi-title">Covered by Bulk Warehouse</div>
        <div class="kpi-value" style="color: var(--emerald);">${items.filter(i => i.canFulfill).length} / ${items.length}</div>
        <div class="kpi-footer">Meds with ready stock in bulk</div>
      </div>
    </div>

    <!-- Replenishment Table -->
    <div class="table-container">
      <div class="table-toolbar">
        <div style="font-weight: 800; font-size: 14px;">Shortage Register</div>
        <span style="font-size: 12px; color: var(--text-dim);">${items.length} items flagged</span>
      </div>

      <table class="app-table">
        <thead>
          <tr>
            <th>Medicine</th>
            <th>Store Stock</th>
            <th>Clinic Stock</th>
            <th>Dispensing Total</th>
            <th>30d Daily Avg</th>
            <th>Req. Buffer (${replenishmentDays}d)</th>
            <th>Deficit</th>
            <th>Bulk Warehouse</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          ${items.length === 0 ? `
            <tr><td colspan="9" style="text-align: center; color: var(--emerald); padding: 40px; font-weight: 700;">
              ✓ All store and clinic dispensing stocks meet or exceed the ${replenishmentDays}-day buffer!
            </td></tr>
          ` : items.map(i => `
            <tr>
              <td>
                <div style="font-weight: 800;">${i.med.name}</div>
                <div style="font-size: 11px; color: var(--text-dim);">${i.med.category}</div>
              </td>
              <td>${i.med.storeStock}</td>
              <td>${i.med.mainStock}</td>
              <td><strong style="color: var(--orange);">${i.dispensingStock}</strong></td>
              <td>${i.daily.toFixed(1)} /day</td>
              <td>${i.requiredStock} units</td>
              <td>
                <span class="badge badge-danger">-${i.deficit}</span>
              </td>
              <td>
                <strong style="color: ${i.canFulfill ? 'var(--emerald)' : 'var(--orange)'};">${i.bulkStock}</strong>
                <span style="font-size: 11px; color: var(--text-dim);">(${i.canFulfill ? 'Available' : 'Shortage'})</span>
              </td>
              <td>
                <button class="btn btn-outline btn-sm" onclick="quickTransfer('${i.med.id}', ${i.deficit})">Transfer</button>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

window.setReplenishmentBuffer = (days) => {
  replenishmentDays = days;
  renderAnalysisTabContent();
};

window.quickTransfer = (medId, qty) => {
  const med = appState.medicines.find(m => m.id == medId);
  if (!med) return;
  const targetQty = prompt(`Transfer quantity for ${med.name} (from Bulk to Clinic/Store):`, qty);
  if (targetQty && !isNaN(targetQty) && parseInt(targetQty, 10) > 0) {
    const count = parseInt(targetQty, 10);
    // Reduce bulk, increase clinic dispensing
    if (med.bulkStoreStock >= count) {
      med.bulkStoreStock -= count;
    } else {
      med.bulkClinicStock = Math.max(0, med.bulkClinicStock - count);
    }
    med.mainStock += count;
    appState.save();
    renderAnalysisTabContent();
    alert(`Transferred ${count} units of ${med.name} to Clinic dispensing!`);
  }
};

// 3. Reorder & Dead Stock Tab
function renderReorder(tabBody) {
  const items = [];
  const deadStock = [];

  for (const med of appState.medicines) {
    const totalStock = (med.storeStock || 0) + (med.mainStock || 0) + (med.bulkStoreStock || 0) + (med.bulkClinicStock || 0);
    const daily = appState.getDailyRate(med, reorderTrendDays);
    const daysRemaining = daily > 0 ? (totalStock / daily) : 999;

    if (daily <= 0.05 && totalStock > 0) {
      deadStock.push({ med, totalStock });
    } else if (daysRemaining <= reorderDepletionDays) {
      const targetStock = Math.ceil(daily * reorderTargetDays);
      const reorderQty = Math.max(0, targetStock - totalStock);
      items.push({ med, totalStock, daily, daysRemaining, targetStock, reorderQty });
    }
  }

  tabBody.innerHTML = `
    <!-- Top Filter -->
    <div style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: var(--radius-lg); padding: 18px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 14px;">
      <div>
        <div style="font-weight: 800; font-size: 15px;">Automated Procurement & Reorder Suggestions</div>
        <p style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">Calculated using sales velocity, depletion thresholds, and annual procurement targets.</p>
      </div>

      <div style="display: flex; gap: 12px; align-items: center;">
        <span style="font-size: 12px; color: var(--text-muted);">Depletion Horizon:</span>
        <select onchange="reorderDepletionDays = parseInt(this.value); renderAnalysisTabContent();" style="background: var(--bg-input); color: var(--text-main); border: 1px solid var(--border-subtle); border-radius: 6px; padding: 6px 10px;">
          <option value="60" ${reorderDepletionDays === 60 ? 'selected' : ''}>60 Days</option>
          <option value="90" ${reorderDepletionDays === 90 ? 'selected' : ''}>90 Days</option>
          <option value="120" ${reorderDepletionDays === 120 ? 'selected' : ''}>120 Days</option>
        </select>
      </div>
    </div>

    <!-- Reorder Table -->
    <div class="table-container">
      <div class="table-toolbar">
        <div style="font-weight: 800; font-size: 14px;">Purchase Reorder Recommendations (${items.length})</div>
      </div>
      <table class="app-table">
        <thead>
          <tr>
            <th>Medicine</th>
            <th>Total All Stock</th>
            <th>Daily Velocity</th>
            <th>Depletion Days</th>
            <th>Suggested Order Qty</th>
            <th>Est. Purchase Cost</th>
          </tr>
        </thead>
        <tbody>
          ${items.length === 0 ? `
            <tr><td colspan="6" style="text-align: center; color: var(--emerald); padding: 30px;">All medicines have healthy long-term coverage!</td></tr>
          ` : items.map(i => `
            <tr>
              <td><strong style="color: var(--text-main);">${i.med.name}</strong></td>
              <td>${i.totalStock} units</td>
              <td>${i.daily.toFixed(1)} /day</td>
              <td><span class="badge badge-orange">${Math.round(i.daysRemaining)} days left</span></td>
              <td><strong style="color: var(--cyan);">${i.reorderQty} units</strong></td>
              <td>₹${(i.reorderQty * i.med.purchasePrice).toFixed(2)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>

    <!-- Dead Stock Table -->
    <div class="table-container">
      <div class="table-toolbar">
        <div style="font-weight: 800; font-size: 14px; color: var(--danger);">Dead Stock Alert (Zero Sales Velocity)</div>
      </div>
      <table class="app-table">
        <thead>
          <tr>
            <th>Medicine</th>
            <th>Category</th>
            <th>Total Dormant Units</th>
            <th>Tied Up Capital</th>
          </tr>
        </thead>
        <tbody>
          ${deadStock.length === 0 ? `
            <tr><td colspan="4" style="text-align: center; color: var(--text-dim); padding: 20px;">No dead stock detected!</td></tr>
          ` : deadStock.map(d => `
            <tr>
              <td>${d.med.name}</td>
              <td><span class="badge">${d.med.category}</span></td>
              <td><strong style="color: var(--orange);">${d.totalStock} units</strong></td>
              <td>₹${(d.totalStock * d.med.purchasePrice).toFixed(2)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

// 4. Reconciliation & Audit Tab
function renderReconcile(tabBody) {
  const isBaseline = !!appState.baselineDate;
  const rows = [];

  // Build transfers map
  const transferMap = {};
  for (const t of appState.transfers) {
    if (isBaseline && new Date(t.transferredAt) < new Date(appState.baselineDate)) continue;
    const key = t.medicineName.toLowerCase().trim();
    if (t.toWarehouse === 'clinic') transferMap[key] = (transferMap[key] || 0) + t.qty;
    if (t.fromWarehouse === 'clinic') transferMap[key] = (transferMap[key] || 0) - t.qty;
  }

  // Build dispense & retail sales map
  const dispenseMap = {};
  const retailMap = {};
  for (const s of appState.sales) {
    if (isBaseline && new Date(s.createdAt) < new Date(appState.baselineDate)) continue;
    for (const item of (s.items || [])) {
      if (item.isProcedure) continue;
      const key = (item.medicineName || '').toLowerCase().trim();
      if (s.isClinicalDispense) {
        dispenseMap[key] = (dispenseMap[key] || 0) + (item.qty || 0);
      } else {
        retailMap[key] = (retailMap[key] || 0) + (item.qty || 0);
      }
    }
  }

  for (const med of appState.medicines) {
    const key = med.name.toLowerCase().trim();
    const dispensed = dispenseMap[key] || 0;
    const retail = retailMap[key] || 0;
    const netTransfer = transferMap[key] || 0;

    let baseline = 0;
    let expected = 0;
    let current = 0;

    if (reconcileScope === 'all') {
      baseline = isBaseline ? (appState.baselineStock[med.id]?.total || 0) : 0;
      current = (med.mainStock || 0) + (med.storeStock || 0);
      expected = isBaseline ? (baseline - (dispensed + retail)) : -(dispensed + retail);
    } else if (reconcileScope === 'clinic') {
      baseline = isBaseline ? (appState.baselineStock[med.id]?.clinic || 0) : 0;
      current = med.mainStock || 0;
      expected = isBaseline ? (baseline + netTransfer - dispensed) : (netTransfer - dispensed);
    } else {
      baseline = isBaseline ? (appState.baselineStock[med.id]?.store || 0) : 0;
      current = med.storeStock || 0;
      expected = isBaseline ? (baseline - netTransfer - retail) : (-netTransfer - retail);
    }

    const variance = current - expected;
    rows.push({
      med,
      baseline,
      transferred: netTransfer,
      dispensed,
      retail,
      totalOut: dispensed + retail,
      expected,
      current,
      variance
    });
  }

  const balanced = rows.filter(r => r.variance === 0).length;
  const deficit = rows.filter(r => r.variance < 0).length;
  const surplus = rows.filter(r => r.variance > 0).length;

  tabBody.innerHTML = `
    <!-- Reconciliation Header -->
    <div style="background: var(--bg-card); border: 1px solid var(--border-subtle); border-radius: var(--radius-lg); padding: 18px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 14px;">
      <div>
        <div style="font-weight: 800; font-size: 15px;">Stock Audit & Dispensary Reconciliation</div>
        <p style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">
          ${isBaseline ? `Active baseline snapshot from: <strong>${new Date(appState.baselineDate).toLocaleString('en-IN')}</strong>` : 'Cumulative all-time history (No baseline active)'}
        </p>
      </div>

      <div style="display: flex; gap: 10px;">
        <select onchange="reconcileScope = this.value; renderAnalysisTabContent();" style="background: var(--bg-input); color: var(--text-main); border: 1px solid var(--border-subtle); border-radius: 6px; padding: 6px 12px; font-weight: 600;">
          <option value="all" ${reconcileScope === 'all' ? 'selected' : ''}>Scope: All Stock (Clinic + Store)</option>
          <option value="clinic" ${reconcileScope === 'clinic' ? 'selected' : ''}>Scope: Clinic Dispensary Only</option>
          <option value="store" ${reconcileScope === 'store' ? 'selected' : ''}>Scope: Store Warehouse Only</option>
        </select>

        ${isBaseline ? `
          <button class="btn btn-outline btn-sm" onclick="appState.clearBaseline(); renderAnalysisTabContent();" style="color: var(--danger);">Clear Baseline</button>
        ` : `
          <button class="btn btn-primary btn-sm" onclick="appState.setBaseline(); renderAnalysisTabContent();">Set New Baseline</button>
        `}
      </div>
    </div>

    <!-- Status Cards -->
    <div class="grid-cards" style="grid-template-columns: repeat(3, 1fr); margin-bottom: 20px;">
      <div class="kpi-card" style="border-left: 4px solid var(--emerald);">
        <div class="kpi-title">Balanced Records</div>
        <div class="kpi-value" style="color: var(--emerald);">${balanced}</div>
        <div class="kpi-footer">Expected matches physical count</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--danger);">
        <div class="kpi-title">Deficit Discrepancies</div>
        <div class="kpi-value" style="color: var(--danger);">${deficit}</div>
        <div class="kpi-footer">System stock lower than expected</div>
      </div>
      <div class="kpi-card" style="border-left: 4px solid var(--cyan);">
        <div class="kpi-title">Surplus Discrepancies</div>
        <div class="kpi-value" style="color: var(--cyan);">${surplus}</div>
        <div class="kpi-footer">Stock higher than recorded deductions</div>
      </div>
    </div>

    <!-- Reconcile Table -->
    <div class="table-container">
      <div class="table-toolbar">
        <div style="font-weight: 800; font-size: 14px;">Audit Comparison Table</div>
        <div class="search-input-box">
          <input type="text" placeholder="Filter medicines..." oninput="reconcileSearch = this.value; renderAnalysisTabContent();" value="${reconcileSearch}">
        </div>
      </div>

      <table class="app-table">
        <thead>
          <tr>
            <th>Medicine</th>
            <th>Baseline</th>
            <th>Transferred</th>
            <th>Dispensed (OPD)</th>
            <th>Retail (Store)</th>
            <th>Expected Stock</th>
            <th>Current Stock</th>
            <th>Variance</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          ${rows.filter(r => r.med.name.toLowerCase().includes(reconcileSearch.toLowerCase().trim())).map(r => `
            <tr>
              <td><strong>${r.med.name}</strong></td>
              <td>${r.baseline}</td>
              <td>${r.transferred >= 0 ? `+${r.transferred}` : r.transferred}</td>
              <td>${r.dispensed}</td>
              <td>${r.retail}</td>
              <td><strong style="color: var(--text-muted);">${r.expected}</strong></td>
              <td><strong>${r.current}</strong></td>
              <td>
                <span class="badge ${r.variance === 0 ? 'badge-emerald' : (r.variance < 0 ? 'badge-danger' : 'badge-cyan')}">
                  ${r.variance > 0 ? `+${r.variance}` : r.variance}
                </span>
              </td>
              <td>
                ${r.variance === 0 ? '<span style="color: var(--emerald); font-weight: 700;">Balanced</span>' : 
                  (r.variance < 0 ? '<span style="color: var(--danger); font-weight: 700;">Deficit</span>' : '<span style="color: var(--cyan); font-weight: 700;">Surplus</span>')}
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

// ----------------- CLOUD & LIVE HUB CONFIG MODAL -----------------
window.openCloudConfigModal = () => {
  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.id = 'cloudModal';
  modal.innerHTML = `
    <div class="modal-card" style="max-width: 480px;">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
        <h3 style="font-size: 16px; font-weight: 800;">Realtime Cloud Setup</h3>
        <button class="btn btn-outline btn-sm" onclick="closeCloudConfigModal()">✕</button>
      </div>
      <p style="font-size: 13px; color: var(--text-muted); margin-bottom: 16px;">
        Connect this web app to your clinic's live Firebase Firestore partition or directly to your Windows Hub.
      </p>

      <div style="margin-bottom: 16px; padding: 14px; background: rgba(34, 197, 94, 0.08); border: 1px solid rgba(34, 197, 94, 0.25); border-radius: var(--radius-sm);">
        <label style="font-size: 11px; font-weight: 800; color: #22c55e; text-transform: uppercase;">Firebase Shop Partition (Active)</label>
        <p style="font-size: 11px; color: var(--text-muted); margin: 4px 0 8px;">
          Live real-time data syncs directly from Google Firebase Firestore without needing your Windows PC or Hub to be turned on.
        </p>
        <div style="display: flex; gap: 6px; margin-bottom: 8px;">
          <button type="button" class="btn btn-outline btn-sm" style="font-size: 11px; padding: 3px 8px;" onclick="document.getElementById('modalShopId').value='default_shop'">default_shop</button>
          <button type="button" class="btn btn-outline btn-sm" style="font-size: 11px; padding: 3px 8px;" onclick="document.getElementById('modalShopId').value='mediposs_pharmacy'">mediposs_pharmacy</button>
        </div>
        <div style="display: flex; gap: 8px;">
          <input type="text" id="modalShopId" placeholder="e.g. default_shop or mediposs_pharmacy" value="${appState.shopId}" style="flex: 1; background: var(--bg-input); border: 1px solid var(--border-subtle); padding: 8px 12px; border-radius: var(--radius-sm); color: var(--text-main);">
          <button class="btn btn-primary btn-sm" onclick="saveCloudShopId()">Connect Live</button>
        </div>
      </div>

      <!-- Advanced / Optional Direct Hub accordion -->
      <details style="margin-bottom: 16px; font-size: 12px; color: var(--text-muted);">
        <summary style="cursor: pointer; padding: 6px 0; font-weight: 600; color: var(--text-dim);">
          ⚙️ Advanced: Direct Windows Hub / Cloudflare Tunnel (Optional)
        </summary>
        <div style="margin-top: 8px; padding: 12px; background: var(--bg-card-subtle); border: 1px solid var(--border-subtle); border-radius: var(--radius-sm);">
          <p style="font-size: 11px; color: var(--text-muted); margin-bottom: 8px;">
            Only needed if you are NOT using Firebase and want to query your local Windows Hub directly over LAN or a Cloudflare Tunnel.
          </p>
          <input type="text" id="modalHubUrl" placeholder="https://your-tunnel.trycloudflare.com or http://192.168.1.X:8080" value="${appState.hubUrl}" style="width: 100%; margin-bottom: 8px; background: var(--bg-input); border: 1px solid var(--border-subtle); padding: 8px 12px; border-radius: var(--radius-sm); color: var(--text-main);">
          <input type="password" id="modalHubSecret" placeholder="Hub JWT Secret (optional)" value="${appState.hubSecret}" style="width: 100%; margin-bottom: 8px; background: var(--bg-input); border: 1px solid var(--border-subtle); padding: 8px 12px; border-radius: var(--radius-sm); color: var(--text-main);">
          <div style="display: flex; justify-content: flex-end;">
            <button class="btn btn-outline btn-sm" id="btnRunSync" onclick="runLiveHubSync()">Test Direct Hub</button>
          </div>
        </div>
      </details>

      <div id="modalSyncError" style="font-size: 12px; color: var(--danger); margin-bottom: 10px;"></div>

      <div style="display: flex; justify-content: flex-end;">
        <button class="btn btn-outline" onclick="closeCloudConfigModal()">Done</button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
};

window.closeCloudConfigModal = () => {
  const m = document.getElementById('cloudModal');
  if (m) m.remove();
};

window.saveCloudShopId = () => {
  const val = document.getElementById('modalShopId').value.trim();
  if (!val) return;
  appState.setShopId(val);
  closeCloudConfigModal();
  alert(`Connected to cloud shop: "${val}". Realtime listeners active.`);
};

window.runLiveHubSync = async () => {
  const url = document.getElementById('modalHubUrl').value.trim();
  const secret = document.getElementById('modalHubSecret').value.trim();
  const err = document.getElementById('modalSyncError');
  const btn = document.getElementById('btnRunSync');

  if (!url) {
    err.innerText = 'Please enter a valid URL.';
    return;
  }

  btn.innerText = 'Connecting...';
  btn.disabled = true;

  const result = await appState.syncWithHub(url, secret);
  if (result.success) {
    closeCloudConfigModal();
    alert('Connected to Windows Hub successfully! Real-time data loaded.');
    renderCurrentPage();
  } else {
    err.innerText = `Connection failed: ${result.error || 'Could not connect'}`;
    btn.innerText = 'Test Direct Hub';
    btn.disabled = false;
  }
};
