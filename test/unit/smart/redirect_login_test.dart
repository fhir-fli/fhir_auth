/// Same-window SMART login (`beginRedirectLogin` / `completeRedirectLogin`):
/// the login an app embedded in an EHR chart tab needs, where a popup or a
/// new browser tab is not allowed.
///
/// Sources the assertions come from:
/// - SMART App Launch STU2.2, app-launch.html (read 2026-11-19): the app
///   "SHALL validate the value of the state parameter upon return to the
///   redirect URL"; the token request carries "The same redirect_uri used in
///   the initial authorization request"; "If the app was launched from an
///   EHR, the app adds a `launch` scope and a `launch={launch id}` URL
///   parameter".
/// - RFC 7636 section 4.2 and 4.5: code_challenge = BASE64URL(SHA256(
///   code_verifier)); the token request sends the code_verifier.
/// - RFC 6749 section 4.1.2: "The client MUST NOT use the authorization
///   code more than once."
/// - Epic, "Embedding in Multiple Tabs" (fhir.epic.com/Documentation, read
///   2026-11-19): Hyperspace can show several patients at once and does not
///   keep session storage apart per tab; tab data is keyed by a tab id.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhir_auth/fhir_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final Uri _authorize = Uri.parse('https://ehr.example.org/oauth2/authorize');
final Uri _token = Uri.parse('https://ehr.example.org/oauth2/token');
final Uri _fhir = Uri.parse('https://ehr.example.org/api/FHIR/R4');
final Uri _redirect = Uri.parse('https://app.example.org/callback.html');

/// The configuration an EHR launch produces: `iss` and `launch` from the
/// launch URL, endpoints already known (Epic publishes them).
SmartConfig _ehrLaunch({String launch = 'launch-abc', String? secret}) =>
    SmartConfig(
      fhirBaseUrl: _fhir,
      clientId: 'cicada-client',
      redirectUri: _redirect,
      scopes: const ['patient/Immunization.read'],
      clientSecret: secret,
      authMethod:
          secret == null
              ? ClientAuthMethod.none
              : ClientAuthMethod.clientSecretBasic,
      launchType: LaunchType.ehr,
      launchToken: launch,
      iss: _fhir.toString(),
      authorizeUrl: _authorize,
      tokenUrl: _token,
    );

/// A token endpoint that records every request and answers with an access
/// token for [patientFor] the code it was given.
class _TokenEndpoint {
  _TokenEndpoint({this.status = 200});

  final int status;
  final List<Map<String, String>> requests = [];

  /// The patient each authorization code was issued for.
  final Map<String, String> patientFor = {};

