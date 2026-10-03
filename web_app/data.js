// Initial Seed Data mirroring MediPoss ObjectBox Schema
const DEFAULT_USERS = [
  { id: 1, name: "Admin", role: "Admin", pin: "1234", isActive: true },
  { id: 2, name: "Dr. Sharma", role: "Doctor", pin: "2222", isActive: true },
  { id: 3, name: "Pharmacist Rahul", role: "Pharmacist", pin: "3333", isActive: true },
  { id: 4, name: "Cashier Amit", role: "Cashier", pin: "4444", isActive: true }
];

const DEFAULT_MEDICINES = [
  {
    id: 101,
    name: "Paracetamol 650mg (Dolo)",
    category: "Analgesic",
    unit: "Tab",
    purchasePrice: 1.20,
    sellingPrice: 2.50,
    storeStock: 140,
    mainStock: 80, // Clinic Dispensing
    bulkStoreStock: 800,
    bulkClinicStock: 400,
    lowStockThreshold: 100,
    batches: [
      { batchNo: "DL-8891", expiryDate: "2027-08-31", storeStock: 140, mainStock: 80 }
    ]
  },
  {
    id: 102,
    name: "Amoxicillin 500mg (Novamox)",
    category: "Antibiotics",
    unit: "Cap",
    purchasePrice: 4.80,
    sellingPrice: 8.50,
    storeStock: 35,
    mainStock: 15,
    bulkStoreStock: 120,
    bulkClinicStock: 80,
    lowStockThreshold: 60,
    batches: [
      { batchNo: "NX-4412", expiryDate: "2026-11-20", storeStock: 35, mainStock: 15 }
    ]
  },
  {
    id: 103,
    name: "Azithromycin 500mg (Azithral)",
    category: "Antibiotics",
    unit: "Tab",
    purchasePrice: 12.00,
    sellingPrice: 22.00,
    storeStock: 18,
    mainStock: 10,
    bulkStoreStock: 300,
    bulkClinicStock: 150,
    lowStockThreshold: 40,
    batches: [
      { batchNo: "AZ-9901", expiryDate: "2027-04-15", storeStock: 18, mainStock: 10 }
    ]
  },
  {
    id: 104,
    name: "Pantoprazole 40mg (Pan-40)",
    category: "Antacid",
    unit: "Tab",
    purchasePrice: 5.50,
    sellingPrice: 10.00,
    storeStock: 110,
    mainStock: 65,
    bulkStoreStock: 500,
    bulkClinicStock: 300,
    lowStockThreshold: 90,
    batches: [
      { batchNo: "PN-1029", expiryDate: "2026-12-31", storeStock: 110, mainStock: 65 }
    ]
  },
  {
    id: 105,
    name: "Cetirizine 10mg (Cetzine)",
    category: "Antihistamine",
    unit: "Tab",
    purchasePrice: 0.90,
    sellingPrice: 2.00,
    storeStock: 25,
    mainStock: 12,
    bulkStoreStock: 250,
    bulkClinicStock: 100,
    lowStockThreshold: 50,
    batches: [
      { batchNo: "CZ-3320", expiryDate: "2027-01-31", storeStock: 25, mainStock: 12 }
    ]
  },
  {
    id: 106,
    name: "Metformin 500mg (Glycomet)",
    category: "Diabetic",
    unit: "Tab",
    purchasePrice: 1.80,
    sellingPrice: 3.50,
    storeStock: 190,
    mainStock: 110,
    bulkStoreStock: 900,
    bulkClinicStock: 450,
    lowStockThreshold: 120,
    batches: [
      { batchNo: "GM-7762", expiryDate: "2027-06-30", storeStock: 190, mainStock: 110 }
    ]
  },
  {
    id: 107,
    name: "Atorvastatin 10mg (Atorva)",
    category: "Cardio",
    unit: "Tab",
    purchasePrice: 7.20,
    sellingPrice: 14.00,
    storeStock: 20,
    mainStock: 8,
    bulkStoreStock: 180,
    bulkClinicStock: 70,
    lowStockThreshold: 45,
    batches: [
      { batchNo: "AT-5521", expiryDate: "2026-10-15", storeStock: 20, mainStock: 8 }
    ]
  },
  {
    id: 108,
    name: "Telmisartan 40mg (Telma)",
    category: "Cardio",
    unit: "Tab",
    purchasePrice: 6.00,
    sellingPrice: 11.50,
    storeStock: 85,
    mainStock: 40,
    bulkStoreStock: 400,
    bulkClinicStock: 200,
    lowStockThreshold: 60,
    batches: [
      { batchNo: "TL-3390", expiryDate: "2027-09-30", storeStock: 85, mainStock: 40 }
    ]
  }
];

