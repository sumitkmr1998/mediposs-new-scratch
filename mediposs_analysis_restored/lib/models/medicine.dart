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
  });

  int get totalStock => mainStock + storeStock;
  double get profitMargin => sellingPrice - purchasePrice;
  double get marginPercent =>
      sellingPrice > 0 ? (profitMargin / sellingPrice) * 100 : 0;
  bool get isLowStock => storeStock <= lowStockThreshold;

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
    );
  }
}
