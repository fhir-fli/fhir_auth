/// Token storage scoped to one browser tab.
library;

import 'dart:convert';

import 'package:fhir_auth/fhir_auth.dart'
    show
        AuthState,
        KeyValueStore,
        SmartTokenResponse,
        StorageException,
        TokenStorage;

/// Keeps one tab's tokens in a [KeyValueStore], under keys that carry
/// [tabKey].
///
/// Epic's "Embedding in Multiple Tabs" guidance (fhir.epic.com
/// Documentation) says Hyperspace can show several patients at once, each in
/// its own embedded tab, and that its browser does not keep session storage
/// apart per tab: "If your app stores tab-specific data in session storage,
/// you need to use the unique tabId from above to store off this data per
/// tab." [tabKey] is that tab id. The same-window login uses the OAuth
/// `state` of the login that opened the tab, which stays in the tab's URL.
class TabTokenStorage implements TokenStorage {
  /// Store tokens for the tab named [tabKey] in [store].
  TabTokenStorage({required this.store, required this.tabKey});

  /// Where the values live; `window.sessionStorage` in a browser.
  final KeyValueStore store;

  /// The tab these tokens belong to.
  final String tabKey;

  /// The key the tokens are stored under.
  String get tokensKey => 'fhir_auth.tab.$tabKey.tokens';

  /// The key the authentication state is stored under.
  String get authStateKey => 'fhir_auth.tab.$tabKey.auth_state';

  @override
  Future<void> saveTokens(SmartTokenResponse tokens) async =>
      store.write(tokensKey, tokens.toStoredJson());

  @override
  Future<SmartTokenResponse?> loadTokens() async {
    final json = store.read(tokensKey);
    if (json == null) return null;
    final SmartTokenResponse tokens;
    try {
      tokens = SmartTokenResponse.fromStoredJson(json);
    } on FormatException catch (e, stackTrace) {
      store.remove(tokensKey);
      throw StorageException(
        'Token storage was corrupted and has been cleared',
        details: e.toString(),
        innerException: e,
        stackTrace: stackTrace,
        isCorrupted: true,
      );
    }
    // Same rule as SecureTokenStorage: an expired token that cannot be
    // refreshed is of no use, so it is cleared rather than returned.
    if (tokens.isExpired && tokens.refreshToken == null) {
      await clearTokens();
      return null;
    }
    return tokens;
  }

  @override
  Future<void> clearTokens() async {
    store
      ..remove(tokensKey)
      ..remove(authStateKey);
  }

  @override
  Future<void> saveAuthState(AuthState state) async =>
      store.write(authStateKey, jsonEncode(state.toJson()));

  @override
  Future<AuthState?> loadAuthState() async {
    final json = store.read(authStateKey);
    if (json == null) return null;
    try {
      return AuthState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Object {
      // As in SecureTokenStorage: unreadable state must not stop the app.
      store.remove(authStateKey);
      return null;
    }
  }

  @override
  Future<bool> hasTokens() async => store.read(tokensKey) != null;
}
