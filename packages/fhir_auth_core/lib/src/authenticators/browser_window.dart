/// The parts of a browser window the same-window redirect login uses.
library;

import 'package:fhir_auth_core/fhir_auth_core.dart' show KeyValueStore;

/// The browser window the app runs in: its address, navigation, and session
/// storage.
///
/// Get the real one with `currentBrowserWindow()`, which works only when the
/// app is compiled for the web. Tests supply their own.
abstract class BrowserWindow {
  /// The window's current address.
  Uri get location;

  /// Leave the app and load [url] in this same window (or iframe).
  void assign(Uri url);

  /// Change the address shown, without loading anything or adding a history
  /// entry.
  void replaceUrl(Uri url);

  /// The window's session storage.
  KeyValueStore get sessionStorage;
}
