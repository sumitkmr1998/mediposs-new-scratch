import 'package:ntp/ntp.dart';
import 'package:flutter/foundation.dart';
import '../services/objectbox_service.dart';
import '../../objectbox.g.dart';

class TimeService {
  TimeService._();

  /// Returns a temporally robust timestamp by:
  /// 1. Attempting to fetch true global time via NTP.
  /// 2. Falling back to the local device clock if offline (or timeout).
  /// 3. Validating and strictly enforcing monotonic sequence against the highest known transaction in ObjectBox.
  static Future<DateTime> getRobustTime() async {
    DateTime networkTime;

    try {
      // Attempt NTP connection with a short timeout.
      // E.g., if checking out while offline, we don't want a 5-second hang.
      networkTime = await NTP.now(
        timeout: const Duration(seconds: 2),
      );
    } catch (e) {
      if (kDebugMode) {
        print('NTP fetch failed, falling back to local clock: $e');
      }
      networkTime = DateTime.now();
    }

    // Step 2: Validate against the local database to enforce monotony.
    // E.g. If an employee turned back their device clock to hide a sale out of shift,
    // the max DB time will be greater than their spoofed time.
    final latestDbTime = _getLatestTransactionTime();

    if (networkTime.isBefore(latestDbTime)) {
      if (kDebugMode) {
        print(
          'TIME TAMPER DETECTED (or extreme drift). '
          'Network/Local Time: $networkTime | Latest DB: $latestDbTime. '
          'Forcing transaction to latest + 1 second.',
        );
      }
      return latestDbTime.add(const Duration(seconds: 1));
    }

    return networkTime;
  }

  /// Looks through Sales and StockTransfers to find the absolute latest chronological entry on this device.
  static DateTime _getLatestTransactionTime() {
    final obx = ObjectBoxService.instance;

    DateTime latest = DateTime(2000); // Baseline

    // Check Sales
    final salesQueryBuilder = obx.saleBox.query();
    salesQueryBuilder.order(Sale_.createdAt,
        flags: 1); // Descending (Order.descender flag is 1)
    final salesQuery = salesQueryBuilder.build();
    salesQuery.limit = 1;
    final topSale = salesQuery.findFirst();
    salesQuery.close();

    if (topSale != null && topSale.createdAt.isAfter(latest)) {
      latest = topSale.createdAt;
    }

    // Check Stock Transfers
    final transferQueryBuilder = obx.transferBox.query();
    transferQueryBuilder.order(StockTransfer_.transferredAt,
        flags: 1); // Descending
    final transferQuery = transferQueryBuilder.build();
    transferQuery.limit = 1;
    final topTransfer = transferQuery.findFirst();
    transferQuery.close();

    if (topTransfer != null && topTransfer.transferredAt.isAfter(latest)) {
      latest = topTransfer.transferredAt;
    }

    return latest;
  }
}
