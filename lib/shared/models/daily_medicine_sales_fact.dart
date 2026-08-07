import 'package:objectbox/objectbox.dart';

/// Pre-aggregated daily units/revenue per medicine for analytics at scale.
@Entity()
class DailyMedicineSalesFact {
  @Id()
  int id = 0;

  /// Local calendar day start as millisecondsSinceEpoch.
  @Index()
  int dayEpochMs;

  @Index()
  int medicineId;

  /// Lowercased trimmed medicine name (fallback when id is 0).
  @Index()
  String medicineNameKey;

  int qtySold;
  double revenue;

  DailyMedicineSalesFact({
    this.id = 0,
    required this.dayEpochMs,
    this.medicineId = 0,
    this.medicineNameKey = '',
    this.qtySold = 0,
    this.revenue = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayEpochMs': dayEpochMs,
        'medicineId': medicineId,
        'medicineNameKey': medicineNameKey,
        'qtySold': qtySold,
        'revenue': revenue,
      };

  factory DailyMedicineSalesFact.fromJson(Map<String, dynamic> json) =>
      DailyMedicineSalesFact(
        id: json['id'] ?? 0,
        dayEpochMs: json['dayEpochMs'] ?? 0,
        medicineId: json['medicineId'] ?? 0,
        medicineNameKey: json['medicineNameKey'] ?? '',
        qtySold: json['qtySold'] ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      );
}
