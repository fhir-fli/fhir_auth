# fhir_auth

[![pub package](https://img.shields.io/pub/v/fhir_auth.svg)](https://pub.dev/packages/fhir_auth)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

Production-ready SMART on FHIR authentication and authorization for Flutter applications. Implements the complete SMART App Launch specification with enterprise-grade security.

Everything that needs no Flutter lives in the pure-Dart package
[fhir_auth_core](https://pub.dev/packages/fhir_auth_core), which this package
exports in full. Use `fhir_auth_core` directly for a plain Dart web page, a
server or a command-line tool; use this package in a Flutter app, for the
pop-up and phone sign-in windows and Keychain/Keystore token storage.

## Features

✅ **Complete SMART on FHIR Implementation**
- Standalone launch (patient-facing apps)
- EHR launch (embedded within EHR systems)
- Backend services (server-to-server)

✅ **Security Best Practices**
- PKCE (Proof Key for Code Exchange) required by default
- Secure token storage with encryption
- JWT validation and verification
- Token introspection and revocation
- Audit logging

✅ **Enterprise Features**
- Session management with timeout controls
- Token refresh handling
- Multi-platform support (iOS, Android, Web, Desktop)
- Comprehensive error handling

✅ **Developer Experience**
- Type-safe API
- Extensive documentation
- Working examples for all launch types

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  fhir_auth: ^0.15.0
```

### Basic Standalone Launch

```dart
import 'package:fhir_auth/fhir_auth.dart';

// 1. Configure your client
final client = SmartFhirClient(
  config: SmartConfig(
    clientId: 'your-client-id',
    fhirBaseUrl: 'https://fhir.example.com/r4'.toFhirUri,
    redirectUri: Uri.parse('com.yourapp://callback'),
    scopes: ['patient/*.read', 'launch/patient'],
  ),
);

// 2. Authenticate (launches the SMART authorization flow)
await client.login();

// 3. SmartFhirClient is an authenticated http.Client. Use it directly,
//    or hand it to fhir_r4_at_rest to build typed FHIR requests:
//    FhirReadRequest(..., client: client).sendRequest();
```

### EHR Launch

```dart
// Parse launch parameters from your URL
final params = Uri.base.queryParameters;

final client = SmartFhirClient(
  config: SmartConfig(
    clientId: params['clientId']!,
    fhirBaseUrl: Uri.parse(params['iss']!),
    redirectUri: Uri.parse('https://your-app.com/callback'),
    launchType: LaunchType.ehr,
    launchToken: params['launch'],
    scopes: ['patient/*.read'], // an EHR launch adds the `launch` scope
  ),
);

await client.login();
```

### EHR Launch Inside the EHR Window (web)

`login()` on the web opens the authorization page in a new window. An app
embedded in the EHR (Epic shows SMART apps in an iframe in the patient chart)
must stay in its own frame, so it logs in with a same-window redirect in two
halves:

```dart
final window = currentBrowserWindow();

// Launch page (the EHR opened it with ?iss=...&launch=...):
final url = await SmartFhirClient(config: config).beginRedirectLogin(
  store: window.sessionStorage,
);
window.assign(url); // the page unloads

// Redirect-URI page, on every load (first arrival and any reload):
final client = await SmartFhirClient.completeRedirectLogin(
  callbackUrl: window.location,
  store: window.sessionStorage,
);
window.replaceUrl(
  SmartFhirClient.redirectCallbackUrlToKeep(window.location),
);
final patientId = (await client.getStoredTokens())?.patientContext;
```

The login's `state` names the tab and stays in the address, and each tab's
tokens are stored under it, so two chart tabs open on two patients never share
tokens (Epic's "Embedding in Multiple Tabs" guidance: its browser does not keep
session storage apart per tab). Only public clients are allowed. A `state`
this browser session did not start, or one older than ten minutes, is refused,
and a code is exchanged once.

`example/ehr_redirect_launch` is a runnable web app built on these two calls.
On 2026-11-19 it signed in to Epic's public sandbox (standalone launch,
clinician user `FHIRTWO`) with PKCE S256 and an OpenID nonce, got a patient in
context, and read that `Patient`.

## Common Use Cases

### Token Refresh

Tokens are automatically refreshed before expiry:

```dart
// Manual refresh if needed
await client.refreshToken();
```

### Token Revocation

```dart
// Logout and revoke tokens
await client.logout();

// Or revoke specific tokens
await client.revokeAccessToken();
```

### Session Management

```dart
final client = SmartFhirClient(
  config: config,
  sessionManager: SessionManager(
    config: SessionConfig(
      idleTimeout: Duration(minutes: 15),
      absoluteTimeout: Duration(hours: 8),
    ),
  ),
);

// Listen for timeout warnings
client.onSessionTimeoutWarning?.listen((remaining) {
  print('Session expires in ${remaining.inMinutes} minutes');
});

// Listen for session expiry
client.onSessionTimeout?.listen((reason) {
  print('Session ended: $reason');
});

// Record user activity to prevent idle timeout
await client.recordActivity();
```

### Audit Logging

```dart
// Events are recorded to an in-memory store by default
final auditLogger = AuditLogger();

final client = SmartFhirClient(
  config: config,
  auditLogger: auditLogger,
);

// Inspect recorded events at any time
final events = await auditLogger.queryEvents();
for (final event in events) {
  print('Audit: ${event.eventType.name}');
}
```

### Secure Token Storage

```dart
// Tokens are automatically stored securely
// On mobile: Keychain (iOS) / KeyStore (Android)
// On web: Encrypted localStorage

// Custom storage
final client = SmartFhirClient(
  config: config,
  tokenStorage: CustomTokenStorage(),
);
```

## Platform-Specific Setup

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.yourapp</string>
    </array>
  </dict>
</array>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity">
  <intent-filter android:label="flutter_web_auth_2">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.yourapp" />
  </intent-filter>
</activity>
```

### Web

Create `web/redirect.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Authentication Redirect</title></head>
<body>
<script>
  window.opener.postMessage(window.location.href, '*');
</script>
</body>
</html>
```

## Supported FHIR Servers

Tested and working with:

- ✅ Epic (Sandbox & Production)
- ✅ Cerner (Sandbox & Production)
- ✅ SMART Health IT Sandbox
- ✅ HAPI FHIR Server
- ✅ Google Cloud Healthcare API
- ✅ Microsoft Azure API for FHIR
- ✅ AWS HealthLake

## Documentation

- 📚 [Full Documentation](https://www.fhirfli.dev/docs/auth)
- 🎯 [API Reference](https://pub.dev/documentation/fhir_auth/latest/)
- 💡 [Examples](https://github.com/fhir-fli/fhir_auth/tree/main/packages/fhir_auth/example)
- 🔧 [Migration Guide](https://www.fhirfli.dev/docs/auth/migration)

## Examples

Check out the [example](example/) directory for complete working applications:

- `example/standalone_launch.dart` - Patient-facing app
- `example/ehr_launch.dart` - Embedded in EHR
- `example/backend_services.dart` - Server-to-server
- `example/advanced_features.dart` - Session management, audit logging

## Troubleshooting

### Common Issues

**"No OAuth configuration found"**
- Ensure your FHIR server's CapabilityStatement includes SMART extensions
- Check that `/metadata` endpoint is accessible

**"PKCE verification failed"**
- Some servers don't support PKCE yet - disable with `enablePkce: false`
- This is NOT recommended for production

**Token refresh fails**
- Ensure you requested `offline_access` scope
- Check that your server supports refresh tokens

**Web redirect doesn't work**
- Verify `redirect.html` exists in `web/` directory
- Check redirect URI is registered with FHIR server
- Ensure redirect URI matches exactly (including trailing slash)

See the [full troubleshooting guide](https://www.fhirfli.dev/docs/auth/troubleshooting) for more help.

## Contributing

Contributions welcome: open an issue or a pull request at https://github.com/fhir-fli/fhir_auth.

## Testing

```bash
# This package (the Flutter parts)
flutter test

# fhir_auth_core (everything else), plain Dart
cd ../fhir_auth_core && dart test && dart test --platform chrome test/web
```

## License

BSD-3-Clause License - see [LICENSE](LICENSE) file for details.

## Support

- 🐛 [Report Issues](https://github.com/fhir-fli/fhir_auth/issues)
- 📧 [Email Support](mailto:support@fhirfli.dev)

## Acknowledgments

Built with ❤️ by the [FHIRfli](https://www.fhirfli.dev) team.

Implements [SMART App Launch](https://hl7.org/fhir/smart-app-launch/) specification from HL7.