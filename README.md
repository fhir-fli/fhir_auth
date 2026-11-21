# fhir_auth

SMART on FHIR authentication for Dart and Flutter, in two packages:

| Package | What it is |
|---|---|
| [`packages/fhir_auth_core`](packages/fhir_auth_core) | Pure Dart: discovery, OAuth 2.0 + PKCE, ID-token checks, backend services, same-window browser login. No Flutter. |
| [`packages/fhir_auth`](packages/fhir_auth) | Flutter: exports all of `fhir_auth_core` and adds pop-up and phone sign-in and Keychain/Keystore token storage. |

`fhir_r4_auth`, `fhir_r5_auth` and `fhir_r6_auth` re-export `fhir_auth`.
