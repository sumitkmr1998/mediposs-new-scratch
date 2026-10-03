import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/objectbox.g.dart';
import 'package:medipos/shared/models/medicine.dart';
import 'package:medipos/shared/models/sale.dart';
import 'package:medipos/shared/services/hub/sale_commit.dart';

void main() {
  late Directory directory;
  late Store store;
  late Medicine medicine;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mediposs-sync-test-');
    store = await openStore(directory: directory.path);
    medicine = Medicine(
        name: 'Test medicine',
        purchasePrice: 1,
        sellingPrice: 2,
        storeStock: 10);
    store.box<Medicine>().put(medicine);
  });
  tearDown(() async {
    store.close();
    await directory.delete(recursive: true);
  });
  Sale sale(String invoice, int qty, {bool missingSecond = false}) => Sale(
        invoiceNo: invoice,
        subtotal: qty * 2.0,
        total: qty * 2.0,
        createdAt: DateTime(2026, 10, 3),
        itemsJson: jsonEncode([
          SaleItem(
                  medicineId: medicine.id,
                  medicineName: medicine.name,
                  qty: qty,
                  unitPrice: 2)
              .toJson(),
          if (missingSecond)
            SaleItem(
                    medicineId: 999,
                    medicineName: 'Missing',
                    qty: 1,
                    unitPrice: 2)
                .toJson(),
        ]),
      );
  test('failure on second line rolls back first deduction and sale', () {
    expect(() => SaleCommit.apply(store, sale('INV-1', 3, missingSecond: true)),
        throwsStateError);
    expect(store.box<Medicine>().get(medicine.id)!.storeStock, 10);
    expect(store.box<Sale>().count(), 0);
  });
  test('lost ACK replay creates one sale and deducts stock once', () {
    SaleCommit.apply(store, sale('INV-1', 3));
    SaleCommit.apply(store, sale('INV-1', 3));
    expect(store.box<Sale>().count(), 1);
    expect(store.box<Medicine>().get(medicine.id)!.storeStock, 7);
  });
  test('rejected edit restores original sale and stock', () {
    SaleCommit.apply(store, sale('INV-1', 3));
    expect(() => SaleCommit.apply(store, sale('INV-1', 20)), throwsStateError);
    expect(store.box<Medicine>().get(medicine.id)!.storeStock, 7);
    expect(store.box<Sale>().getAll().single.total, 6);
  });
  test('repeated delete restores inventory once', () {
    SaleCommit.apply(store, sale('INV-1', 3));
    SaleCommit.delete(store, 'INV-1');
    SaleCommit.delete(store, 'INV-1');
    expect(store.box<Sale>().count(), 0);
    expect(store.box<Medicine>().get(medicine.id)!.storeStock, 10);
  });
  test('empty invoice cannot commit or erase an unrelated sale', () {
    expect(() => SaleCommit.apply(store, sale('', 3)), throwsFormatException);
    expect(() => SaleCommit.delete(store, ''), throwsFormatException);
    expect(store.box<Medicine>().get(medicine.id)!.storeStock, 10);
  });
}
