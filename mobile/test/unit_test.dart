import 'package:flutter_test/flutter_test.dart';
import 'package:saibaan_connect/core/utils/formatters.dart';
import 'package:saibaan_connect/domain/entities/app_policy.dart';
import 'package:saibaan_connect/domain/entities/models.dart';

void main() {
  group('orgDateKey', () {
    test('uses Pakistan time (UTC+5)', () {
      expect(orgDateKey(DateTime.utc(2026, 11, 2, 20)), '2026-11-03');
      expect(orgDateKey(DateTime.utc(2026, 11, 2, 18, 59)), '2026-11-02');
    });
  });

  group('normalizePhone', () {
    test('accepts Pakistani formats', () {
      expect(normalizePhone('0300-1234567'), '923001234567');
      expect(normalizePhone('+92 300 1234567'), '923001234567');
      expect(normalizePhone('3001234567'), '923001234567');
      expect(normalizePhone('123'), isNull);
    });
    test('synthetic email round-trip', () {
      expect(isSyntheticEmail(syntheticEmailFor('923001234567')), isTrue);
      expect(isSyntheticEmail('a@b.com'), isFalse);
    });
  });

  test('distanceMeters ~1 km', () {
    final d = distanceMeters(31.5204, 74.3587, 31.5294, 74.3587);
    expect(d, inInclusiveRange(990, 1010));
  });

  test('fmtDuration', () {
    expect(fmtDuration(125), '2h 5m');
    expect(fmtDuration(45), '45m');
    expect(fmtDuration(null), '—');
  });

  group('AppPolicy', () {
    test('defaults when missing', () {
      final p = AppPolicy.fromMap(null);
      expect(p.requiredApprovals, 2);
      expect(p.allowGallery, isFalse);
    });
    test('round-trips through toMap', () {
      final p = AppPolicy.fromMap(const AppPolicy(requiredApprovals: 3, allowGallery: true).toMap());
      expect(p.requiredApprovals, 3);
      expect(p.allowGallery, isTrue);
    });
  });

  test('UserRole.parse falls back to employee', () {
    expect(UserRole.parse('manager'), UserRole.manager);
    expect(UserRole.parse('nonsense'), UserRole.employee);
    expect(UserRole.admin.isHrOrAdmin, isTrue);
    expect(UserRole.supervisor.canReviewLeave, isFalse);
  });
}
