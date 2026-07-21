import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../services/objectbox_service.dart';
import '../services/sync_service.dart';
import '../services/audit_service.dart';
import '../services/sync_queue_service.dart';
import '../../objectbox.g.dart';

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

  bool get canViewAnalytics =>
      isAdmin || (_currentUser?.canViewAnalytics ?? false);

  bool get canViewHistoricalData =>
      isAdmin || (_currentUser?.canViewHistoricalData ?? false);

  bool get canViewFinancialAnalytics =>
      isAdmin || (_currentUser?.canViewFinancialAnalytics ?? false);

  bool get canViewInventory =>
      isAdmin || (_currentUser?.canViewInventory ?? false);
  bool get hasInventoryWriteAccess =>
      isAdmin || (_currentUser?.canEditInventory ?? false);
  bool get canAddStock =>
      isAdmin || (_currentUser?.canAddStock ?? false);

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
  bool get canEditSales =>
      isAdmin || (_currentUser?.canEditSales ?? false);

  bool get canAccessOPD => isAdmin || (_currentUser?.canAccessOPD ?? false);
  bool get canManageDoctors =>
      isAdmin || (_currentUser?.canManageDoctors ?? false);
  bool get canViewOpdReports =>
      isAdmin || (_currentUser?.canViewOpdReports ?? false);
  bool get canAccessMedicalRecords =>
      isAdmin || (_currentUser?.canAccessMedicalRecords ?? false);
  bool get canDispenseMedicines =>
      isAdmin || (_currentUser?.canDispenseMedicines ?? false);

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
      _triggerAutoCheckIn(match);
      AuditService.instance.log(
        action: 'LOGIN',
        entityType: 'User',
        entityId: match.id.toString(),
        description: 'User ${match.name} logged in successfully',
        details: {'userId': match.id, 'role': match.role, 'username': match.name},
        actor: match,
      );
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
      _triggerAutoCheckIn(user);
      AuditService.instance.log(
        action: 'LOGIN',
        entityType: 'User',
        entityId: user.id.toString(),
        description: 'User ${user.name} logged in successfully',
        details: {'userId': user.id, 'role': user.role, 'username': user.name},
        actor: user,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  void forceLogin(AppUser user) {
    debugPrint('AuthProvider: forceLogin for ${user.name}');
    _currentUser = user;
    _isAuthenticated = true;
    _triggerAutoCheckIn(user);
    notifyListeners();
  }

  void logout() {
    final oldUser = _currentUser;
    _currentUser = null;
    _isAuthenticated = false;
    if (oldUser != null) {
      AuditService.instance.log(
        action: 'LOGOUT',
        entityType: 'User',
        entityId: oldUser.id.toString(),
        description: 'User ${oldUser.name} logged out',
        details: {'userId': oldUser.id, 'username': oldUser.name},
        actor: oldUser,
      );
    }
    notifyListeners();
  }

  List<AppUser> getAllUsers() => ObjectBoxService.instance.userBox.getAll();

  void addUser(AppUser user, {SyncService? syncService, AppUser? actor}) {
    final isNew = user.id == 0;
    ObjectBoxService.instance.userBox.put(user);

    // Log user creation/update
    AuditService.instance.log(
      action: isNew ? 'CREATE' : 'UPDATE',
      entityType: 'User',
      entityId: user.id.toString(),
      description: isNew
          ? 'Created staff member: ${user.name} (Role: ${user.role})'
          : 'Updated staff member details: ${user.name} (Role: ${user.role})',
      details: {
        'targetUserId': user.id,
        'targetUsername': user.name,
        'targetRole': user.role,
        'isActive': user.isActive,
      },
      actor: actor,
    );

    if (syncService != null && syncService.isConnected) {
      syncService.pushUser(user);
    }
    notifyListeners();
  }

  void updatePin(int userId, String newPin, {SyncService? syncService, AppUser? actor}) {
    final user = ObjectBoxService.instance.userBox.get(userId);
    if (user != null) {
      user.pin = newPin;
      ObjectBoxService.instance.userBox.put(user);

      // Log PIN update
      AuditService.instance.log(
        action: 'SECURITY',
        entityType: 'User',
        entityId: user.id.toString(),
        description: 'Updated PIN for staff member: ${user.name}',
        details: {'targetUserId': user.id, 'targetUsername': user.name},
        actor: actor,
      );

      if (syncService != null && syncService.isConnected) {
        syncService.pushUser(user);
      }
      notifyListeners();
    }
  }

  void _triggerAutoCheckIn(AppUser user) {
    if (user.role.toLowerCase() == 'admin') return;
    try {
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final box = ObjectBoxService.instance.attendanceBox;
      final query = box.query(
        AttendanceRecord_.userId.equals(user.id)
        .and(AttendanceRecord_.date.equals(dateStr))
      ).build();
      final existing = query.findFirst();
      query.close();

      if (existing == null) {
        final record = AttendanceRecord(
          userId: user.id,
          userName: user.name,
          checkIn: DateTime.now(),
          date: dateStr,
          status: 'present',
        );
        box.put(record);
        debugPrint('AuthProvider: Auto check-in logged for ${user.name}');

        final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
        if (isClient) {
          SyncQueueService.instance.addToQueue(
            entity: 'attendance',
            action: 'create',
            data: record.toJson(),
          );
        }
      }
    } catch (e) {
      debugPrint('AuthProvider: autoCheckIn failed: $e');
    }
  }
}
