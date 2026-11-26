import 'package:shared_preferences/shared_preferences.dart';

/// Small abstraction over key-value persistence so settings can be tested
/// without platform channels.
abstract class KeyValueStore {
  String? getString(String key);
  bool? getBool(String key);
  double? getDouble(String key);
  Set<String> keys();

  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> setDouble(String key, double value);
  Future<void> remove(String key);
}

class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  double? getDouble(String key) => _prefs.getDouble(key);

  @override
  Set<String> keys() => _prefs.getKeys();

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  @override
  Future<void> setDouble(String key, double value) async {
    await _prefs.setDouble(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, Object>? seed]) : _values = {...?seed};

  final Map<String, Object> _values;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => (_values[key] as num?)?.toDouble();

  @override
  Set<String> keys() => _values.keys.toSet();

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
