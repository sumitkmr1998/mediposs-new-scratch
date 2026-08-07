import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../objectbox_service.dart';
import '../../../objectbox.g.dart';

/// Hub GET /api/sales with since/limit/offset (extracted from LocalServerService).
class SalesRoutes {
  static Response getSales(Request req) {
    final sinceStr = req.url.queryParameters['since'];
    final sinceMs = int.tryParse(sinceStr ?? '') ??
        (DateTime.tryParse(sinceStr ?? '')?.millisecondsSinceEpoch) ??
        0;
    final limitStr = req.url.queryParameters['limit'];
    final offsetStr = req.url.queryParameters['offset'];
    final limit = int.tryParse(limitStr ?? '');
    final offset = int.tryParse(offsetStr ?? '');

    final box = ObjectBoxService.instance.saleBox;
    final queryBuilder = box.query(Sale_.updatedAt.greaterThan(sinceMs - 1));
    final query = queryBuilder.build();
    try {
      if (offset != null) query.offset = offset;
      if (limit != null) query.limit = limit;
      final sales = query.find();

      debugPrint(
          'Hub: Sales sync requested (since=$sinceMs, limit=$limit, offset=$offset). Returning ${sales.length} sales.');

      final json = sales
          .map((s) => {
                'id': s.id,
                'invoiceNo': s.invoiceNo,
                'patientId': s.patientId,
                'patientName': s.patientName,
                'patientPhone': s.patientPhone,
                'patientUhid': s.patientUhid,
                'subtotal': s.subtotal,
                'discount': s.discount,
                'taxRate': s.taxRate,
                'taxAmount': s.taxAmount,
                'total': s.total,
                'paymentMethod': s.paymentMethod,
                'cashAmount': s.cashAmount,
                'upiAmount': s.upiAmount,
                'cardAmount': s.cardAmount,
                'createdAt': s.createdAt.toIso8601String(),
                'updatedAt': s.updatedAt.toIso8601String(),
                'synced': s.synced,
                'isReturn': s.isReturn,
                'isClinicalDispense': s.isClinicalDispense,
                'linkedAppointmentId': s.linkedAppointmentId,
                'linkedProcedureId': s.linkedProcedureId,
                'opdInvoiceNo': s.opdInvoiceNo,
                'itemsJson': s.itemsJson,
              })
          .toList();
      return Response.ok(
        jsonEncode({
          'data': json,
          'serverTime': DateTime.now().millisecondsSinceEpoch,
        }),
        headers: {'content-type': 'application/json'},
      );
    } finally {
      query.close();
    }
  }
}
