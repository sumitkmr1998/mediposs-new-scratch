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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'pin': pin,
        'isActive': isActive,
        'canAccessSettings': canAccessSettings,
        'canManageUsers': canManageUsers,
        'canViewDashboard': canViewDashboard,
        'canViewInventory': canViewInventory,
        'canEditInventory': canEditInventory,
        'canOverrideStock': canOverrideStock,
        'canViewWarehouse': canViewWarehouse,
        'canTransferStock': canTransferStock,
        'canAccessPOS': canAccessPOS,
        'canDiscountSales': canDiscountSales,
        'canOverridePrice': canOverridePrice,
        'canBulkDiscount': canBulkDiscount,
        'canViewSalesHistory': canViewSalesHistory,
        'canVoidSales': canVoidSales,
        'canProcessReturns': canProcessReturns,
        'canAccessOPD': canAccessOPD,
        'canManageDoctors': canManageDoctors,
        'canViewOpdReports': canViewOpdReports,
        'canAccessMedicalRecords': canAccessMedicalRecords,
        'canViewPurchasePrice': canViewPurchasePrice,
        'canExportData': canExportData,
      };

  static AppUser fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        role: json['role'] ?? 'Staff',
        pin: json['pin'] ?? '0000',
        isActive: json['isActive'] ?? true,
        canAccessSettings: json['canAccessSettings'] ?? false,
        canManageUsers: json['canManageUsers'] ?? false,
        canViewDashboard: json['canViewDashboard'] ?? false,
        canViewInventory: json['canViewInventory'] ?? false,
        canEditInventory: json['canEditInventory'] ?? false,
        canOverrideStock: json['canOverrideStock'] ?? false,
        canViewWarehouse: json['canViewWarehouse'] ?? false,
        canTransferStock: json['canTransferStock'] ?? false,
        canAccessPOS: json['canAccessPOS'] ?? true,
        canDiscountSales: json['canDiscountSales'] ?? false,
        canOverridePrice: json['canOverridePrice'] ?? false,
        canBulkDiscount: json['canBulkDiscount'] ?? false,
        canViewSalesHistory: json['canViewSalesHistory'] ?? false,
        canVoidSales: json['canVoidSales'] ?? false,
        canProcessReturns: json['canProcessReturns'] ?? false,
        canAccessOPD: json['canAccessOPD'] ?? true,
        canManageDoctors: json['canManageDoctors'] ?? false,
        canViewOpdReports: json['canViewOpdReports'] ?? false,
        canAccessMedicalRecords: json['canAccessMedicalRecords'] ?? false,
        canViewPurchasePrice: json['canViewPurchasePrice'] ?? false,
        canExportData: json['canExportData'] ?? false,
      );
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
  double preferredRefreshRate; // -1.0 = Auto/Max
  bool enableAnimations;
  String autoBackupFrequency; // 'Never', 'Daily', 'Weekly', 'Monthly'
  String autoBackupLogic; // 'At Startup', 'On Close', 'Periodic'
  bool googleDriveLinked;
  String? googleAuthData; // JSON of credentials
  int? lastBackupMillis;
  String? autoBackupTime; // e.g., "22:00"
  bool navCollapsed;

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
    this.preferredRefreshRate = -1.0,
    this.enableAnimations = true,
    this.autoBackupFrequency = 'Never',
    this.autoBackupLogic = 'At Startup',
    this.googleDriveLinked = false,
    this.googleAuthData,
    this.lastBackupMillis,
    this.autoBackupTime = '22:00',
    this.navCollapsed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeName': storeName,
        'storeAddress': storeAddress,
        'storePhone': storePhone,
        'gstNumber': gstNumber,
        'receiptFooterMessage': receiptFooterMessage,
        'taxRate': taxRate,
        'currencySymbol': currencySymbol,
        'themeMode': themeMode,
        'serverPort': serverPort,
        'jwtSecret': jwtSecret,
        'defaultPrinterName': defaultPrinterName,
        'autoPrintReceipt': autoPrintReceipt,
        'receiptPaperSize': receiptPaperSize,
        'hubIp': hubIp,
        'autoLoginPin': autoLoginPin,
        'lowStockThreshold': lowStockThreshold,
        'nearExpiryThresholdDays': nearExpiryThresholdDays,
        'preferredRefreshRate': preferredRefreshRate,
        'enableAnimations': enableAnimations,
        'autoBackupFrequency': autoBackupFrequency,
        'autoBackupLogic': autoBackupLogic,
        'googleDriveLinked': googleDriveLinked,
        'googleAuthData': googleAuthData,
        'lastBackupMillis': lastBackupMillis,
        'autoBackupTime': autoBackupTime,
        'navCollapsed': navCollapsed,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        id: json['id'] ?? 0,
        storeName: json['storeName'] ?? 'MediPoss Pharmacy',
        storeAddress: json['storeAddress'] ?? '',
        storePhone: json['storePhone'] ?? '',
        gstNumber: json['gstNumber'] ?? '',
        receiptFooterMessage:
            json['receiptFooterMessage'] ?? 'Thank you for your visit!',
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.0,
        currencySymbol: json['currencySymbol'] ?? '₹',
        themeMode: json['themeMode'] ?? 'dark',
        serverPort: json['serverPort'] ?? 8080,
        jwtSecret: json['jwtSecret'] ?? 'medipos_secret_key_2024',
        defaultPrinterName: json['defaultPrinterName'] ?? '',
        autoPrintReceipt: json['autoPrintReceipt'] ?? false,
        receiptPaperSize: json['receiptPaperSize'] ?? 'A6',
        hubIp: json['hubIp'],
        autoLoginPin: json['autoLoginPin'],
        lowStockThreshold: json['lowStockThreshold'] ?? 10,
        nearExpiryThresholdDays: json['nearExpiryThresholdDays'] ?? 90,
        preferredRefreshRate:
            (json['preferredRefreshRate'] as num?)?.toDouble() ?? -1.0,
        enableAnimations: json['enableAnimations'] ?? true,
        autoBackupFrequency: json['autoBackupFrequency'] ?? 'Never',
        autoBackupLogic: json['autoBackupLogic'] ?? 'At Startup',
        googleDriveLinked: json['googleDriveLinked'] ?? false,
        googleAuthData: json['googleAuthData'],
        lastBackupMillis: json['lastBackupMillis'],
        autoBackupTime: json['autoBackupTime'] ?? '22:00',
        navCollapsed: json['navCollapsed'] ?? false,
      );
}