const DEFAULT_SALES = [
  {
    id: 1,
    invoiceNo: "INV-2026-00101",
    patientName: "Ramesh Gupta",
    patientPhone: "+91 98231 44510",
    patientUhid: "OPD-031026-0001",
    total: 385.00,
    subtotal: 385.00,
    paymentMethod: "UPI",
    isClinicalDispense: true,
    createdAt: new Date(Date.now() - 45 * 60 * 1000).toISOString(),
    items: [
      { medicineName: "Paracetamol 650mg (Dolo)", qty: 10, unitPrice: 2.50, lineTotal: 25.00 },
      { medicineName: "Amoxicillin 500mg (Novamox)", qty: 10, unitPrice: 8.50, lineTotal: 85.00 },
      { medicineName: "Pantoprazole 40mg (Pan-40)", qty: 10, unitPrice: 10.00, lineTotal: 100.00 },
      { medicineName: "OPD Doctor Consultation", qty: 1, unitPrice: 175.00, lineTotal: 175.00, isProcedure: true }
    ]
  },
  {
    id: 2,
    invoiceNo: "INV-2026-00102",
    patientName: "Sunita Verma",
    patientPhone: "+91 94112 88721",
    patientUhid: "OPD-031026-0002",
    total: 154.00,
    subtotal: 154.00,
    paymentMethod: "Cash",
    isClinicalDispense: false,
    createdAt: new Date(Date.now() - 110 * 60 * 1000).toISOString(),
    items: [
      { medicineName: "Cetirizine 10mg (Cetzine)", qty: 20, unitPrice: 2.00, lineTotal: 40.00 },
      { medicineName: "Azithromycin 500mg (Azithral)", qty: 3, unitPrice: 22.00, lineTotal: 66.00 },
      { medicineName: "Paracetamol 650mg (Dolo)", qty: 19, unitPrice: 2.50, lineTotal: 48.00 }
    ]
  },
  {
    id: 3,
    invoiceNo: "INV-2026-00103",
    patientName: "Anil Kapoor",
    patientPhone: "+91 99120 11984",
    patientUhid: "OPD-031026-0003",
    total: 420.00,
    subtotal: 420.00,
    paymentMethod: "Card",
    isClinicalDispense: true,
    createdAt: new Date(Date.now() - 180 * 60 * 1000).toISOString(),
    items: [
      { medicineName: "Metformin 500mg (Glycomet)", qty: 30, unitPrice: 3.50, lineTotal: 105.00 },
      { medicineName: "Atorvastatin 10mg (Atorva)", qty: 10, unitPrice: 14.00, lineTotal: 140.00 },
      { medicineName: "OPD Doctor Consultation", qty: 1, unitPrice: 175.00, lineTotal: 175.00, isProcedure: true }
    ]
  },
  {
    id: 4,
    invoiceNo: "INV-2026-00104",
    patientName: "Pooja Mehta",
    patientPhone: "+91 98200 44102",
    patientUhid: "OPD-031026-0004",
    total: 115.00,
    subtotal: 115.00,
    paymentMethod: "UPI",
    isClinicalDispense: false,
    createdAt: new Date(Date.now() - 240 * 60 * 1000).toISOString(),
    items: [
      { medicineName: "Telmisartan 40mg (Telma)", qty: 10, unitPrice: 11.50, lineTotal: 115.00 }
    ]
  }
];

const DEFAULT_APPOINTMENTS = [
  {
    id: 1,
    tokenNumber: 1,
    patientName: "Ramesh Gupta",
    patientPhone: "+91 98231 44510",
    patientUhid: "OPD-031026-0001",
    doctorName: "Dr. Sharma",
    status: "done",
    consultationFee: 175.00,
    paymentMethod: "UPI",
    consultationBilled: true,
    notes: "Fever & Cough checkup done",
    scheduledAt: "10:15 AM"
  },
  {
    id: 2,
    tokenNumber: 2,
    patientName: "Sunita Verma",
    patientPhone: "+91 94112 88721",
    patientUhid: "OPD-031026-0002",
    doctorName: "Dr. Sharma",
    status: "pharmacy",
    consultationFee: 175.00,
    paymentMethod: "Cash",
    consultationBilled: true,
    notes: "Allergy symptoms, prescribed cetirizine & azithromycin",
    scheduledAt: "10:45 AM"
  },
  {
    id: 3,
    tokenNumber: 3,
    patientName: "Vikram Malhotra",
    patientPhone: "+91 97233 11842",
    patientUhid: "OPD-031026-0005",
    doctorName: "Dr. Sharma",
    status: "with_doctor",
    consultationFee: 200.00,
    paymentMethod: "Pending",
    consultationBilled: false,
    notes: "General weakness & BP checkup",
    scheduledAt: "11:20 AM"
  },
  {
    id: 4,
    tokenNumber: 4,
    patientName: "Meenakshi Devi",
    patientPhone: "+91 91234 55678",
    patientUhid: "OPD-031026-0006",
    doctorName: "Dr. Sharma",
    status: "waiting",
    consultationFee: 200.00,
    paymentMethod: "Pending",
    consultationBilled: false,
    notes: "Follow up visit",
    scheduledAt: "11:45 AM"
  }
];

const DEFAULT_TRANSFERS = [
  {
    id: 1,
    medicineName: "Paracetamol 650mg (Dolo)",
    qty: 50,
    fromWarehouse: "bulkStore",
    toWarehouse: "clinic",
    transferredAt: new Date(Date.now() - 3600 * 1000 * 6).toISOString()
  },
  {
    id: 2,
    medicineName: "Amoxicillin 500mg (Novamox)",
    qty: 30,
    fromWarehouse: "bulkClinic",
    toWarehouse: "clinic",
    transferredAt: new Date(Date.now() - 3600 * 1000 * 12).toISOString()
  }
];
