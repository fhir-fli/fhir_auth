/// A synchronous string store, the shape of a browser's `sessionStorage`.
library;

/// A string-to-string store with synchronous reads and writes.
///
/// The same-window redirect login keeps what it needs between leaving the
/// app and coming back in one of these. In a browser it is
/// `window.sessionStorage` (see `currentBrowserWindow`); in tests and on
/// other platforms it is a [MemoryKeyValueStore].
abstract class KeyValueStore {
  /// Every key currently stored.
  Iterable<String> get keys;

  /// The value stored under [key], or null when there is none.
  String? read(String key);

  /// Store [value] under [key], replacing any earlier value.
  void write(String key, String value);

  /// Remove whatever is stored under [key].
  void remove(String key);
}

/// A [KeyValueStore] held in memory, for tests and non-browser platforms.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Iterable<String> get keys => List<String>.of(_values.keys);

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);
}
