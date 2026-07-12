import '../models/medicine.dart';
import '../models/app_user.dart';

class TransferRules {
  static String? validateTransfer({
    required Medicine medicine,
    required int qty,
    required String from,
    required String to,
    DateTime? expiryDate,
    AppUser? actor,
  }) {
    if (actor != null &&
        !(actor.role.toLowerCase() == 'admin' || actor.canTransferStock)) {
      return 'Unauthorized: You do not have permission to execute stock transfers.';
    }

    if (expiryDate != null &&
        expiryDate.isBefore(DateTime.now()) &&
        (to == 'main' || to == 'clinic' || to == 'store')) {
      return 'Validation Error: Cannot transfer expired stock to active retail locations (Clinic/Store). Expired stock must remain in storage bulk locations.';
    }

    if (qty <= 0) return 'Quantity must be greater than 0';

    int available = 0;
    if (from == 'main' || from == 'clinic') {
      available = medicine.mainStock;
    } else if (from == 'store') {
      available = medicine.storeStock;
    } else if (from == 'bulkClinic') {
      available = medicine.bulkClinicStock;
    } else if (from == 'bulkStore') {
      available = medicine.bulkStoreStock;
    }

    if (qty > available) {
      String getLocName(String loc) {
        if (loc == 'main' || loc == 'clinic') return 'Clinic';
        if (loc == 'store') return 'Store';
        if (loc == 'bulkClinic') return 'Clinic Bulk';
        if (loc == 'bulkStore') return 'Store Bulk';
        return loc;
      }
      return 'Insufficient stock in ${getLocName(from)} (available: $available)';
    }

    return null; // Valid
  }
}
