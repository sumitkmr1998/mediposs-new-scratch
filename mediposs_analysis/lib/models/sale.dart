import 'dart:convert';

class Sale {
  final int id;
  final String invoiceNo;
  final String patientName;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String paymentMethod;
  final DateTime createdAt;
  final bool isReturn;
  final List<SaleItem> items;

  Sale({
    required this.id,
    required this.invoiceNo,
    required this.patientName,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    required this.isReturn,
    required this.items,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    List<dynamic> rawItems = [];
    if (json['items'] is List) {
      rawItems = json['items'];
    } else if (json['itemsJson'] is String) {
      try {
        rawItems = jsonDecode(json['itemsJson']);
      } catch (_) {}
    }

    return Sale(
      id: json['id'] ?? 0,
      invoiceNo: json['invoiceNo'] ?? '',
      patientName: json['patientName'] ?? 'Unknown',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] ?? 'cash',
      createdAt: DateTime.parse(json['createdAt']),
      isReturn: json['isReturn'] ?? false,
      items: rawItems.map((e) => SaleItem.fromJson(e)).toList(),
    );
  }
}

class SaleItem {
  final int medicineId;
  final String medicineName;
  final int qty;
  final double unitPrice;

  double get lineTotal => qty * unitPrice;

  SaleItem({
    required this.medicineId,
    required this.medicineName,
    required this.qty,
    required this.unitPrice,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    // Try multiple possible field names for medicine ID
    dynamic rawId = json['medicineId'] ??
                    json['medicine_id'] ??
                    json['medId'] ??
                    json['productId'] ??
                    json['itemId'] ??
                    0;

    // Convert string to int if needed
    int medicineId;
    if (rawId is int) {
      medicineId = rawId;
    } else if (rawId is String) {
      medicineId = int.tryParse(rawId) ?? 0;
    } else {
      medicineId = 0;
    }

    // Try multiple possible field names for medicine name
    String medicineName = json['medicineName'] ??
                          json['medicine_name'] ??
                          json['productName'] ??
                          json['itemName'] ??
                          json['name'] ??
                          '';

    return SaleItem(
      medicineId: medicineId,
      medicineName: medicineName,
      qty: json['qty'] ?? json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ??
                 (json['price'] as num?)?.toDouble() ??
                 (json['sellingPrice'] as num?)?.toDouble() ??
                 0.0,
    );
  }
}
