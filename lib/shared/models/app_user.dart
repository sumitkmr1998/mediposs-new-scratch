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
  bool canViewAnalytics;

  // Inventory
  bool canViewInventory;
  bool canEditInventory;
  bool canOverrideStock;         // Manual inventory adjustments
  bool canDeleteInventory;       // NEW: Separate delete right

  // Warehouse
  bool canViewWarehouse;
  bool canTransferStock;

  // POS
  bool canAccessPOS;
  bool canDiscountSales;
  bool canOverridePrice;         // AD-HOC Price override at POS
  bool canBulkDiscount;          // Large checkout discounts
  bool canProcessRetailSales;    // NEW: Antigravvity Retail Mode
  bool canProcessClinicalDispenses; // NEW: Antigravvity Clinic Mode

  // Sales History
  bool canViewSalesHistory;
  bool canVoidSales;
  bool canProcessReturns;
  bool canEditSales;

  // OPD
  bool canAccessOPD;
  bool canManageDoctors;
  bool canViewOpdReports;
  bool canAccessMedicalRecords;  // Clinical privacy (Prescriptions/History)
  bool canDeletePatients;        // NEW: Separate delete right
  bool canDeleteAppointments;    // NEW: Separate delete right

  // Security & Data
  bool canViewPurchasePrice;     // Restricted financial data
  bool canExportData;            // Prevent bulk extraction
  bool canViewHistoricalData;    // Shield historical stats (Dashboard/Reports)

  AppUser({
    this.id = 0,
    required this.name,
    this.role = 'Staff',
    this.pin = '0000',
    this.isActive = true,
    this.canAccessSettings = false,
    this.canManageUsers = false,
    this.canViewDashboard = false,
    this.canViewAnalytics = false,
    this.canViewInventory = false,
    this.canEditInventory = false,
    this.canOverrideStock = false,
    this.canDeleteInventory = false,
    this.canViewWarehouse = false,
    this.canTransferStock = false,
    this.canAccessPOS = true,
    this.canDiscountSales = false,
    this.canOverridePrice = false,
    this.canBulkDiscount = false,
    this.canProcessRetailSales = true,
    this.canProcessClinicalDispenses = true,
    this.canViewSalesHistory = false,
    this.canVoidSales = false,
    this.canProcessReturns = false,
    this.canEditSales = false,
    this.canAccessOPD = true,
    this.canManageDoctors = false,
    this.canViewOpdReports = false,
    this.canAccessMedicalRecords = false,
    this.canDeletePatients = false,
    this.canDeleteAppointments = false,
    this.canViewPurchasePrice = false,
    this.canExportData = false,
    this.canViewHistoricalData = true,
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
        canViewAnalytics = true;
        canViewInventory = true;
        canEditInventory = true;
        canDeleteInventory = true;
        canViewWarehouse = true;
        canTransferStock = true;
        canAccessPOS = true;
        canProcessRetailSales = true;
        canProcessClinicalDispenses = true;
        canDiscountSales = true;
        canViewSalesHistory = true;
        canProcessReturns = true;
        canVoidSales = true;
        canEditSales = true;
        canAccessOPD = true;
        canManageDoctors = true;
        canViewOpdReports = true;
        canAccessMedicalRecords = true;
        canDeletePatients = true;
        canDeleteAppointments = true;
        canViewPurchasePrice = true;
        canOverrideStock = true;
        canBulkDiscount = true;
        canViewHistoricalData = true;
        canExportData = true;
        break;
      case 'pharmacist':
        canViewInventory = true;
        canEditInventory = true;
        canViewWarehouse = true;
        canTransferStock = true;
        canAccessPOS = true;
        canProcessRetailSales = true;
        canProcessClinicalDispenses = true;
        canDiscountSales = true;
        canViewSalesHistory = true;
        canProcessReturns = true;
        canAccessOPD = true;
        canViewHistoricalData = false; // "Today Only" for staff
        break;
      case 'cashier':
        canAccessPOS = true;
        canProcessRetailSales = true;
        canProcessClinicalDispenses = false;
        canViewInventory = true;
        canViewSalesHistory = true;
        canAccessOPD = true;
        canProcessReturns = true;
        canViewHistoricalData = false; // "Today Only" for staff
        break;
      case 'doctor':
        canAccessPOS = true;
        canProcessRetailSales = false;
        canProcessClinicalDispenses = true;
        canAccessOPD = true;
        canAccessMedicalRecords = true;
        canViewInventory = true;
        canViewHistoricalData = true;
        canViewOpdReports = true;
        break;
      case 'accountant':
        canViewDashboard = true;
        canViewAnalytics = true;
        canViewSalesHistory = true;
        canViewOpdReports = true;
        canViewPurchasePrice = true;
        canViewHistoricalData = true;
        break;
    }
  }

  void _applyPermissionShield(String preset) {
    switch (preset.toLowerCase()) {
      case 'admin':
      case 'owner':
      case 'manager':
      case 'doctor':
      case 'accountant':
        canViewHistoricalData = true;
        break;
      case 'cashier':
      case 'pharmacist':
      case 'staff':
      default:
        canViewHistoricalData = false;
        break;
    }
  }

  void _setAll(bool val) {
    canAccessSettings = val;
    canManageUsers = val;
    canViewDashboard = val;
    canViewAnalytics = val;
    canViewInventory = val;
    canEditInventory = val;
    canOverrideStock = val;
    canDeleteInventory = val;
    canViewWarehouse = val;
    canTransferStock = val;
    canAccessPOS = val;
    canProcessRetailSales = val;
    canProcessClinicalDispenses = val;
    canDiscountSales = val;
    canOverridePrice = val;
    canBulkDiscount = val;
    canViewSalesHistory = val;
    canVoidSales = val;
    canProcessReturns = val;
    canEditSales = val;
    canAccessOPD = val;
    canManageDoctors = val;
    canViewOpdReports = val;
    canAccessMedicalRecords = val;
    canDeletePatients = val;
    canDeleteAppointments = val;
    canViewPurchasePrice = val;
    canExportData = val;
    canViewHistoricalData = val;
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
        'canViewAnalytics': canViewAnalytics,
        'canViewInventory': canViewInventory,
        'canEditInventory': canEditInventory,
        'canOverrideStock': canOverrideStock,
        'canDeleteInventory': canDeleteInventory,
        'canViewWarehouse': canViewWarehouse,
        'canTransferStock': canTransferStock,
        'canAccessPOS': canAccessPOS,
        'canProcessRetailSales': canProcessRetailSales,
        'canProcessClinicalDispenses': canProcessClinicalDispenses,
        'canDiscountSales': canDiscountSales,
        'canOverridePrice': canOverridePrice,
        'canBulkDiscount': canBulkDiscount,
        'canViewSalesHistory': canViewSalesHistory,
        'canVoidSales': canVoidSales,
        'canProcessReturns': canProcessReturns,
        'canEditSales': canEditSales,
        'canAccessOPD': canAccessOPD,
        'canManageDoctors': canManageDoctors,
        'canViewOpdReports': canViewOpdReports,
        'canAccessMedicalRecords': canAccessMedicalRecords,
        'canDeletePatients': canDeletePatients,
        'canDeleteAppointments': canDeleteAppointments,
        'canViewPurchasePrice': canViewPurchasePrice,
        'canExportData': canExportData,
        'canViewHistoricalData': canViewHistoricalData,
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
        canViewAnalytics: json['canViewAnalytics'] ?? false,
        canViewInventory: json['canViewInventory'] ?? false,
        canEditInventory: json['canEditInventory'] ?? false,
        canOverrideStock: json['canOverrideStock'] ?? false,
        canDeleteInventory: json['canDeleteInventory'] ?? false,
        canViewWarehouse: json['canViewWarehouse'] ?? false,
        canTransferStock: json['canTransferStock'] ?? false,
        canAccessPOS: json['canAccessPOS'] ?? true,
        canProcessRetailSales: json['canProcessRetailSales'] ?? true,
        canProcessClinicalDispenses: json['canProcessClinicalDispenses'] ?? true,
        canDiscountSales: json['canDiscountSales'] ?? false,
        canOverridePrice: json['canOverridePrice'] ?? false,
        canBulkDiscount: json['canBulkDiscount'] ?? false,
        canViewSalesHistory: json['canViewSalesHistory'] ?? false,
        canVoidSales: json['canVoidSales'] ?? false,
        canProcessReturns: json['canProcessReturns'] ?? false,
        canEditSales: json['canEditSales'] ?? false,
        canAccessOPD: json['canAccessOPD'] ?? true,
        canManageDoctors: json['canManageDoctors'] ?? false,
        canViewOpdReports: json['canViewOpdReports'] ?? false,
        canAccessMedicalRecords: json['canAccessMedicalRecords'] ?? false,
        canDeletePatients: json['canDeletePatients'] ?? false,
        canDeleteAppointments: json['canDeleteAppointments'] ?? false,
        canViewPurchasePrice: json['canViewPurchasePrice'] ?? false,
        canExportData: json['canExportData'] ?? false,
        canViewHistoricalData: json['canViewHistoricalData'] ?? true,
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
  String? autoLoginName; // Saved Name for auto-login JWT refresh on Android
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
  int? lastGlobalSync;

  // New Cloud Sync Settings
  String connectionMode; // "auto", "local", "cloudflare", "firebase"
  String cloudflareUrl; // "https://xxx.trycloudflare.com"
  int? lastCloudflareSync; // timestamp
  bool firebaseEnabled; // true
  int? lastFirebaseSync; // timestamp
  String? deviceId; // UUID for this device
  bool isWindowsClient = false; // If true, this PC acts as a terminal/client
  List<String> dashboardActions = ['new_pos', 'add_patient', 'stock_list', 'reports', 'patients', 'returns', 'settings'];

  // Clinic Details
  String? clinicName;
  String? clinicAddress;
  String? clinicPhone;
  String? clinicRegNo;
  bool isCompositionScheme = false;

  bool showBatchExpiryInRetailPrint = true;
  bool showBatchExpiryInClinicalPrint = true;

  // Multi-Tenant Cloud Sync
  String shopId;

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
    this.autoLoginName,
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
    this.lastGlobalSync,
    this.connectionMode = 'auto',
    this.cloudflareUrl = '',
    this.lastCloudflareSync,
    this.firebaseEnabled = true,
    this.lastFirebaseSync,
    this.deviceId,
    this.isWindowsClient = false,
    this.dashboardActions = const ['new_pos', 'add_patient', 'stock_list', 'reports', 'patients', 'returns', 'settings'],
    this.clinicName = 'MediPoss Clinic',
    this.clinicAddress = '',
    this.clinicPhone = '',
    this.clinicRegNo = '',
    this.isCompositionScheme = false,
    this.showBatchExpiryInRetailPrint = true,
    this.showBatchExpiryInClinicalPrint = true,
    this.shopId = '',
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
        'autoLoginName': autoLoginName,
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
        'lastGlobalSync': lastGlobalSync,
        'connectionMode': connectionMode,
        'cloudflareUrl': cloudflareUrl,
        'lastCloudflareSync': lastCloudflareSync,
        'firebaseEnabled': firebaseEnabled,
        'lastFirebaseSync': lastFirebaseSync,
        'deviceId': deviceId,
        'isWindowsClient': isWindowsClient,
        'dashboardActions': dashboardActions,
        'clinicName': clinicName,
        'clinicAddress': clinicAddress,
        'clinicPhone': clinicPhone,
        'clinicRegNo': clinicRegNo,
        'isCompositionScheme': isCompositionScheme,
        'showBatchExpiryInRetailPrint': showBatchExpiryInRetailPrint,
        'showBatchExpiryInClinicalPrint': showBatchExpiryInClinicalPrint,
        'shopId': shopId,
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
        autoLoginName: json['autoLoginName'],
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
        lastGlobalSync: json['lastGlobalSync'],
        connectionMode: json['connectionMode'] ?? 'auto',
        cloudflareUrl: json['cloudflareUrl'] ?? '',
        lastCloudflareSync: json['lastCloudflareSync'],
        firebaseEnabled: json['firebaseEnabled'] ?? true,
        lastFirebaseSync: json['lastFirebaseSync'],
        deviceId: json['deviceId'],
        isWindowsClient: json['isWindowsClient'] ?? false,
        dashboardActions: List<String>.from(json['dashboardActions'] ?? const ['new_pos', 'add_patient', 'stock_list', 'reports', 'patients', 'returns', 'settings']),
        clinicName: json['clinicName'] ?? 'MediPoss Clinic',
        clinicAddress: json['clinicAddress'] ?? '',
        clinicPhone: json['clinicPhone'] ?? '',
        clinicRegNo: json['clinicRegNo'] ?? '',
        isCompositionScheme: json['isCompositionScheme'] ?? false,
        showBatchExpiryInRetailPrint: json['showBatchExpiryInRetailPrint'] ?? true,
        showBatchExpiryInClinicalPrint: json['showBatchExpiryInClinicalPrint'] ?? true,
        shopId: json['shopId'] ?? '',
      );
}