  late final http.Client client = MockClient((request) async {
    expect(request.url, _token);
    final body = Uri.splitQueryString(request.body);
    requests.add(body);
    if (status != 200) {
      return http.Response(
        jsonEncode({'error': 'invalid_grant'}),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'access_token': 'token-for-${body['code']}',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'launch patient/Immunization.read',
        'patient': patientFor[body['code']] ?? 'unknown',
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

/// RFC 7636 section 4.2, S256, computed here rather than with the package's
/// own PkceManager so the test does not trust the code under test.
String _s256(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll(
      '=',
      '',
    );

void main() {
  group('beginRedirectLogin', () {
    test('returns the authorization URL and keeps its secrets under the '
        'state', () async {
      final store = MemoryKeyValueStore();
      final client = SmartFhirClient(config: _ehrLaunch());

      final url = await client.beginRedirectLogin(store: store);
      final q = url.queryParameters;

      expect(url.replace(query: '').toString(), '$_authorize?');
      expect(q['response_type'], 'code');
      expect(q['client_id'], 'cicada-client');
      expect(q['redirect_uri'], _redirect.toString());
      expect(q['launch'], 'launch-abc');
      expect(q['aud'], _fhir.toString());
      expect(q['scope']!.split(' '), contains('launch'));
      expect(q['code_challenge_method'], 'S256');

      final state = q['state']!;
      final saved = store.read(SmartFhirClient.redirectTabKey(state));
      expect(saved, isNotNull);
      final record = RedirectTabRecord.fromJson(
        jsonDecode(saved!) as Map<String, dynamic>,
      );
      expect(_s256(record.pending!.codeVerifier!), q['code_challenge']);
      expect(record.pending!.nonce, q['nonce']);
      expect(record.config.tokenUrl, _token);
    });

    test('refuses a client with a secret, which a browser cannot keep', () {
      final client = SmartFhirClient(config: _ehrLaunch(secret: 's3cret'));
      expect(
        () => client.beginRedirectLogin(store: MemoryKeyValueStore()),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });

  group('completeRedirectLogin', () {
    test('exchanges the code with the saved verifier and the same '
        'redirect_uri, and stores the tokens for this tab', () async {
      final store = MemoryKeyValueStore();
      final url = await SmartFhirClient(
        config: _ehrLaunch(),
      ).beginRedirectLogin(store: store);
      final state = url.queryParameters['state']!;
      final endpoint = _TokenEndpoint()..patientFor['code-1'] = 'patient-A';

      final client = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: _redirect.replace(
          queryParameters: {'code': 'code-1', 'state': state},
        ),
        store: store,
        httpClient: endpoint.client,
      );

      expect(endpoint.requests, hasLength(1));
      final sent = endpoint.requests.single;
      expect(sent['grant_type'], 'authorization_code');
      expect(sent['code'], 'code-1');
      expect(sent['redirect_uri'], _redirect.toString());
      expect(sent['client_id'], 'cicada-client');
      expect(
        _s256(sent['code_verifier']!),
        url.queryParameters['code_challenge'],
      );

      expect(await client.getAccessToken(), 'token-for-code-1');
      final stored =
          await TabTokenStorage(
            store: store,
            tabKey: state,
          ).loadTokens();
      expect(stored!.patientContext, 'patient-A');

      // The secrets are gone; only the tab's configuration remains.
      final record = RedirectTabRecord.fromJson(
        jsonDecode(store.read(SmartFhirClient.redirectTabKey(state))!)
            as Map<String, dynamic>,
      );
      expect(record.pending, isNull);
    });

    test('two tabs on two patients keep their own tokens', () async {
      final store = MemoryKeyValueStore();
      final urlA = await SmartFhirClient(
        config: _ehrLaunch(launch: 'launch-A'),
      ).beginRedirectLogin(store: store);
      final urlB = await SmartFhirClient(
        config: _ehrLaunch(launch: 'launch-B'),
      ).beginRedirectLogin(store: store);
      final stateA = urlA.queryParameters['state']!;
      final stateB = urlB.queryParameters['state']!;
      expect(stateA, isNot(stateB));

      final endpoint =
          _TokenEndpoint()
            ..patientFor['code-A'] = 'patient-A'
            ..patientFor['code-B'] = 'patient-B';

      // Tab B comes back first; the order must not matter.
      final clientB = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: _redirect.replace(
          queryParameters: {'code': 'code-B', 'state': stateB},
        ),
        store: store,
        httpClient: endpoint.client,
      );
      final clientA = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: _redirect.replace(
          queryParameters: {'code': 'code-A', 'state': stateA},
        ),
        store: store,
        httpClient: endpoint.client,
      );

      expect((await clientA.getStoredTokens())!.patientContext, 'patient-A');
      expect((await clientB.getStoredTokens())!.patientContext, 'patient-B');

      // Each verifier went with its own code.
      final byCode = {for (final r in endpoint.requests) r['code']: r};
      expect(
        _s256(byCode['code-A']!['code_verifier']!),
        urlA.queryParameters['code_challenge'],
      );
      expect(
        _s256(byCode['code-B']!['code_verifier']!),
        urlB.queryParameters['code_challenge'],
      );

      // A reload of tab A finds patient A, not the last login.
      final reloadA = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: _redirect.replace(queryParameters: {'state': stateA}),
        store: store,
        httpClient: endpoint.client,
      );
      expect((await reloadA.getStoredTokens())!.patientContext, 'patient-A');
      expect(endpoint.requests, hasLength(2));
    });

    test('a code is exchanged once: the same callback again is a reload, '
        'with no second token request', () async {
      final store = MemoryKeyValueStore();
      final url = await SmartFhirClient(
        config: _ehrLaunch(),
      ).beginRedirectLogin(store: store);
      final callback = _redirect.replace(
        queryParameters: {
          'code': 'code-1',
          'state': url.queryParameters['state'],
        },
      );
      final endpoint = _TokenEndpoint()..patientFor['code-1'] = 'patient-A';

      await SmartFhirClient.completeRedirectLogin(
        callbackUrl: callback,
        store: store,
        httpClient: endpoint.client,
      );
      final again = await SmartFhirClient.completeRedirectLogin(
        callbackUrl: callback,
        store: store,
        httpClient: endpoint.client,
      );

      expect(endpoint.requests, hasLength(1));
      expect(await again.getAccessToken(), 'token-for-code-1');
    });

    test('a state this browser session did not start is refused, with no '
        'token request', () async {
      final endpoint = _TokenEndpoint();
      await expectLater(
        SmartFhirClient.completeRedirectLogin(
          callbackUrl: _redirect.replace(
            queryParameters: {'code': 'code-1', 'state': 'forged'},
          ),
          store: MemoryKeyValueStore(),
          httpClient: endpoint.client,
        ),
        throwsA(
          isA<SecurityException>().having(
            (e) => e.securityViolationType,
            'type',
            SecurityViolationType.stateMismatch,
          ),
        ),
      );
      expect(endpoint.requests, isEmpty);
    });

    test('a callback with no state is refused', () async {
      await expectLater(
        SmartFhirClient.completeRedirectLogin(
          callbackUrl: _redirect.replace(queryParameters: {'code': 'code-1'}),
          store: MemoryKeyValueStore(),
        ),
        throwsA(isA<SecurityException>()),
      );
    });

    test(
      'a login older than the allowed time is refused and forgotten',
      () async {
        final store = MemoryKeyValueStore();
        final start = DateTime.utc(2026, 11, 19, 12);
        final url = await SmartFhirClient(
          config: _ehrLaunch(),
        ).beginRedirectLogin(store: store, now: () => start);
        final state = url.queryParameters['state']!;
        final endpoint = _TokenEndpoint();

        await expectLater(
          SmartFhirClient.completeRedirectLogin(
            callbackUrl: _redirect.replace(
              queryParameters: {'code': 'code-1', 'state': state},
            ),
            store: store,
            httpClient: endpoint.client,
            now:
                () => start.add(
                  SmartFhirClient.redirectLoginLifetime +
                      const Duration(seconds: 1),
                ),
          ),
          throwsA(isA<SecurityException>()),
        );
        expect(endpoint.requests, isEmpty);
        expect(store.read(SmartFhirClient.redirectTabKey(state)), isNull);
      },
    );

    test('a login just inside the allowed time completes', () async {
      final store = MemoryKeyValueStore();
      final start = DateTime.utc(2026, 11, 19, 12);
      final url = await SmartFhirClient(
        config: _ehrLaunch(),
      ).beginRedirectLogin(store: store, now: () => start);
      final endpoint = _TokenEndpoint();

      await SmartFhirClient.completeRedirectLogin(
        callbackUrl: _redirect.replace(
          queryParameters: {
            'code': 'code-1',
            'state': url.queryParameters['state'],
          },
        ),
        store: store,
        httpClient: endpoint.client,
        now: () => start.add(SmartFhirClient.redirectLoginLifetime),
      );
      expect(endpoint.requests, hasLength(1));
    });

    test('an error from the authorization server is reported and the login '
        'forgotten', () async {
      final store = MemoryKeyValueStore();
      final url = await SmartFhirClient(
        config: _ehrLaunch(),
      ).beginRedirectLogin(store: store);
      final state = url.queryParameters['state']!;

      await expectLater(
        SmartFhirClient.completeRedirectLogin(
          callbackUrl: _redirect.replace(
            queryParameters: {'error': 'access_denied', 'state': state},
          ),
          store: store,
          httpClient: _TokenEndpoint().client,
        ),
        throwsA(
          isA<AuthorizationException>().having(
            (e) => e.errorCode,
            'errorCode',
            'access_denied',
          ),
        ),
      );
      expect(store.read(SmartFhirClient.redirectTabKey(state)), isNull);
    });

    test('a refused token request forgets the login, so the code cannot be '
        'tried again', () async {
      final store = MemoryKeyValueStore();
      final url = await SmartFhirClient(
        config: _ehrLaunch(),
      ).beginRedirectLogin(store: store);
      final callback = _redirect.replace(
        queryParameters: {
          'code': 'code-1',
          'state': url.queryParameters['state'],
        },
      );

      await expectLater(
        SmartFhirClient.completeRedirectLogin(
          callbackUrl: callback,
          store: store,
          httpClient: _TokenEndpoint(status: 400).client,
        ),
        throwsA(isA<AuthorizationException>()),
      );
      final endpoint = _TokenEndpoint();
      await expectLater(
        SmartFhirClient.completeRedirectLogin(
          callbackUrl: callback,
          store: store,
          httpClient: endpoint.client,
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(endpoint.requests, isEmpty);
    });
  });

  test('redirectCallbackUrlToKeep drops the code and keeps the state', () {
    final kept = SmartFhirClient.redirectCallbackUrlToKeep(
      Uri.parse('https://app.example.org/callback.html?code=c&state=s'),
    );
    expect(kept.toString(), 'https://app.example.org/callback.html?state=s');
  });

  group('scopes', () {
    test('an EHR launch asks for the launch scope', () {
      expect(_ehrLaunch().buildScopes(), contains('launch'));
    });

    test('a standalone launch asks for launch/patient, not launch', () {
      final scopes =
          SmartConfig(
            fhirBaseUrl: _fhir,
            clientId: 'c',
            redirectUri: _redirect,
          ).buildScopes();
      expect(scopes, contains('launch/patient'));
      expect(scopes, isNot(contains('launch')));
    });
  });

  test('PkceManager.restore refuses a string that is not a code verifier', () {
    expect(() => PkceManager().restore('too-short'), throwsArgumentError);
  });

  test('TabTokenStorage keeps two tabs apart in one store', () async {
    final store = MemoryKeyValueStore();
    final a = TabTokenStorage(store: store, tabKey: 'A');
    final b = TabTokenStorage(store: store, tabKey: 'B');
    await a.saveTokens(
      SmartTokenResponse(accessToken: 'a'),
    );
    expect(await b.loadTokens(), isNull);
    expect((await a.loadTokens())!.accessToken, 'a');
    await b.clearTokens();
    expect(await a.hasTokens(), isTrue);
  });
}
