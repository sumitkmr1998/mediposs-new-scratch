import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../models/medicine.dart';
import '../objectbox_service.dart';
import '../../../objectbox.g.dart';

/// Hub HTTP handlers for medicine list/sync (extracted from LocalServerService).
class MedicinesRoutes {
  static Response getMedicines(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final limitStr = req.url.queryParameters['limit'];
    final offsetStr = req.url.queryParameters['offset'];
    final limit = int.tryParse(limitStr ?? '');
    final offset = int.tryParse(offsetStr ?? '');

    final box = ObjectBoxService.instance.medicineBox;
    final QueryBuilder<Medicine> queryBuilder;
    if (sinceStr != null && sinceStr.isNotEmpty) {
      final since = DateTime.tryParse(sinceStr);
      if (since != null) {
        queryBuilder = box.query(Medicine_.updatedAt.greaterThan(since.millisecondsSinceEpoch));
      } else {
        queryBuilder = box.query();
      }
    } else {
      queryBuilder = box.query();
    }
    final query = queryBuilder.build();
    try {
      if (offset != null) query.offset = offset;
      if (limit != null) query.limit = limit;
      final medicines = query.find();

      final json = medicines.map(_medicineToJson).toList();
      return Response.ok(
        jsonEncode({
          'data': json,
          'count': json.length,
          'serverTime': DateTime.now().millisecondsSinceEpoch,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    } finally {
      query.close();
    }
  }

  static Map<String, dynamic> _medicineToJson(Medicine m) => {
        'id': m.id,
        'name': m.name,
        'barcode': m.barcode,
        'category': m.category,
        'unit': m.unit,
        'purchasePrice': m.purchasePrice,
        'sellingPrice': m.sellingPrice,
        'mainStock': m.mainStock,
        'storeStock': m.storeStock,
        'bulkClinicStock': m.bulkClinicStock,
        'bulkStoreStock': m.bulkStoreStock,
        'lowStockThreshold': m.lowStockThreshold,
        'isScheduleH1': m.isScheduleH1,
        'createdAt': m.createdAt.toIso8601String(),
        'updatedAt': m.updatedAt.toIso8601String(),
        'batches': m.batches.map((b) => b.toJson()).toList(),
      };
}
