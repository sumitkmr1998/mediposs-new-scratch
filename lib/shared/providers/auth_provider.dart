import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';

class AuthProvider extends ChangeNotifier {
  AppUser? _currentUser;
  bool _isAuthenticated = false;

  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;

  // Master override for backward compatibility
  bool get isAdmin => _currentUser?.role.toLowerCase() == 'admin';

  // Granular check getters (fall back to true if admin, else check specific flag)
  bool get canAccessSettings =>
      isAdmin || (_currentUser?.canAccessSettings ?? false);
  bool get canManageUsers => isAdmin || (_currentUser?.canManageUsers ?? false);

  bool get canViewDashboard =>
      isAdmin || (_currentUser?.canViewDashboard ?? false);

  bool get canViewInventory =>
      isAdmin || (_currentUser?.canViewInventory ?? false);
  bool get hasInventoryWriteAccess =>
      isAdmin || (_currentUser?.canEditInventory ?? false);

  bool get canViewWarehouse =>
      isAdmin || (_currentUser?.canViewWarehouse ?? false);
  bool get hasWarehouseWriteAccess =>
      isAdmin || (_currentUser?.canTransferStock ?? false);

  bool get canAccessPOS => isAdmin || (_currentUser?.canAccessPOS ?? false);
  bool get canDiscountSales =>
      isAdmin || (_currentUser?.canDiscountSales ?? false);

  bool get canViewSalesHistory =>
      isAdmin || (_currentUser?.canViewSalesHistory ?? false);
  bool get canVoidSales => isAdmin || (_currentUser?.canVoidSales ?? false);
  bool get canProcessReturns =>
      isAdmin || (_currentUser?.canProcessReturns ?? false);

  bool get canAccessOPD => isAdmin || (_currentUser?.canAccessOPD ?? false);
  bool get canManageDoctors =>
      isAdmin || (_currentUser?.canManageDoctors ?? false);
  bool get canViewOpdReports =>
      isAdmin || (_currentUser?.canViewOpdReports ?? false);
  bool get canAccessMedicalRecords =>
      isAdmin || (_currentUser?.canAccessMedicalRecords ?? false);

  // Security & Data
  bool get canViewPurchasePrice =>
      isAdmin || (_currentUser?.canViewPurchasePrice ?? false);
  bool get canExportData => isAdmin || (_currentUser?.canExportData ?? false);
  bool get canOverrideStock =>
      isAdmin || (_currentUser?.canOverrideStock ?? false);
  bool get canOverridePrice =>
      isAdmin || (_currentUser?.canOverridePrice ?? false);
  bool get canBulkDiscount =>
      isAdmin || (_currentUser?.canBulkDiscount ?? false);

  bool get canProcessRetailSales =>
      isAdmin || (_currentUser?.canProcessRetailSales ?? true);
  bool get canProcessClinicalDispenses =>
      isAdmin || (_currentUser?.canProcessClinicalDispenses ?? true);

  bool login(String pin) {
    final users = ObjectBoxService.instance.userBox.getAll();
    final match = users.cast<AppUser?>().firstWhere(
          (u) => u!.pin == pin && u.isActive,
          orElse: () => null,
        );
    if (match != null) {
      _currentUser = match;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  bool loginWithUser(AppUser user, String pin) {
    debugPrint(
        'AuthProvider: loginWithUser check for ${user.name}. Input PIN match: ${user.pin == pin}. Active: ${user.isActive}');
    if (user.pin == pin && user.isActive) {
      _currentUser = user;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void forceLogin(AppUser user) {
    debugPrint('AuthProvider: forceLogin for ${user.name}');
    _currentUser = user;
    _isAuthenticated = true;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  List<AppUser> getAllUsers() => ObjectBoxService.instance.userBox.getAll();

  void addUser(AppUser user, {SyncService? syncService}) {
    ObjectBoxService.instance.userBox.put(user);
    if (syncService != null && syncService.isConnected) {
      syncService.pushUser(user);
    }
    notifyListeners();
  }

  void updatePin(int userId, String newPin, {SyncService? syncService}) {
    final user = ObjectBoxService.instance.userBox.get(userId);
    if (user != null) {
      user.pin = newPin;
      ObjectBoxService.instance.userBox.put(user);
      if (syncService != null && syncService.isConnected) {
        syncService.pushUser(user);
      }
      notifyListeners();
    }
  }
}
