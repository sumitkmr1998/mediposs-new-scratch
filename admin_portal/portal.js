// MediPoss Admin Portal JavaScript Logic (Compat Version for file:// Protocol Support)

// 1. Firebase configuration from DefaultFirebaseOptions
const firebaseConfig = {
  apiKey: "AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs",
  projectId: "mediposs-64841",
  storageBucket: "mediposs-64841.firebasestorage.app",
  appId: "1:363693923093:android:38f68ec56eeaac9b79271c"
};

// 2. Admin Passcode (Change this as needed)
const ADMIN_PASSCODE = "Sumit@kmr1998";

// Initialize Firebase using compat SDK
firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

// Global State
let allLicenses = [];

// Expose functions globally for HTML event attributes
window.attemptLogin = attemptLogin;
window.switchTab = switchTab;
window.logout = logout;
window.generateBatchKeys = generateBatchKeys;
window.copyGeneratedKeys = copyGeneratedKeys;
window.copyToClipboard = copyToClipboard;
window.revokeLicense = revokeLicense;
window.deleteLicense = deleteLicense;
window.filterTable = filterTable;

// --- Authentication Gate ---
function attemptLogin() {
  const codeInput = document.getElementById("admin-passcode");
  const errorMsg = document.getElementById("login-error");
  
  if (codeInput.value === ADMIN_PASSCODE) {
    document.getElementById("login-screen").classList.add("hidden");
    document.getElementById("portal-container").classList.remove("hidden");
    localStorage.setItem("admin_unlocked", "true");
    initPortal();
  } else {
    errorMsg.style.display = "block";
    codeInput.value = "";
    codeInput.focus();
  }
}

// Auto-login on load if already unlocked
window.addEventListener("DOMContentLoaded", () => {
  if (localStorage.getItem("admin_unlocked") === "true") {
    document.getElementById("login-screen").classList.add("hidden");
    document.getElementById("portal-container").classList.remove("hidden");
    initPortal();
  } else {
    document.getElementById("admin-passcode").focus();
  }
});

function logout() {
  localStorage.removeItem("admin_unlocked");
  document.getElementById("portal-container").classList.add("hidden");
  document.getElementById("login-screen").classList.remove("hidden");
  document.getElementById("admin-passcode").value = "";
  document.getElementById("admin-passcode").focus();
}

// --- Navigation Tabs ---
function switchTab(tabName) {
  // Update nav class
  const items = document.querySelectorAll(".nav-item");
  items.forEach(el => el.classList.remove("active"));
  
  const contentHeader = document.querySelector(".content-header h1");
  const tabContents = document.querySelectorAll(".tab-content");
  tabContents.forEach(el => el.classList.add("hidden"));

  if (tabName === 'dashboard') {
    items[0].classList.add("active");
    document.getElementById("tab-dashboard").classList.remove("hidden");
    contentHeader.innerText = "Dashboard Overview";
  } else if (tabName === 'generate') {
    items[1].classList.add("active");
    document.getElementById("tab-generate").classList.remove("hidden");
    contentHeader.innerText = "Generate License Keys";
  } else if (tabName === 'manage') {
    items[2].classList.add("active");
    document.getElementById("tab-manage").classList.remove("hidden");
    contentHeader.innerText = "Manage Active Licenses";
  }
}

// --- Firestore Synchronization & Real-time Listeners ---
function initPortal() {
  db.collection("licenses")
    .orderBy("createdAt", "desc")
    .onSnapshot((snapshot) => {
      allLicenses = [];
      snapshot.forEach(doc => {
        allLicenses.push({
          id: doc.id,
          ...doc.data()
        });
      });
      updateStats();
      renderTable(allLicenses);
      renderRecentActivities();
    }, (error) => {
      console.error("Firestore Listen Error: ", error);
    });
}

function updateStats() {
  const total = allLicenses.length;
  const unused = allLicenses.filter(x => !x.isUsed).length;
  const pro = allLicenses.filter(x => x.isUsed && x.tier === 'pro').length;
  const enterprise = allLicenses.filter(x => x.isUsed && x.tier === 'enterprise').length;
  
  document.getElementById("stat-total").innerText = total;
  document.getElementById("stat-unused").innerText = unused;
  document.getElementById("stat-pro").innerText = pro;
  document.getElementById("stat-enterprise").innerText = enterprise;
}

