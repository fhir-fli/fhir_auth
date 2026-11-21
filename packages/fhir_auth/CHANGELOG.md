# fhir_auth

## [0.15.0]

- Everything that needs no Flutter moved to a new pure-Dart package,
  `fhir_auth_core`. `fhir_auth` depends on it and exports all of it, and
  keeps only the Flutter parts: `WebAuthenticator` (flutter_web_auth_2),
  `MobileAuthenticator` (flutter_appauth), `SecureTokenStorage`
  (flutter_secure_storage), and a `SmartFhirClient` that uses
  `WebAuthenticator` and `SecureTokenStorage` when you name no others.
  Apps that import `package:fhir_auth/fhir_auth.dart` need no change,
  except:
- Breaking: a class that extends `FhirAuthClient` directly must pass
  `tokenStorage`; the base class no longer picks `SecureTokenStorage`.
  `SmartFhirClient` still does.
- Breaking: imports of `package:fhir_auth/src/...` for the moved files
  become `package:fhir_auth_core/src/...` (these paths were never public).
- Dependencies: `url_launcher` removed (nothing used it); `crypto`, `jose`,
  `uuid` and `web` now come through `fhir_auth_core`. Test-only:
  `fake_async` and `http_mock_adapter` removed (nothing used them).

## [0.14.0]

- Same-window SMART login for web apps embedded in an EHR, where a popup or
  new tab is not allowed: `SmartFhirClient.beginRedirectLogin` and
  `SmartFhirClient.completeRedirectLogin`. Each tab's login and tokens are
  kept in session storage under the login's `state`, which stays in the
  address as the tab's id (`TabTokenStorage`, `KeyValueStore`,
  `RedirectTabRecord`). `currentBrowserWindow()` gives the browser's address,
  navigation and session storage in a web build.
