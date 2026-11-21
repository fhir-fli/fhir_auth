import 'package:fhir_auth_core/fhir_auth_core.dart';

/// Token storage for a client whose test never stores or reads a token.
///
/// Before the split these clients took fhir_auth's default,
/// SecureTokenStorage, which has no platform behind it in a VM test, so
/// using it failed. Every call here fails too, so a test that starts
/// relying on storage says so instead of passing on a store it never chose.
class UntouchedTokenStorage implements TokenStorage {
  Never _used(String call) =>
      throw StateError(
        'UntouchedTokenStorage.$call: this test was not meant to use storage',
      );

  @override
  Future<void> saveTokens(SmartTokenResponse tokens) async =>
      _used('saveTokens');

  @override
  Future<SmartTokenResponse?> loadTokens() async => _used('loadTokens');

  @override
  Future<void> clearTokens() async => _used('clearTokens');

  @override
  Future<void> saveAuthState(AuthState state) async => _used('saveAuthState');

  @override
  Future<AuthState?> loadAuthState() async => _used('loadAuthState');

  @override
  Future<bool> hasTokens() async => _used('hasTokens');
}
