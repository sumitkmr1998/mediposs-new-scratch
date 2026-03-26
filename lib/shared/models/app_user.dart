import 'package:objectbox/objectbox.dart';

@Entity()
class AppUser {
  @Id()
  int id = 0;

  String name;
  String role; // Display label only (e.g., 'Cashier', 'Admin')
  String pin;
  bool isActive;

  // -- Granular Permissions --
  // Settings & Staff
  bool canAccessSettings;
  bool canManageUsers;

  // Dashboard
  bool canViewDashboard;

  // Inventory
  bool canViewInventory;
  bool canEditInventory;
  bool canOverrideStock;         // Manual inventory adjustments

  // Warehouse
  bool canViewWarehouse;
  bool canTransferStock;

  // POS
  bool canAccessPOS;
  bool canDiscountSales;
  bool canOverridePrice;         // AD-HOC Price override at POS
  bool canBulkDiscount;          // Large checkout discounts

  // Sales History
  bool canViewSalesHistory;
  bool canVoidSales;
  bool canProcessReturns;

  // OPD
  bool canAccessOPD;
  bool canManageDoctors;
  bool canViewOpdReports;
  bool canAccessMedicalRecords;  // Clinical privacy (Prescriptions/History)

  // Security & Data
  bool canViewPurchasePrice;     // Restricted financial data
  bool canExportData;            // Prevent bulk extraction

  AppUser({
    this.id = 0,
    required this.name,
    this.role = 'Staff',
    this.pin = '0000',
    this.isActive = true,
    this.canAccessSettings = false,
    this.canManageUsers = false,
    this.canViewDashboard = false,
    this.canViewInventory = false,
    this.canEditInventory = false,
    this.canOverrideStock = false,
    this.canViewWarehouse = false,
    this.canTransferStock = false,
    this.canAccessPOS = true,
    this.canDiscountSales = false,
    this.canOverridePrice = false,
    this.canBulkDiscount = false,
    this.canViewSalesHistory = false,
    this.canVoidSales = false,
    this.canProcessReturns = false,
    this.canAccessOPD = true,
    this.canManageDoctors = false,
    this.canViewOpdReports = false,
    this.canAccessMedicalRecords = false,
    this.canViewPurchasePrice = false,
    this.canExportData = false,
  });

  /// Applies standard permissions based on a role name.
  void applyPreset(String preset) {
    role = preset;
    // Reset all to false first for safety
    _setAll(false);

    switch (preset.toLowerCase()) {
      case 'admin':
      case 'owner':
        _setAll(true);
        break;
      case 'manager':
        canViewDashboard = true;
        canViewInventory = true;
        canEditInventory = true;
        canViewWarehouse = true;
        canTransferStock = true;
        canAccessPOS = true;
        canDiscountSales = true;
        canViewSalesHistory = true;
        canProcessReturns = true;
        canAccessOPD = true;
        canViewPurchasePrice = true;
        canOverrideStock = true;
        canBulkDiscount = true;
        break;
      case 'pharmacist':
        canViewInventory = true;
        canEditInventory = true;
        canViewWarehouse = true;
        canTransferStock = true;
        canAccessPOS = true;
        canAccessOPD = true;
        break;
      case 'cashier':
        canAccessPOS = true;
        canViewInventory = true;
        canAccessOPD = true;
        break;
      case 'doctor':
        canAccessOPD = true;
        canAccessMedicalRecords = true;
        break;
      case 'accountant':
        canViewDashboard = true;
        canViewSalesHistory = true;
        canViewOpdReports = true;
        canViewPurchasePrice = true;
        break;
    }
  }

  void _setAll(bool val) {
    canAccessSettings = val;
    canManageUsers = val;
    canViewDashboard = val;
    canViewInventory = val;
    canEditInventory = val;
    canOverrideStock = val;
    canViewWarehouse = val;
    canTransferStock = val;
    canAccessPOS = val;
    canDiscountSales = val;
    canOverridePrice = val;
    canBulkDiscount = val;
    canViewSalesHistory = val;
    canVoidSales = val;
    canProcessReturns = val;
    canAccessOPD = val;
    canManageDoctors = val;
    canViewOpdReports = val;
    canAccessMedicalRecords = val;
    canViewPurchasePrice = val;
    canExportData = val;
  }
}

@Entity()
class AppSettings {
  @Id()
  int id = 0;

  String storeName;
  String storeAddress;
  String storePhone;
  String gstNumber;
  String receiptFooterMessage;
  double taxRate;
  String currencySymbol;
  String themeMode; // 'system', 'light', 'dark'
  int serverPort;
  String jwtSecret;
  String defaultPrinterName;
  bool autoPrintReceipt;
  String receiptPaperSize; // 'A6', 'Letter', 'A4', 'Roll80'
  String? hubIp; // To persist connection
  String? autoLoginPin; // Saved PIN for auto-login JWT refresh on Android
  int lowStockThreshold;
  int nearExpiryThresholdDays;

  AppSettings({
    this.id = 0,
    this.storeName = 'MediPoss Pharmacy',
    this.storeAddress = '',
    this.storePhone = '',
    this.gstNumber = '',
    this.receiptFooterMessage = 'Thank you for your visit!',
    this.taxRate = 0.0,
    this.currencySymbol = '₹',
    this.themeMode = 'dark',
    this.serverPort = 8080,
    this.jwtSecret = 'medipos_secret_key_2024',
    this.defaultPrinterName = '',
    this.autoPrintReceipt = false,
    this.receiptPaperSize = 'A6',
    this.hubIp,
    this.autoLoginPin,
    this.lowStockThreshold = 10,
    this.nearExpiryThresholdDays = 90,
  });
}
