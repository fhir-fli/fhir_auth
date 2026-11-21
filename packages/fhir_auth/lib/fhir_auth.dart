/// SMART on FHIR authentication for Flutter apps.
///
/// Everything in the pure-Dart `fhir_auth_core`, plus the parts that need
/// Flutter: the pop-up / system-browser sign-in ([WebAuthenticator]), native
/// phone sign-in ([MobileAuthenticator]), Keychain/Keystore token storage
/// ([SecureTokenStorage]), and a [SmartFhirClient] that uses the first and
/// the last when you name no others.
library;

export 'package:fhir_auth_core/fhir_auth_core.dart' hide SmartFhirClient;

export 'src/authenticators/mobile_authenticator.dart';
export 'src/authenticators/web_authenticator.dart';
export 'src/smart/smart_client.dart';
export 'src/storage/secure_token_storage.dart';
