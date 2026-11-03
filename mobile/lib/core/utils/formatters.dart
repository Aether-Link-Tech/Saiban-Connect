import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Working-day key (YYYY-MM-DD) in organization time. Mirrors dateKeyOf() in the backend.
String orgDateKey(DateTime t) {
  final o = t.toUtc().add(AppConstants.orgUtcOffset);
  return '${o.year.toString().padLeft(4, '0')}-${_two(o.month)}-${_two(o.day)}';
}

String todayKey() => orgDateKey(DateTime.now());

String fmtTime(DateTime? t) => t == null ? '—' : DateFormat('hh:mm a').format(t.toLocal());

String fmtDate(DateTime? t) => t == null ? '—' : DateFormat('d MMM yyyy').format(t.toLocal());

String fmtDateTime(DateTime? t) => t == null ? '—' : DateFormat('d MMM yyyy, hh:mm a').format(t.toLocal());

/// "Mon, 3 Nov 2026" from a date key.
String fmtDateKey(String key) {
  final d = DateTime.tryParse(key);
  return d == null ? key : DateFormat('EEE, d MMM yyyy').format(d);
}

String dateKeyFromDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String fmtDuration(int? minutes) {
  if (minutes == null) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String relativeAge(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// Normalizes to international digits, default Pakistan (+92). Mirrors backend normalizePhone().
String? normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = '92${digits.substring(1)}';
  } else if (digits.length == 10 && digits.startsWith('3')) {
    digits = '92$digits';
  }
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

String syntheticEmailFor(String normalizedPhone) => 'p$normalizedPhone@${AppConstants.syntheticEmailDomain}';

bool isSyntheticEmail(String? email) =>
    email != null && email.toLowerCase().endsWith('@${AppConstants.syntheticEmailDomain}');

/// Great-circle distance in metres.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
}

const _flagLabels = {
  'outside_geofence': 'Outside site',
  'low_accuracy': 'Low GPS accuracy',
  'no_gps': 'No GPS',
  'mock_location': 'Mock location',
  'no_assigned_site': 'No assigned site',
  'late_sync': 'Synced late',
  'device_time_ahead': 'Device clock ahead',
  'no_biometric': 'No biometric',
  'duplicate_check_in': 'Duplicate check-in',
  'duplicate_check_out': 'Duplicate check-out',
  'check_out_without_check_in': 'Check-out without check-in',
  'check_out_before_check_in': 'Check-out before check-in',
  'missing_checkout': 'Missing check-out',
  'check_in_rejected_by_review': 'Check-in rejected',
  'check_out_rejected_by_review': 'Check-out rejected',
};

String flagLabel(String flag) => _flagLabels[flag] ?? flag.replaceAll('_', ' ');
