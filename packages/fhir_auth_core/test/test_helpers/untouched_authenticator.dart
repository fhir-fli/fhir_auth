import 'package:fhir_auth_core/fhir_auth_core.dart';

/// An authenticator for a client whose test must fail before any sign-in
/// window would open.
///
/// Before the split these clients took fhir_auth's default,
/// WebAuthenticator, and the test's check refused the login before it was
/// used. Opening this one fails the test, so it still shows that the check
/// came first.
class UntouchedAuthenticator implements Authenticator {
  @override
  Future<Uri> authenticate({
    required Uri authorizationUrl,
    required Uri redirectUri,
    String? callbackUrlScheme,
  }) =>
      throw StateError(
        'UntouchedAuthenticator: the login should have been refused before '
        'the sign-in window opened',
      );

  @override
  void cancel() {}
}
