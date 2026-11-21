/// What the pure-Dart client does with the two choices that need a
/// platform: the sign-in window and where tokens are kept. fhir_auth_core
/// makes neither; the Flutter package fhir_auth makes both.
library;

import 'dart:convert';

import 'package:fhir_auth_core/fhir_auth_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../test_helpers/untouched_token_storage.dart';

final Uri _fhir = Uri.parse('https://ehr.example.org/api/FHIR/R4');

SmartConfig _config() => SmartConfig(
  fhirBaseUrl: _fhir,
  clientId: 'c',
  redirectUri: Uri.parse('https://app.example.org/callback.html'),
  authorizeUrl: Uri.parse('https://ehr.example.org/oauth2/authorize'),
  tokenUrl: Uri.parse('https://ehr.example.org/oauth2/token'),
);

/// A client subclass, standing in for fhir_auth's.
class _OwnClient extends SmartFhirClient {
  _OwnClient({
    required super.config,
    required super.tokenStorage,
    super.httpClient,
    super.auditLogger,
    super.sessionManager,
    super.logger,
  });
}

void main() {
  test('login with no authenticator is refused before any request', () async {
    var requests = 0;
    final client = SmartFhirClient(
      config: _config(),
      tokenStorage: UntouchedTokenStorage(),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.login(),
      throwsA(
        isA<ConfigurationException>().having(
          (e) => e.configurationField,
          'configurationField',
          'authenticator',
        ),
      ),
    );
    expect(requests, 0);
    client.close();
  });

  test('a backend-services login needs no authenticator', () async {
    final client = SmartFhirClient(
      config: BackendServiceConfig(
        fhirBaseUrl: _fhir,
        clientId: 'svc',
        tokenUrl: Uri.parse('https://ehr.example.org/oauth2/token'),
        // Not a key: the login fails on it, after the authenticator check.
        privateKey: 'not a key',
      ),
      tokenStorage: UntouchedTokenStorage(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      client.login(),
      throwsA(
        isA<FhirAuthException>().having(
          (e) =>
              e is ConfigurationException &&
              e.configurationField == 'authenticator',
          'refused for want of an authenticator',
          isFalse,
        ),
      ),
    );
    client.close();
  });

  test(
    'completeRedirectLogin returns the client createClient builds',
    () async {
      // A tab whose login already finished, as after a page reload: the
      // record has no pending secrets and the tab's tokens are stored.
      final store = MemoryKeyValueStore();
      const state = 'tab-1';
      store.write(
        SmartFhirClient.redirectTabKey(state),
        jsonEncode(RedirectTabRecord(config: _config()).toJson()),
      );
      await TabTokenStorage(store: store, tabKey: state).saveTokens(
        SmartTokenResponse(accessToken: 'a', expiresIn: 3600),
      );

      final client = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: Uri.parse(
          'https://app.example.org/callback.html?state=$state',
        ),
        store: store,
        createClient: _OwnClient.new,
      );
      expect(client, isA<_OwnClient>());
      expect(client.tokenStorage, isA<TabTokenStorage>());
      client.close();
    },
  );
}
