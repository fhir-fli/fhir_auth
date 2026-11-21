/// The SMART on FHIR client with Flutter's sign-in window and token store.
library;

import 'package:fhir_auth/src/authenticators/web_authenticator.dart';
import 'package:fhir_auth/src/storage/secure_token_storage.dart';
import 'package:fhir_auth_core/fhir_auth_core.dart' as core;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// SMART on FHIR client for OAuth authentication.
///
/// The client from `fhir_auth_core`, with the two choices that need Flutter
/// made for you: sign-in opens a [WebAuthenticator] window and tokens are
/// kept in [SecureTokenStorage] (iOS Keychain, Android Keystore) unless you
/// pass others. Everything else is `fhir_auth_core`'s.
class SmartFhirClient extends core.SmartFhirClient {
  /// Create a SMART on FHIR client from [config], wiring in the platform
  /// [authenticator] (defaults to [WebAuthenticator]), [tokenStorage]
  /// (defaults to [SecureTokenStorage]) and an optional pre-built
  /// [oauthFlow], HTTP client, audit logger, and session manager.
  SmartFhirClient({
    required super.config,
    core.Authenticator? authenticator,
    super.oauthFlow,
    super.httpClient,
    super.auditLogger,
    super.sessionManager,
    super.logger,
    core.TokenStorage? tokenStorage,
  }) : super(
         authenticator: authenticator ?? WebAuthenticator(),
         tokenStorage: tokenStorage ?? SecureTokenStorage(),
       );

  /// How long a same-window login may take
  /// ([core.SmartFhirClient.redirectLoginLifetime]).
  static const Duration redirectLoginLifetime =
      core.SmartFhirClient.redirectLoginLifetime;

  /// The session-storage key of the login record whose OAuth `state` is
  /// [tabKey] ([core.SmartFhirClient.redirectTabKey]).
  static String redirectTabKey(String tabKey) =>
      core.SmartFhirClient.redirectTabKey(tabKey);

  /// Finish a same-window login
  /// ([core.SmartFhirClient.completeRedirectLogin]), returning this
  /// package's client.
  static Future<SmartFhirClient> completeRedirectLogin({
    required Uri callbackUrl,
    required core.KeyValueStore store,
    http.Client? httpClient,
    core.AuditLogger? auditLogger,
    core.SessionManager? sessionManager,
    Logger? logger,
    DateTime Function() now = DateTime.now,
  }) async =>
      await core.SmartFhirClient.completeRedirectLogin(
            callbackUrl: callbackUrl,
            store: store,
            httpClient: httpClient,
            auditLogger: auditLogger,
            sessionManager: sessionManager,
            logger: logger,
            now: now,
            createClient: SmartFhirClient.new,
          )
          as SmartFhirClient;

  /// [callbackUrl] without the one-time authorization `code`
  /// ([core.SmartFhirClient.redirectCallbackUrlToKeep]).
  static Uri redirectCallbackUrlToKeep(Uri callbackUrl) =>
      core.SmartFhirClient.redirectCallbackUrlToKeep(callbackUrl);
}
