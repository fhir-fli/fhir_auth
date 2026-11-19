/// `currentBrowserWindow()` in a web build, over `package:web`.
library;

import 'package:fhir_auth/fhir_auth.dart' show BrowserWindow, KeyValueStore;
import 'package:web/web.dart' as web;

/// The window the app runs in.
BrowserWindow currentBrowserWindow() => const _WebBrowserWindow();

class _WebBrowserWindow implements BrowserWindow {
  const _WebBrowserWindow();

  @override
  Uri get location => Uri.parse(web.window.location.href);

  @override
  void assign(Uri url) => web.window.location.assign(url.toString());

  @override
  void replaceUrl(Uri url) =>
      web.window.history.replaceState(null, '', url.toString());

  @override
  KeyValueStore get sessionStorage => const _SessionStorage();
}

class _SessionStorage implements KeyValueStore {
  const _SessionStorage();

  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);

  @override
  void remove(String key) => web.window.sessionStorage.removeItem(key);
}
