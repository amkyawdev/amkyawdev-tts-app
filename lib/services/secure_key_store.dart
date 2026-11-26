import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys are intentionally short and stable. Values never enter logs, history,
/// settings exports or crash reports.
class SecureKeys {
  const SecureKeys._();

  static const String geminiApiKey = 'gemini_api_key';
  static const String vieneuToken = 'vieneu_token';
}

abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Test double. It is deliberately kept in `lib/` so previews and widget tests
/// can inject it; the production app always constructs [FlutterSecureKeyStore].
class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
