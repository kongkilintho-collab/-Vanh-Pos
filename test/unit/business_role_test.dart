import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/shared/models/business_role.dart';

void main() {
  group('BusinessRole', () {
    test('rank ordering matches OWNER > ADMIN > MANAGER > CASHIER > STAFF', () {
      expect(BusinessRole.owner.rank, greaterThan(BusinessRole.admin.rank));
      expect(BusinessRole.admin.rank, greaterThan(BusinessRole.manager.rank));
      expect(BusinessRole.manager.rank, greaterThan(BusinessRole.cashier.rank));
      expect(BusinessRole.cashier.rank, greaterThan(BusinessRole.staff.rank));
    });

    test('isAtLeast is reflexive and respects hierarchy', () {
      expect(BusinessRole.manager.isAtLeast(BusinessRole.manager), isTrue);
      expect(BusinessRole.owner.isAtLeast(BusinessRole.staff), isTrue);
      expect(BusinessRole.staff.isAtLeast(BusinessRole.manager), isFalse);
      expect(BusinessRole.cashier.isAtLeast(BusinessRole.admin), isFalse);
    });

    test('fromDb round-trips with dbValue', () {
      for (final role in BusinessRole.values) {
        expect(BusinessRole.fromDb(role.dbValue), role);
      }
    });
  });
}