- An EHR launch now requests the `launch` scope, as SMART App Launch STU2.2
  requires ("the app adds a `launch` scope and a `launch={launch id}` URL
  parameter").
- `OAuthFlow.pendingSecrets` / `resumeAuthorization` and
  `PkceManager.restore` carry a login's state, nonce and code verifier
  across a page load.
- Breaking: `CustomWebAuthenticator` is removed. It was never implemented
  (`authenticate` always threw `UnimplementedError`), and nothing in the
  fhir-fli tree used it.
- New dependency: `web`.
- `example/ehr_redirect_launch`: a web app that signs in with the
  same-window login, from an EHR launch or a standalone launch.

## [0.13.0]

- Revived as the one authentication package for every FHIR version. The code
  is fhir_r4_auth 0.12.0's, which was byte-identical in fhir_r5_auth and
  fhir_r6_auth; those three become re-exports of this package.
- `AuthConfig.fhirBaseUrl` (and `AuthClient.fhirBaseUrl`) is a `Uri`, no
  longer a version-specific `FhirUri`. SMART endpoint discovery reads the
  CapabilityStatement as JSON.
- The Google sign-in of the 0.9.x line is not carried over; this package is
  SMART on FHIR (OAuth 2.0, PKCE, JWT, backend services).

## Carried from fhir_r4_auth

## [0.12.0]

- No code changes; version aligned with the fhir_r4 0.12.0 family release

## [0.9.0]

- No code changes; version aligned with the fhir_r4 0.9.0 family release

## [0.8.0]

- No code changes; version aligned with the fhir_r4 0.8.0 family release

## [0.7.3]

Robustness hardening (library code only; fhir_r4 core unchanged at ^0.7.0):

- All OAuth/OpenID Connect HTTP calls (token exchange, refresh, client-credentials grant, revocation, SMART discovery, JWKS fetch, token introspection) now enforce a 30-second network timeout (configurable via `networkTimeout`), so a hung or slow server can no longer block the auth flow indefinitely.
- `JwtValidator` now releases the HTTP client it owns via `dispose()`, and `OAuthFlow.dispose()` disposes the validator it created — fixing a socket leak on JWKS-verifying flows.
- Example updated to demonstrate the `allowedIssuers` allowlist for EHR launches.

## [0.7.2]

Second security hardening pass (library code only; fhir_r4 core unchanged at ^0.7.0):

- Fixed a broken concurrency guard where the "prevent concurrent refreshes" lock was permanently completed and did nothing — parallel refreshes are now coalesced into a single token exchange. This prevents refresh-token-rotation servers from rejecting a racing refresh and invalidating the token family.
- Refresh no longer discards the refresh token when the server omits it from a refresh response (RFC 6749 §6) — the existing refresh token is carried forward instead of being nulled out.
- TLS is now enforced on the SMART discovery documents (`.well-known/smart-configuration` and `/metadata`) and on the token introspection endpoint, closing the remaining plaintext paths (loopback still allowed; `allowInsecureConnections` opt-out).
- The bearer token is now origin-bound: it is attached only to requests whose scheme/host/port match the configured FHIR server, so it cannot leak to another host.
- `SmartConfig.fromLaunchParameters` accepts an `allowedIssuers` set and rejects an EHR-launch `iss` that is not allowlisted (mitigates SMART "iss spoofing" token theft).
- JWT verification enforces an algorithm allowlist (rejects `alg: none` and unknown algorithms) and rejects tokens carrying their own key material or key references (`jwk`/`jku`/`x5u`/`x5c`).
- Client-assertion JWTs (`createSignedJwt`) now use a random UUID `jti` instead of a timestamp.
- PKCE can no longer be disabled for a public SMART client.
- `at_hash`, nonce, and PKCE challenge comparisons now use a constant-time equality check.

## [0.7.1]

Security hardening of the SMART on FHIR auth flow (auth-only patch; fhir_r4 core unchanged at ^0.7.0):

- id_token validation now fails closed: `JwtValidator.validateToken` verifies the signature against the server's JWKS (discovered from `.well-known/smart-configuration`) and pins the expected issuer and audience (audience defaults to the client_id). When no key material is available it throws instead of silently decoding — pass `allowUnverified: true` (or use `decodeWithoutValidation`) for the previous behavior. `OAuthFlow` gained `jwksUri`/`expectedIssuer`/`expectedAudience`.
- Session timeout now purges the in-memory tokens: on idle/absolute timeout the client immediately stops attaching the bearer token (previously the timeout only cleared persistent storage, so the cached token kept being sent). New `FhirAuthClient.clearInMemoryTokens()`.
- HTTPS is now enforced on all OAuth/OpenID Connect endpoints (authorization, token, revocation, and JWKS). Non-HTTPS URLs throw `SecurityException`; loopback hosts remain allowed for local development, and `allowInsecureConnections` (on `AuthConfig`/`OAuthFlow`/`JwtValidator`) is an explicit opt-out.
- iOS keychain items now use `first_unlock_this_device`, keeping credentials on-device (excluded from iCloud Keychain sync and cross-device backup restore).
- `AuthConfig.toJson()` no longer serializes secrets (`clientSecret`, `BackendServiceConfig.privateKey`) by default — pass `includeSecrets: true` to persist them deliberately.
- jose remains ^0.3.5+2 (GHSA-vm9r-h74p-hg97 / CVE-2026-34240 patched)

## [0.7.0]

- Family release train: cores and companions released in lockstep at 0.7.0
- README: SMART App Launch link now https
- Tests: replaced a statistically unsound PKCE repeated-pattern test (CI flake)
- fhir_r4 ^0.7.0

## [0.6.0]

- flutter_appauth ^12.0.0 + flutter_web_auth_2 ^5.0.0 (verified live against the Epic sandbox: standalone patient+clinician on web, EHR launch on web, standalone on Linux desktop)
- Fixed desktop (Linux/Windows) sign-in being cancelled when the app window regained focus mid-login: the plugin's app-resume cleanup force-closed its local callback server; the authenticator now invokes the desktop platform implementation directly
- Security: jose bumped to ^0.3.5+2 (GHSA-vm9r-h74p-hg97 / CVE-2026-34240, JWS signature-verification bypass)
- Removed the unused dart_jsonwebtoken dependency
- Family lockstep 0.6.0; runnable example added; README rewritten and verified against the API (login/refreshToken); package-local lint relaxations removed, analyzer clean

## [0.5.1]

- Improved documentation and README files

## [0.5.0]

* Unified versioning across all fhir_r4 packages
* Initial publication to pub.dev
* SMART on FHIR authentication with standalone and EHR launch flows
* Fixed PKCE and OpenID flags not being passed through to OAuth flow
* Fixed competing Android intent filters with flutter_appauth
* Platform-specific auth support for web, Linux, and Android

## The 0.9.x–0.11.0-dev line

## [0.11.0-dev.1]

* Updated dependencies
* Broadened platform support
* Updated Readme

## [0.10.0]

* Updated dependencies

## [0.9.5]

* Updated dependencies
* Notably, google login is updated, which means there's now a CORS error if you login from a PWA

## [0.9.4]

* Updated dependencies
* Updated to Dart 2.19.0
* Updated to fhir 0.9.4

## [0.9.3]

* Just updated, doing it again
* Updated dependencies

## [0.9.2]

* Updated dependencies

## [0.9.1]

* Updated GcpFhirClient to have access to email & displayName

## [0.9.0]

* Cannot create resources and then find them in Epic. Can create them but due to a CORS issue canot get the location, and identifiers are stripped away upon creation. Ayone who figures this out, please let me know.
* Cerner patient launch works internally and externally
* NOTE: for some reason the Cerner launch does not accept the launch token for an internal launch being attached to the Authorization url - if you need this included, you'll have to adjust how the url is created

## [0.9.0-2]

* Successfully does external and internal web launches to Epic for patients and for users, although for Epic you do need to ensure that you include the proper launch parameters if you're doing a patient context
* Updated dependencies
* Internal launch for patients and users for Epic and Meld (HAPI)
* External launch for patients and users for Google, Meld (HAPI), and Epic
* Cannot read id (location) with resources created in Epic (CORS issue), so you may need to include an identifier

## [0.9.0-1]

* Successfully does external and internal web launches to Epic for patients
* For users, successfully logs in externally, doesn't return all needed headers

## [0.8.1]

* Added demos
    1. External Web demos - aidbox, google, hapi, meld, epic
    2. Internal EHR demos (all web) - meld & epic
    3. External Mobile demos - aidbox, google, hapi, meld
* Updated to new granular SMART scopes (not in use yet, usually)
* Added system, in addition to patient & user scopes
* Had to add new authorizationCodeGrant (extended from Oauth2) to save some of the passed FHIR values
* Added epic client class for values it may pass at launch

## [0.8.0]

* Updated Dependencies
* Fhir 0.8.0
* Flutter 3.0.0
* All Clients are now extensions of http.Client, so they can be passed to fhir_at_rest, and so all requests have been removed from fhir_auth for easier maintenance
* Moved All demos to demo folder
* Same client for each FHIR version, as the only difference for authentication is getting the endpoints
* For web, you will need to include a version of the redirect.html that is included in the lib directory

## [0.6.1]

* Updated dependencies
* Updated to fhir 0.6.1
* Imports sorted
* Added NonFhirClient
* Linting Changes
* ToDo: Fix overriding fields

## [0.6.0]

* Updated dependencies
* Updated to 0.6.0
* Cleaned up Demos to work for Google, MELD, and Aidbox
* Internal EHR Launch only works from MELD

## [0.5.0-10]

* Updated fhir version

## [0.5.0-9]

* Base FhirClient was still returning void from isLoggedIn (but should return a boolean)
* Let `.login()` immediately ask for a token
* Updated dependencies
* Dart 2.15.0

## [0.5.0-8]

* ClientId is optional for Google Mobile
* EHR Launch example without ClientID (passed as URL argument) to make it more flexible

## [0.5.0-7]

* Simplified ehrlaunchdemo to more closely mirror actual ehr launch workflow
* Added new clinical scopes to correspond to SMART on FHIR 2.0 (note that while these are an option for the enum Interaction, they're not supported yet - baby steps people)
* SMART Client now has getters for patientId and encounterId (as these are the two contexts that are sometimes passed with an EHR launch)
* They are fully supported in Web client NOT in mobile client (again, for now)

## [0.5.0-6]

* initialize() has been changed back to login()
* logout() has been added
* All restful calls now require a FhirClient
* Restful calls check if client is logged in, automatically logs in if not
* headers now optional as argument for request method in FhirRequest

## [0.5.0-5]

* Added EHR Launch Example
* Added ability to pass launch token
* Automatically checks launch token, if not null, includes token as a parameter and launch as a scope

## [0.5.0-4]

* Added example
* Ran formatter

## [0.5.0-3]

* Fairly big changes this time around
* Changed to use [oauth2_client](https://pub.dev/packages/oauth2_client) instead of [flutter_appauth](https://pub.dev/packages/flutter_appauth) because it gives me less issues with web (and I can use it for both the mobile client and the web client)
* Updated the readme with much longer instructions
* Authenticates against GCP, MELD, Interopland and Aidbox (haven't checked Azure with this new update)

## [0.4.1]

* Updated dependencies
* Trying to make it fully web and mobile compliant on pub.dev

## [0.4.0]

* Now works for mobile and web
* Still needs a better readme
* Now has authenticated against
    1. Google Healthcare API
    2. Azure API for FHIR
    3. HAPI
    4. Logica
    5. Aidbox
    6. MiHIN

## [0.3.0-nullsafety.8]

* Updating dependencies

## [0.3.0-nullsafety.7]

* So Close.
* Normal auth for mobile with no significant changes since last prerelease
* Web auth now available! This is a big change, mostly because I've added it. Should work very similarly to mobile auth though, and I've tried to generally keep the structure of the classes the same.
* authdemo is the example for mobile
* example is the example for web

## [0.3.0-nullsafety.6]

* Updated dependencies, all now null safe
* Still not stable release because I want to do more testing
* removed Dartz dependency

## [0.3.0-nullsafety.5]

* Fucking finally
* Static analysis can kiss my ass

## [0.3.0-nullsafety.4]

* Didn't like my Flutter SDK
* Passes all testing/reviews on my computer, but not on pub.dev

## [0.3.0-nullsafety.3]

* Keeps giving me shit about pub points

## [0.3.0-nullsafety.2]

* Updated SDK requirements

## [0.3.0-nullsafety.1]

* Trying to get more points
* Added documentation, need to pass static analysis, etc.

## [0.3.0-nullsafety.0]

* Null safety!
* Should be completely ready for null safety
* Same functionality as before, just a little stricter now

## [0.2.1]

* Updated dependencies
* Added documentation
* made it available on web (removed dart:io)

## [0.2.0]

* Updated dependencies
* Attempted to make GCS Client Similar to SmartClient
* Changed FhirClient to SmartClient
* FhirClient now superclass, extended with SmartClient & GcsClient
* Updated Readme, instructions for Hapi, Aidbox, Google and Azure

## [0.1.0]

* removed use of Dartz, throwing errors instead of failures, allow developer to decided how to handle exceptions
* simplified, removed some enums, removed types (since they're now in base package)

## [0.0.3]

* Refactoring failures to errors, will let developer decide how to handle

## [0.0.2]

* Updated failures

## [0.0.1]

* First release
* Allows the creation of a FhirClient using standard SMART on FHIR functionality
* Also allows Google Sign-in if users desire to use Google Healthcare API
