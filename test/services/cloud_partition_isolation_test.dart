import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/objectbox_service.dart';
import 'package:medipos/shared/models/medicine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shop Partition Sanitization & Isolation Tests', () {
    test('sanitizeShopId formats and preserves valid shop IDs', () {
      expect(ObjectBoxService.sanitizeShopId('MEDIPOSS'), equals('MEDIPOSS'));
      expect(ObjectBoxService.sanitizeShopId('mediposs-test'), equals('mediposs-test'));
      expect(ObjectBoxService.sanitizeShopId('clinic_1'), equals('clinic_1'));
    });

    test('sanitizeShopId fallbacks to default_shop for empty or blank input', () {
      expect(ObjectBoxService.sanitizeShopId(''), equals('default_shop'));
      expect(ObjectBoxService.sanitizeShopId('   '), equals('default_shop'));
    });

    test('sanitizeShopId cleans illegal path characters safely', () {
      expect(ObjectBoxService.sanitizeShopId('Shop/Branch:1'), equals('Shop_Branch_1'));
      expect(ObjectBoxService.sanitizeShopId('Branch #2 @ North'), equals('Branch__2___North'));
    });
  });

  group('Cloud Mode Medicine Catalog Scoping & Orphan Pruning Logic', () {
    test('Identifies foreign medicines from another shop as orphans to prune', () {
      // Suppose local partition has medicines from MEDIPOSS and mediposs-test (prior cross-contamination)
      final localMedicines = [
        Medicine(id: 1, name: 'Paracetamol 500mg', barcode: '8901001'),
        Medicine(id: 2, name: 'Amoxicillin 250mg', barcode: '8901002'),
        Medicine(id: 3, name: 'Ibuprofen 400mg', barcode: '8902001'), // From mediposs-test
        Medicine(id: 4, name: 'Cough Syrup', barcode: '8902002'),     // From mediposs-test
      ];

      // Cloud catalog for shop MEDIPOSS only has Paracetamol and Amoxicillin
      final fbMedsCloudForMediposs = [
        {'id': 101, 'name': 'Paracetamol 500mg', 'barcode': '8901001', 'sellingPrice': 20.0},
        {'id': 102, 'name': 'Amoxicillin 250mg', 'barcode': '8901002', 'sellingPrice': 45.0},
      ];

      final cloudBarcodes = <String>{};
      final cloudNames = <String>{};
      final claimedLocalIds = <int>{};

      for (var mMap in fbMedsCloudForMediposs) {
        final bc = (mMap['barcode'] as String? ?? '').trim();
        if (bc.isNotEmpty) cloudBarcodes.add(bc);
        final nm = (mMap['name'] as String? ?? '').trim().toLowerCase();
        if (nm.isNotEmpty) cloudNames.add(nm);

        final existing = localMedicines.where((x) {
          final bcMatch = x.barcode.isNotEmpty && x.barcode == bc;
          final nameMatch = x.name.toLowerCase() == nm;
          return bcMatch || nameMatch;
        }).firstOrNull;

        if (existing != null) {
          claimedLocalIds.add(existing.id);
        }
      }

      // Reconcile orphans (same logic as in syncAllFromCloud)
      final toRemoveIds = <int>[];
      for (final m in localMedicines) {
        if (claimedLocalIds.contains(m.id)) continue;
        final bc = m.barcode.trim();
        final matchesBar = bc.isNotEmpty && cloudBarcodes.contains(bc);
        final matchesName = cloudNames.contains(m.name.trim().toLowerCase());
        if (!matchesBar && !matchesName) {
          toRemoveIds.add(m.id);
        }
      }

      // Claimed should only be MEDIPOSS medicines
      expect(claimedLocalIds, containsAll([1, 2]));
      expect(claimedLocalIds.contains(3), isFalse);
      expect(claimedLocalIds.contains(4), isFalse);

      // Foreign medicines 3 and 4 (from mediposs-test) must be marked for removal
      expect(toRemoveIds, equals([3, 4]));

      // Remaining medicines strictly belong to MEDIPOSS
      final purgedList = localMedicines.where((m) => !toRemoveIds.contains(m.id)).toList();
      expect(purgedList.length, equals(2));
      expect(purgedList.map((m) => m.name), containsAll(['Paracetamol 500mg', 'Amoxicillin 250mg']));
    });
  });
}

