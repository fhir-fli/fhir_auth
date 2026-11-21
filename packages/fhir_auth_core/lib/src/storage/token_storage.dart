/// Token storage interface for secure credential management
library;

import 'package:fhir_auth_core/fhir_auth_core.dart'
    show AuthState, SmartTokenResponse;

/// Where a client keeps its tokens and authentication state.
///
/// This package has [TabTokenStorage] (one browser tab's tokens in a
/// [KeyValueStore], such as `sessionStorage`). The Flutter package
/// `fhir_auth` adds `SecureTokenStorage`, backed by the iOS Keychain and the
/// Android Keystore.
abstract class TokenStorage {
  /// Save tokens securely
  Future<void> saveTokens(SmartTokenResponse tokens);

  /// Load tokens from storage
  Future<SmartTokenResponse?> loadTokens();

  /// Clear all tokens
  Future<void> clearTokens();

  /// Save authentication state
  Future<void> saveAuthState(AuthState state);

  /// Load authentication state
  Future<AuthState?> loadAuthState();

  /// Check if tokens exist
  Future<bool> hasTokens();
}
