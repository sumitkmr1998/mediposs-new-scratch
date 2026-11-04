import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/domain/transfer_rules.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/models/app_user.dart';
import 'package:medipos/shared/models/stock_transfer.dart';

void main() {
  group('Stock Transfer Edit & Revert Logic Tests', () {
    late AppUser adminUser;
    late Medicine medicine;

    setUp(() {
      adminUser = AppUser(
        id: 1,
        name: 'Admin',
        role: 'admin',
        canTransferStock: true,
      );

      // Starting with 10 units in main, 5 units in store
      medicine = Medicine(
        id: 1,
        name: 'Amoxicillin 500mg',
        purchasePrice: 20.0,
        sellingPrice: 35.0,
        mainStock: 10,
        storeStock: 5,
        bulkClinicStock: 0,
        bulkStoreStock: 0,
      );
    });

    test('simulated initial transfer moves stock from main to store', () {
      final validation = TransferRules.validateTransfer(
        medicine: medicine,
        qty: 4,
        from: 'main',
        to: 'store',
        actor: adminUser,
      );
      expect(validation, isNull);

      // Apply transfer
      medicine.mainStock -= 4;
      medicine.storeStock += 4;

      expect(medicine.mainStock, 6);
      expect(medicine.storeStock, 9);
    });

    test('reverting an original transfer restores original stock levels', () {
      // Simulate transfer of 4 units
      medicine.mainStock = 6;
      medicine.storeStock = 9;

      final originalTransfer = StockTransfer(
        medicineId: medicine.id,
        medicineName: medicine.name,
        qty: 4,
        fromWarehouse: 'main',
        toWarehouse: 'store',
        transferredBy: adminUser.name,
        transferredAt: DateTime.now(),
        initialFromQty: 10,
        finalFromQty: 6,
        initialToQty: 5,
        finalToQty: 9,
      );

      // Revert step: transfer back from toWarehouse to fromWarehouse
      medicine.storeStock -= originalTransfer.qty;
      medicine.mainStock += originalTransfer.qty;

      expect(medicine.mainStock, 10);
      expect(medicine.storeStock, 5);
    });

    test('editing transfer allows increasing quantity if restored stock allows', () {
      // Original state before transfer: main: 10, store: 5
      // Current state after 4 units transferred: main: 6, store: 9
      medicine.mainStock = 6;
      medicine.storeStock = 9;

      final originalTransfer = StockTransfer(
        medicineId: medicine.id,
        medicineName: medicine.name,
        qty: 4,
        fromWarehouse: 'main',
        toWarehouse: 'store',
        transferredBy: adminUser.name,
        transferredAt: DateTime.now(),
        initialFromQty: 10,
        finalFromQty: 6,
        initialToQty: 5,
        finalToQty: 9,
      );

      // 1. Temporarily revert
      medicine.storeStock -= originalTransfer.qty;
      medicine.mainStock += originalTransfer.qty;
      expect(medicine.mainStock, 10);

      // 2. Validate new quantity: 7 units (which was > 6 currently in main, but <= 10 restored)
      final validation = TransferRules.validateTransfer(
        medicine: medicine,
        qty: 7,
        from: 'main',
        to: 'store',
        actor: adminUser,
      );
      expect(validation, isNull);

      // 3. Apply new transfer of 7 units
      medicine.mainStock -= 7;
      medicine.storeStock += 7;

      expect(medicine.mainStock, 3);
      expect(medicine.storeStock, 12);
    });

    test('editing transfer rejects quantity exceeding restored stock and rolls back cleanly', () {
      // Current state after 4 units transferred: main: 6, store: 9
      medicine.mainStock = 6;
      medicine.storeStock = 9;

      final originalTransfer = StockTransfer(
        medicineId: medicine.id,
        medicineName: medicine.name,
        qty: 4,
        fromWarehouse: 'main',
        toWarehouse: 'store',
        transferredBy: adminUser.name,
        transferredAt: DateTime.now(),
        initialFromQty: 10,
        finalFromQty: 6,
        initialToQty: 5,
        finalToQty: 9,
      );

      // 1. Temporarily revert
      medicine.storeStock -= originalTransfer.qty;
      medicine.mainStock += originalTransfer.qty;
      expect(medicine.mainStock, 10);

      // 2. Attempt to transfer 15 units (exceeds restored 10)
      final validation = TransferRules.validateTransfer(
        medicine: medicine,
        qty: 15,
        from: 'main',
        to: 'store',
        actor: adminUser,
      );
      expect(validation, isNotNull);
      expect(validation, contains('Insufficient stock'));

      // 3. On validation failure, rollback revert
      medicine.mainStock -= originalTransfer.qty;
      medicine.storeStock += originalTransfer.qty;

      // Stock remains safely at the pre-edit state
      expect(medicine.mainStock, 6);
      expect(medicine.storeStock, 9);
    });

    test('editing transfer to new destination changes locations correctly', () {
      // Current state after 4 units transferred: main: 6, store: 9, bulkClinic: 0
      medicine.mainStock = 6;
      medicine.storeStock = 9;
      medicine.bulkClinicStock = 0;

      final originalTransfer = StockTransfer(
        medicineId: medicine.id,
        medicineName: medicine.name,
        qty: 4,
        fromWarehouse: 'main',
        toWarehouse: 'store',
        transferredBy: adminUser.name,
        transferredAt: DateTime.now(),
        initialFromQty: 10,
        finalFromQty: 6,
        initialToQty: 5,
        finalToQty: 9,
      );

      // 1. Revert original
      medicine.storeStock -= originalTransfer.qty;
      medicine.mainStock += originalTransfer.qty;

      // 2. Apply new transfer from main to bulkClinic for 4 units
      final validation = TransferRules.validateTransfer(
        medicine: medicine,
        qty: 4,
        from: 'main',
        to: 'bulkClinic',
        actor: adminUser,
      );
      expect(validation, isNull);

      medicine.mainStock -= 4;
      medicine.bulkClinicStock += 4;

      // Verify final distribution
      expect(medicine.mainStock, 6);
      expect(medicine.storeStock, 5); // back to pre-transfer 5
      expect(medicine.bulkClinicStock, 4); // newly credited
    });
  
    test('admin has permission to edit transfers', () {
      final admin = AppUser(name: 'Admin', role: 'Admin');
      admin.applyPreset('Admin');

      expect(admin.canTransferStock, isTrue);
      expect(admin.canEditTransfers, isTrue);

      final result = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: admin,
      );
      expect(result, isNull);
    });

    test('manager has permission to edit transfers by preset', () {
      final manager = AppUser(name: 'Manager', role: 'Manager');
      manager.applyPreset('Manager');

      expect(manager.canTransferStock, isTrue);
      expect(manager.canEditTransfers, isTrue);

      final result = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: manager,
      );
      expect(result, isNull);
    });

    test('warehouse preset has permission to transfer and edit transfers', () {
      final whUser = AppUser(name: 'Warehouse Lead', role: 'Warehouse');
      whUser.applyPreset('Warehouse');

      expect(whUser.canViewWarehouse, isTrue);
      expect(whUser.canTransferStock, isTrue);
      expect(whUser.canEditTransfers, isTrue);

      final result = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: whUser,
      );
      expect(result, isNull);
    });

    test('pharmacist CAN transfer stock but CANNOT edit transfers by preset', () {
      final pharmacist = AppUser(name: 'Pharmacist', role: 'Pharmacist');
      pharmacist.applyPreset('Pharmacist');

      expect(pharmacist.canTransferStock, isTrue);
      expect(pharmacist.canEditTransfers, isFalse);

      // Can execute normal transfer
      final transferResult = TransferRules.validateTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: pharmacist,
      );
      expect(transferResult, isNull);

      // Cannot edit transfer
      final editResult = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: pharmacist,
      );
      expect(editResult, isNotNull);
      expect(editResult, contains('Unauthorized'));
    });

    test('cashier CANNOT transfer stock and CANNOT edit transfers', () {
      final cashier = AppUser(name: 'Cashier', role: 'Cashier');
      cashier.applyPreset('Cashier');

      expect(cashier.canTransferStock, isFalse);
      expect(cashier.canEditTransfers, isFalse);

      final editResult = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: cashier,
      );
      expect(editResult, isNotNull);
      expect(editResult, contains('Unauthorized'));
    });

    test('custom user with explicit canEditTransfers: true is permitted', () {
      final customStaff = AppUser(
        name: 'Staff Custom',
        role: 'Staff',
        canTransferStock: true,
        canEditTransfers: true,
      );

      final editResult = TransferRules.validateEditTransfer(
        medicine: medicine,
        qty: 3,
        from: 'main',
        to: 'store',
        actor: customStaff,
      );
      expect(editResult, isNull);
    });
  });
}
