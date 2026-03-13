class Medicine {
  final int id;
  final String name;
  final String category;
  final String unit;
  final String barcode;
  final double purchasePrice;
  final double sellingPrice;
  final int mainStock;
  final int storeStock;
  final int lowStockThreshold;
  final List<MedicineBatch> batches;

  Medicine({
    required this.id,
    required this.name,
    required this.category,
    this.unit = 'Pcs',
    this.barcode = '',
    required this.purchasePrice,
    required this.sellingPrice,
    this.mainStock = 0,
    required this.storeStock,
    this.lowStockThreshold = 10,
    this.batches = const [],
  });

  int get totalStock => mainStock + storeStock;
  double get profitMargin => sellingPrice - purchasePrice;
  double get marginPercent =>
      sellingPrice > 0 ? (profitMargin / sellingPrice) * 100 : 0;
  bool get isLowStock => storeStock <= lowStockThreshold;

  bool get hasExpiredBatch => batches.any((b) => b.isExpired && (b.mainStock > 0 || b.storeStock > 0));
  bool get hasNearExpiryBatch => batches.any((b) => b.isNearExpiry && (b.mainStock > 0 || b.storeStock > 0));

  DateTime? get soonestExpiry {
    final activeBatches = batches.where((b) => b.mainStock > 0 || b.storeStock > 0).toList();
    if (activeBatches.isEmpty) return null;
    activeBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return activeBatches.first.expiryDate;
  }

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      category: json['category'] ?? 'General',
      unit: json['unit'] ?? 'Pcs',
      barcode: json['barcode'] ?? '',
      purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      mainStock: json['mainStock'] ?? 0,
      storeStock: json['storeStock'] ?? 0,
      lowStockThreshold: json['lowStockThreshold'] ?? 10,
      batches: (json['batches'] as List?)
              ?.map((e) => MedicineBatch.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class MedicineBatch {
  final int id;
  final String batchNo;
  final DateTime expiryDate;
  final int mainStock;
  final int storeStock;

  MedicineBatch({
    required this.id,
    required this.batchNo,
    required this.expiryDate,
    this.mainStock = 0,
    this.storeStock = 0,
  });

  factory MedicineBatch.fromJson(Map<String, dynamic> json) {
    return MedicineBatch(
      id: json['id'] ?? 0,
      batchNo: json['batchNo'] ?? '',
      expiryDate: DateTime.tryParse(json['expiryDate'] ?? '') ?? DateTime.now(),
      mainStock: json['mainStock'] ?? 0,
      storeStock: json['storeStock'] ?? 0,
    );
  }

  bool get isExpired => expiryDate.isBefore(DateTime.now());
  bool get isNearExpiry => expiryDate.isBefore(DateTime.now().add(const Duration(days: 90))) && !isExpired;
}
