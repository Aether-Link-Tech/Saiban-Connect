import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper over callable Cloud Functions (backend/functions/src/index.ts).
class FunctionsApi {
  FunctionsApi(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic>? data]) async {
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
    );
    final result = await callable.call<dynamic>(data ?? <String, dynamic>{});
    return deepMap(result.data);
  }

  static Map<String, dynamic> deepMap(Object? v) {
    if (v is! Map) return <String, dynamic>{};
    return v.map((k, val) => MapEntry(k.toString(), _deep(val)));
  }

  static Object? _deep(Object? v) {
    if (v is Map) return deepMap(v);
    if (v is List) return v.map(_deep).toList();
    return v;
  }
}
