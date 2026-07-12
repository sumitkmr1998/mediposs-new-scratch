import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/domain/transfer_rules.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/models/app_user.dart';

void main() {
  group('TransferRules Tests', () {
    test('should fail if user is unauthorized', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 10,
        storeStock: 10,
      );

      final user = AppUser(
        id: 1,
        name: 'Staff',
        role: 'user',
        canTransferStock: false,
      );

      final result = TransferRules.validateTransfer(
        medicine: med,
        qty: 5,
        from: 'main',
        to: 'store',
        actor: user,
      );

      expect(result, contains('Unauthorized'));
    });

    test('should fail if quantity is invalid', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 10,
        storeStock: 10,
      );

      final result = TransferRules.validateTransfer(
        medicine: med,
        qty: 0,
        from: 'main',
        to: 'store',
      );

      expect(result, contains('Quantity must be greater than 0'));
    });

    test('should fail if transferring expired stock to active locations', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 10,
        storeStock: 10,
      );

      final result = TransferRules.validateTransfer(
        medicine: med,
        qty: 5,
        from: 'bulkStore',
        to: 'store',
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(result, contains('Cannot transfer expired stock'));
    });

    test('should succeed for valid transfer parameters', () {
      final med = Medicine(
        id: 1,
        name: 'Paracetamol',
        purchasePrice: 8.0,
        sellingPrice: 10.0,
        mainStock: 10,
        storeStock: 10,
      );

      final result = TransferRules.validateTransfer(
        medicine: med,
        qty: 5,
        from: 'main',
        to: 'store',
      );

      expect(result, isNull);
    });
  });
}
