# fhir_auth_core

[![pub package](https://img.shields.io/pub/v/fhir_auth_core.svg)](https://pub.dev/packages/fhir_auth_core)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

SMART on FHIR authentication in pure Dart, for every FHIR version: SMART
discovery, OAuth 2.0 with PKCE, ID-token checks, token refresh,
introspection and revocation, backend services, sessions, audit logging, and
a same-window login for web pages embedded in an EHR.

No Flutter. For a Flutter app use
[fhir_auth](https://pub.dev/packages/fhir_auth), which exports all of this
package and adds the pop-up and phone sign-in windows and Keychain/Keystore
token storage.

## Install

```yaml
dependencies:
  fhir_auth_core: ^0.15.0
```

## Sign in from a web page inside the EHR

Epic shows SMART apps in an iframe in the patient chart, so the page signs in
with a same-window redirect in two halves:

```dart
import 'package:fhir_auth_core/fhir_auth_core.dart';

final window = currentBrowserWindow();

// Launch page (the EHR opened it with ?iss=...&launch=...). This client
// keeps no tokens; the login's secrets go to session storage.
final url = await SmartFhirClient(
  config: config,
  tokenStorage: TabTokenStorage(store: MemoryKeyValueStore(), tabKey: 'launch'),
).beginRedirectLogin(store: window.sessionStorage);
window.assign(url); // the page unloads

// Redirect-URI page, on every load (first arrival and any reload):
final client = await SmartFhirClient.completeRedirectLogin(
  callbackUrl: window.location,
  store: window.sessionStorage,
);
window.replaceUrl(SmartFhirClient.redirectCallbackUrlToKeep(window.location));
final patientId = (await client.getStoredTokens())?.patientContext;
```

The login's `state` names the tab and stays in the address, and each tab's
tokens are stored under it, so two chart tabs on two patients never share
tokens. Only public clients are allowed. A `state` this browser session did
not start, or one older than ten minutes, is refused, and a code is exchanged
once.

## What you choose

This package picks nothing that needs a platform:

- `tokenStorage` is required. In a browser tab, `TabTokenStorage` over
  `window.sessionStorage`; elsewhere, your own `TokenStorage`.
- `SmartFhirClient.login()` for a user login needs an `authenticator` to open
  the sign-in window. Without one it throws `ConfigurationException`
  (`configurationField: 'authenticator'`) before any request. Backend
  services and the same-window login need none.

## Testing

```bash
dart test
dart test --platform chrome test/web
```

## License

BSD-3-Clause, see [LICENSE](LICENSE).
