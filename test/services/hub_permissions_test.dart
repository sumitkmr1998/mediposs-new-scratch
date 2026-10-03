import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/models/app_user.dart';
import 'package:medipos/shared/services/hub_permissions.dart';

void main() {
  test('cashier cannot administer users or read medical records', () {
    final cashier = AppUser(name: 'Cashier', pin: '9999');
    expect(HubPermissions.allows(cashier, 'manageUsers'), isFalse);
    expect(HubPermissions.allows(cashier, 'medicalRecords'), isFalse);
    expect(HubPermissions.allows(cashier, 'unknown'), isFalse);
  });

  test('deactivation revokes even administrator permissions', () {
    final admin = AppUser(name: 'Admin', role: 'Admin', isActive: false);
    expect(HubPermissions.allows(admin, 'manageUsers'), isFalse);
  });
}