// --- Render Table ---
function renderTable(data) {
  const tbody = document.getElementById("licenses-tbody");
  tbody.innerHTML = "";
  
  if (data.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" class="loading-row">No license keys found in database.</td></tr>`;
    return;
  }
  
  data.forEach(item => {
    const isUsed = item.isUsed || false;
    const tier = item.tier || "pro";
    const shopId = item.usedByShopId || "—";
    
    let statusBadge = `<span class="badge badge-green">Unused</span>`;
    let expDate = "—";
    
    if (isUsed) {
      if (item.expiresAt) {
        const expiry = new Date(item.expiresAt);
        const now = new Date();
        expDate = expiry.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
        
        if (expiry < now) {
          statusBadge = `<span class="badge badge-red">Expired</span>`;
        } else {
          statusBadge = `<span class="badge badge-yellow">Active</span>`;
        }
      } else {
        statusBadge = `<span class="badge badge-yellow">Active</span>`;
      }
    }
    
    const row = document.createElement("tr");
    row.innerHTML = `
      <td><span class="key-code">${item.id}</span></td>
      <td><span class="badge badge-tier">${tier.toUpperCase()}</span></td>
      <td>${statusBadge}</td>
      <td>${item.durationDays || 365} Days</td>
      <td>${shopId}</td>
      <td>${expDate}</td>
      <td>
        <div class="action-btns">
          <button class="btn-icon" title="Copy Key" onclick="copyToClipboard('${item.id}')">
            <i class="fa-solid fa-copy"></i>
          </button>
          ${isUsed ? `
            <button class="btn-icon btn-delete" title="Reset/Revoke Key" onclick="revokeLicense('${item.id}')">
              <i class="fa-solid fa-rotate-left"></i>
            </button>
          ` : ''}
          <button class="btn-icon btn-delete" title="Delete Key" onclick="deleteLicense('${item.id}')">
            <i class="fa-solid fa-trash"></i>
          </button>
        </div>
      </td>
    `;
    tbody.appendChild(row);
  });
}

function renderRecentActivities() {
  const list = document.getElementById("recent-activities");
  list.innerHTML = "";
  
  // Show last 5 activities
  const recent = allLicenses
    .filter(x => x.isUsed)
    .sort((a, b) => new Date(b.activatedAt) - new Date(a.activatedAt))
    .slice(0, 5);
    
  if (recent.length === 0) {
    list.innerHTML = `<li>No recent activations.</li>`;
    return;
  }
  
  recent.forEach(x => {
    const date = new Date(x.activatedAt).toLocaleDateString('en-IN', {
      day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
    });
    const li = document.createElement("li");
    li.innerHTML = `
      <span class="act-title">Shop <strong>${x.usedByShopId}</strong> activated ${x.tier.toUpperCase()} plan</span>
      <span class="act-time"><i class="fa-solid fa-clock"></i> ${date}</span>
    `;
    list.appendChild(li);
  });
}

// --- Filter Table ---
function filterTable() {
  const q = document.getElementById("search-input").value.toLowerCase();
  const filtered = allLicenses.filter(x => 
    x.id.toLowerCase().includes(q) || 
    (x.usedByShopId && x.usedByShopId.toLowerCase().includes(q))
  );
  renderTable(filtered);
}

// --- Key Generation algorithm ---
function generateBatchKeys() {
  const tier = document.getElementById("gen-tier").value;
  const duration = parseInt(document.getElementById("gen-duration").value) || 365;
  const count = parseInt(document.getElementById("gen-count").value) || 1;
  
  const createdKeys = [];
  const promises = [];
  
  const prefix = tier === 'enterprise' ? 'MP-ENT' : 'MP-PRO';
  
  for (let i = 0; i < count; i++) {
    // Generate secure random key format: MP-PRO-XXXX-XXXX-XXXX
    const randSegment = () => Math.random().toString(36).substring(2, 6).toUpperCase();
    const key = `${prefix}-${randSegment()}-${randSegment()}-${randSegment()}`;
    
    createdKeys.push(key);
    
    // Add to Firebase via compat SDK
    const docRef = db.collection("licenses").doc(key);
    const p = docRef.set({
      tier: tier,
      durationDays: duration,
      isUsed: false,
      createdAt: new Date().toISOString()
    });
    promises.push(p);
  }
  
  Promise.all(promises).then(() => {
    const resultBox = document.getElementById("generation-result");
    const output = document.getElementById("keys-output");
    output.value = createdKeys.join("\n");
    resultBox.classList.remove("hidden");
  }).catch(e => {
    alert("Error creating keys: " + e);
  });
}

function copyGeneratedKeys() {
  const output = document.getElementById("keys-output");
  output.select();
  document.execCommand("copy");
  alert("All generated keys copied to clipboard!");
}

function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(() => {
    alert("Key copied to clipboard: " + text);
  });
}

// --- Database Modifications (Revoke & Delete) ---
function revokeLicense(key) {
  if (confirm(`Are you sure you want to reset key ${key}? This will revoke premium access from the current shop and allow the key to be reused.`)) {
    db.collection("licenses").doc(key).update({
      isUsed: false,
      usedByShopId: "",
      activatedAt: "",
      expiresAt: ""
    }).then(() => {
      alert("License key successfully reset!");
    }).catch(e => {
      alert("Error resetting key: " + e);
    });
  }
}

function deleteLicense(key) {
  if (confirm(`Are you sure you want to delete license key ${key}? This action is permanent.`)) {
    db.collection("licenses").doc(key).delete().then(() => {
      alert("License key deleted from database.");
    }).catch(e => {
      alert("Error deleting key: " + e);
    });
  }
}
