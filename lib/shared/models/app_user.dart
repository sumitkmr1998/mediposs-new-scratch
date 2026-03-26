import 'package:objectbox/objectbox.dart';

@Entity()
class AppUser {
  @Id()
  int id = 0;

  String name;
  String role; // Display label only (e.g., 'Cashier', 'Admin')
  String pin;
  bool isActive;

  // Granular Permissions

  // Settings & Staff
  bool canAccessSettings;
  bool canManageUsers;

  // Dashboard
  bool canViewDashboard;

  // Inventory
  bool canViewInventory;
  bool canEditInventory;

  // Warehouse
  bool canViewWarehouse;
  bool canTransferStock;

  // POS
  bool canAccessPOS;
  bool canDiscountSales;

  // Sales History
  bool canViewSalesHistory;
  bool canVoidSales;
  bool canProcessReturns;

  // OPD
  bool canAccessOPD;
  bool canManageDoctors;
  bool canViewOpdReports;

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
    this.canViewWarehouse = false,
    this.canTransferStock = false,
    this.canAccessPOS = true,
    this.canDiscountSales = false,
    this.canViewSalesHistory = false,
    this.canVoidSales = false,
    this.canProcessReturns = false,
    this.canAccessOPD = true,
    this.canManageDoctors = false,
    this.canViewOpdReports = false,
  });
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
