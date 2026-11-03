class AppConstants {
  AppConstants._();

  static const appName = 'SAIBAAN Connect';
  static const organization = 'SAIBAAN Development Organization';

  /// Must match REGION in backend/functions/src/core/firebase.ts.
  static const functionsRegion = 'asia-south1';

  /// Organization time zone: Asia/Karachi (UTC+5, no daylight saving).
  static const orgUtcOffset = Duration(hours: 5);

  /// Phone-only accounts sign in with a synthetic email on this domain.
  static const syntheticEmailDomain = 'users.saibaan-connect.app';
}
