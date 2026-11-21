/// fhir_auth's client makes the two choices fhir_auth_core leaves to the
/// caller, so a Flutter app written for fhir_auth 0.14 runs unchanged.
library;

import 'dart:convert';

import 'package:fhir_auth/fhir_auth.dart';
import 'package:fhir_auth_core/fhir_auth_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

SmartConfig _config() => SmartConfig(
  fhirBaseUrl: Uri.parse('https://ehr.example.org/api/FHIR/R4'),
  clientId: 'c',
  redirectUri: Uri.parse('https://app.example.org/callback.html'),
  authorizeUrl: Uri.parse('https://ehr.example.org/oauth2/authorize'),
  tokenUrl: Uri.parse('https://ehr.example.org/oauth2/token'),
);

void main() {
  test('with no storage named, tokens go to SecureTokenStorage', () {
    final client = SmartFhirClient(config: _config());
    expect(client.tokenStorage, isA<SecureTokenStorage>());
    client.close();
  });

  test('a storage that is named is used', () {
    final storage = TabTokenStorage(store: MemoryKeyValueStore(), tabKey: 't');
    final client = SmartFhirClient(config: _config(), tokenStorage: storage);
    expect(client.tokenStorage, same(storage));
    client.close();
  });

  test("completeRedirectLogin returns this package's client", () async {
    // A tab whose login already finished, as after a page reload.
    final store = MemoryKeyValueStore();
    const state = 'tab-1';
    store.write(
      SmartFhirClient.redirectTabKey(state),
      jsonEncode(RedirectTabRecord(config: _config()).toJson()),
    );
    await TabTokenStorage(
      store: store,
      tabKey: state,
    ).saveTokens(SmartTokenResponse(accessToken: 'a', expiresIn: 3600));

    final client = await SmartFhirClient.completeRedirectLogin(
      callbackUrl: Uri.parse(
        'https://app.example.org/callback.html?state=$state',
      ),
      store: store,
    );
    expect(client, isA<SmartFhirClient>());
    expect(client.tokenStorage, isA<TabTokenStorage>());
    client.close();
  });

  test("the forwarded statics are the core's", () {
    expect(
      SmartFhirClient.redirectLoginLifetime,
      core.SmartFhirClient.redirectLoginLifetime,
    );
    expect(
      SmartFhirClient.redirectTabKey('x'),
      core.SmartFhirClient.redirectTabKey('x'),
    );
    final url = Uri.parse('https://app.example.org/cb?code=c&state=s');
    expect(
      SmartFhirClient.redirectCallbackUrlToKeep(url),
      core.SmartFhirClient.redirectCallbackUrlToKeep(url),
    );
  });
}
