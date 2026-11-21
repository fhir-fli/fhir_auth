# fhir_auth_core

## [0.15.0]

- First release. The pure-Dart part of `fhir_auth` 0.14.0, moved out so it
  can be used without Flutter (a plain Dart web page, a server, a
  command-line tool): SMART discovery, OAuth 2.0 with PKCE, ID-token checks,
  token refresh, introspection and revocation, backend services, sessions,
  audit logging, and the same-window browser login
  (`beginRedirectLogin` / `completeRedirectLogin`, `TabTokenStorage`,
  `currentBrowserWindow()`).
- Unlike `fhir_auth`, nothing that needs a platform is chosen for you:
  `FhirAuthClient` and `SmartFhirClient` take a `tokenStorage`, and
  `SmartFhirClient.login()` for a user login needs an `authenticator`
  (without one it throws `ConfigurationException` on
  `configurationField: 'authenticator'`, before any request).
- `SmartFhirClient.completeRedirectLogin` takes `createClient`, so a package
  that extends `SmartFhirClient` gets its own type back.
