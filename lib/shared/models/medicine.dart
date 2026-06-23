import 'package:objectbox/objectbox.dart';
import '../utils/date_helper.dart';

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
  int mainStock; // Clinic quantity
  int storeStock; // Store Stock (Shop floor) quantity
  int bulkClinicStock; // Clinic Bulk Warehouse quantity
  int bulkStoreStock; // Store Bulk Warehouse quantity

  int lowStockThreshold;
  bool isScheduleH1;

  @Property(type: PropertyType.date)
  DateTime createdAt;

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
    this.bulkClinicStock = 0,
    this.bulkStoreStock = 0,
    this.lowStockThreshold = 10,
    this.isScheduleH1 = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.synced = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'category': category,
        'unit': unit,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
        'mainStock': mainStock,
        'storeStock': storeStock,
        'bulkClinicStock': bulkClinicStock,
        'bulkStoreStock': bulkStoreStock,
        'lowStockThreshold': lowStockThreshold,
        'isScheduleH1': isScheduleH1,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'synced': synced,
        'batches': batches.map((b) => b.toJson()).toList(),
      };

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final medicine = Medicine(
      id: json['id'] ?? 0,
      name: json['name'],
      barcode: json['barcode'] ?? '',
      category: json['category'] ?? 'General',
      unit: json['unit'] ?? 'Pcs',
      purchasePrice: (json['purchasePrice'] as num).toDouble(),
      sellingPrice: (json['sellingPrice'] as num).toDouble(),
      mainStock: json['mainStock'] ?? 0,
      storeStock: json['storeStock'] ?? 0,
      bulkClinicStock: json['bulkClinicStock'] ?? 0,
      bulkStoreStock: json['bulkStoreStock'] ?? 0,
      lowStockThreshold: json['lowStockThreshold'] ?? 10,
      isScheduleH1: json['isScheduleH1'] ?? false,
      createdAt: DateHelper.parseDateTime(json['createdAt']),
      updatedAt: DateHelper.parseDateTime(json['updatedAt']),
      synced: json['synced'] ?? false,
    );
    if (json['batches'] != null) {
      final batchList = (json['batches'] as List)
          .map((b) => MedicineBatch.fromJson(b))
          .toList();
      medicine.batches.addAll(batchList);
    }
    return medicine;
  }
 
  /// Recalculates aggregate stock fields from individual batches.
  void recalculateStockFromBatches() {
    int totalMain = 0;
    int totalStore = 0;
    int totalBulkClinic = 0;
    int totalBulkStore = 0;
    for (final batch in batches) {
      totalMain += batch.mainStock;
      totalStore += batch.storeStock;
      totalBulkClinic += batch.bulkClinicStock;
      totalBulkStore += batch.bulkStoreStock;
    }
    mainStock = totalMain.clamp(0, 999999);
    storeStock = totalStore.clamp(0, 999999);
    bulkClinicStock = totalBulkClinic.clamp(0, 999999);
    bulkStoreStock = totalBulkStore.clamp(0, 999999);
    updatedAt = DateTime.now();
  }

  bool get isLowStock => storeStock <= lowStockThreshold;
  int get totalStock => mainStock + storeStock + bulkClinicStock + bulkStoreStock;
  double get profitMargin => sellingPrice - purchasePrice;

  /// Returns the batch that is expiring soonest and has store stock
  MedicineBatch? get activeBatch {
    if (batches.isEmpty) return null;
    final now = DateTime.now();
    final available = batches.where((b) => b.storeStock > 0 && !b.expiryDate.isBefore(now)).toList();
    if (available.isEmpty) return null;
    available.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return available.first;
  }

  /// Returns the batch that is expiring soonest and has stock for the active mode
  MedicineBatch? getActiveBatch(bool isClinicalDispense) {
    if (batches.isEmpty) return null;
    final now = DateTime.now();
    final available = batches.where((b) {
      if (b.expiryDate.isBefore(now)) return false;
      return isClinicalDispense ? b.mainStock > 0 : b.storeStock > 0;
    }).toList();
    if (available.isEmpty) return null;
    available.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return available.first;
  }

  int getNonExpiredMainStock() {
    final now = DateTime.now();
    return batches
        .where((b) => !b.expiryDate.isBefore(now))
        .fold(0, (sum, b) => sum + b.mainStock);
  }

  int getNonExpiredStoreStock() {
    final now = DateTime.now();
    return batches
        .where((b) => !b.expiryDate.isBefore(now))
        .fold(0, (sum, b) => sum + b.storeStock);
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
  int bulkClinicStock;
  int bulkStoreStock;

  final medicine = ToOne<Medicine>();

  MedicineBatch({
    this.id = 0,
    required this.batchNo,
    required this.expiryDate,
    this.mainStock = 0,
    this.storeStock = 0,
    this.bulkClinicStock = 0,
    this.bulkStoreStock = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchNo': batchNo,
        'expiryDate': expiryDate.toIso8601String(),
        'mainStock': mainStock,
        'storeStock': storeStock,
        'bulkClinicStock': bulkClinicStock,
        'bulkStoreStock': bulkStoreStock,
      };

  factory MedicineBatch.fromJson(Map<String, dynamic> json) => MedicineBatch(
        id: json['id'] ?? 0,
        batchNo: json['batchNo'],
        expiryDate: DateHelper.parseDateTime(json['expiryDate']) ?? DateTime.now(),
        mainStock: json['mainStock'] ?? 0,
        storeStock: json['storeStock'] ?? 0,
        bulkClinicStock: json['bulkClinicStock'] ?? 0,
        bulkStoreStock: json['bulkStoreStock'] ?? 0,
      );
}
