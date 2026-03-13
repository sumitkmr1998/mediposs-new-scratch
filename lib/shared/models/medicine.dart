import 'package:objectbox/objectbox.dart';

@Entity()
class Medicine {
  @Id()
  int id = 0;

  String name;
  String barcode;
  String category;
  String unit; // tablet, ml, capsule, syrup, etc.

  double purchasePrice;
  double sellingPrice;

  // These will now be aggregated from batches but kept for compatibility/legacy if needed,
  // or we can transition to getters. Let's keep them as cached values or transition.
  int mainStock; // Main Warehouse quantity
  int storeStock; // Store Stock (Shop floor) quantity

  int lowStockThreshold;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool synced;

  final batches = ToMany<MedicineBatch>();

  Medicine({
    this.id = 0,
    required this.name,
    this.barcode = '',
    this.category = 'General',
    this.unit = 'Pcs',
    required this.purchasePrice,
    required this.sellingPrice,
    this.mainStock = 0,
    this.storeStock = 0,
    this.lowStockThreshold = 10,
    DateTime? updatedAt,
    this.synced = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isLowStock => storeStock <= lowStockThreshold;
  int get totalStock => mainStock + storeStock;
  double get profitMargin => sellingPrice - purchasePrice;

  /// Returns the batch that is expiring soonest and has store stock
  MedicineBatch? get activeBatch {
    if (batches.isEmpty) return null;
    final available = batches.where((b) => b.storeStock > 0).toList();
    if (available.isEmpty) return null;
    available.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return available.first;
  }

  bool get hasExpiredBatch => batches.any((b) => 
      b.expiryDate.isBefore(DateTime.now()) && (b.mainStock > 0 || b.storeStock > 0));
  bool get hasNearExpiryBatch => batches.any((b) => 
      b.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90))) && 
      !b.expiryDate.isBefore(DateTime.now()) &&
      (b.mainStock > 0 || b.storeStock > 0));

  MedicineBatch? get soonestExpiringBatch {
    if (batches.isEmpty) return null;
    final sorted = batches.toList()..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return sorted.first;
  }
}

@Entity()
class MedicineBatch {
  @Id()
  int id = 0;

  String batchNo;
  
  @Property(type: PropertyType.date)
  DateTime expiryDate;

  int mainStock;
  int storeStock;

  final medicine = ToOne<Medicine>();

  MedicineBatch({
    this.id = 0,
    required this.batchNo,
    required this.expiryDate,
    this.mainStock = 0,
    this.storeStock = 0,
  });
}
