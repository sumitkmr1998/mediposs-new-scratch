import '../models/app_user.dart';

/// Permission decisions are made against the Hub's current user record.
class HubPermissions {
  static bool allows(AppUser user, String permission) {
    if (!user.isActive) return false;
    if (user.role.toLowerCase() == 'admin') return true;
    switch (permission) {
      case 'manageUsers': return user.canManageUsers;
      case 'settings': return user.canAccessSettings;
      case 'manageDoctors': return user.canManageDoctors;
      case 'deletePatients': return user.canDeletePatients;
      case 'deleteInventory': return user.canDeleteInventory;
      case 'medicalRecords': return user.canAccessMedicalRecords;
      case 'inventoryWrite': return user.canEditInventory;
      case 'addStock': return user.canAddStock;
      case 'pos': return user.canAccessPOS || user.canDispenseMedicines;
      case 'opd': return user.canAccessOPD;
      case 'patients': return user.canAccessOPD || user.canAccessPOS;
      case 'warehouse': return user.canViewWarehouse;
      case 'transferStock': return user.canTransferStock;
      case 'purchasePrice': return user.canViewPurchasePrice || user.canAddStock;
      case 'salesHistory': return user.canViewSalesHistory || user.canAccessPOS;
      case 'voidSales': return user.canVoidSales;
      case 'processReturns': return user.canProcessReturns;
      case 'exportData': return user.canExportData;
      default: return false;
    }
  }
}
