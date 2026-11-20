// A SMART app that signs in without leaving its own window, the way an app
// shown inside an EHR's patient chart must.
//
// Serve the web build at http://localhost:8080 and register
// http://localhost:8080/callback.html as the app's redirect URI.
//
//   EHR launch:        http://localhost:8080/?iss=...&launch=...
//   Standalone launch: http://localhost:8080/?standalone=1
//
// Add `openid=0` to the launch address to sign in without OpenID Connect.
// Every step is printed to the browser console with a `DEMO:` prefix.
import 'dart:async';
import 'dart:convert';

import 'package:fhir_auth/fhir_auth.dart';
import 'package:flutter/material.dart';

/// The app's client ID, from `--dart-define=CLIENT_ID=...`.
const String clientId = String.fromEnvironment('CLIENT_ID');

/// The FHIR servers this app will sign in to. A launch naming any other
/// server is refused: the launch address can be forged.
const Set<String> allowedIssuers = {
  'https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4',
};

void main() => runApp(const MaterialApp(home: LaunchPage()));

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  final List<String> _lines = <String>[];

  void _say(String line) {
    // The console line is what an automated run reads.
    // ignore: avoid_print
    print('DEMO: $line');
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final window = currentBrowserWindow();
    final here = window.location;
    final query = here.queryParameters;
    try {
      if (query.containsKey(OAuthParameters.state)) {
        await _finish(window);
      } else if (query.containsKey('iss') || query['standalone'] == '1') {
        await _begin(window, here);
      } else {
        _say('Open with ?iss=...&launch=... or ?standalone=1');
      }
    } on Object catch (e) {
      _say('FAILED: $e');
    }
  }

  Future<void> _begin(BrowserWindow window, Uri here) async {
    final query = here.queryParameters;
    final iss = query['iss'] ?? allowedIssuers.first;
    if (!allowedIssuers.contains(iss)) {
      _say('FAILED: refusing launch from untrusted iss $iss');
      return;
    }
    final launch = query['launch'];
    final config = SmartConfig(
      fhirBaseUrl: Uri.parse(iss),
      clientId: clientId,
      redirectUri: Uri.parse('${here.origin}/callback.html'),
      launchType: launch == null ? LaunchType.standalone : LaunchType.ehr,
      launchToken: launch,
      iss: iss,
      audience: iss,
      enableOpenId: query['openid'] != '0',
    );
    _say('scopes: ${config.buildScopes().join(' ')}');
    final url = await SmartFhirClient(
      config: config,
    ).beginRedirectLogin(store: window.sessionStorage);
    _say('authorize: $url');
    window.assign(url);
  }

  Future<void> _finish(BrowserWindow window) async {
    final error = window.location.queryParameters['error'];
    if (error != null) {
      _say(
        'FAILED: server answered $error: '
        '${window.location.queryParameters['error_description']}',
      );
    }
    final client = await SmartFhirClient.completeRedirectLogin(
      callbackUrl: window.location,
      store: window.sessionStorage,
    );
    window.replaceUrl(
      SmartFhirClient.redirectCallbackUrlToKeep(window.location),
    );
    final tokens = await client.getStoredTokens();
    _say('signed in; scope: ${tokens?.scope}');
    _say('patient: ${tokens?.patientContext}');
    _say('fhirUser: ${tokens?.fhirUser}');
    _say('id_token present: ${tokens?.idToken != null}');

    final patientId = tokens?.patientContext;
    if (patientId == null) {
      _say('no patient in context; nothing to read');
      return;
    }
    final base = client.smartConfig!.fhirBaseUrl.toString();
    final response = await client.get(
      Uri.parse('$base/Patient/$patientId'),
      headers: const {'Accept': 'application/fhir+json'},
    );
    _say('GET Patient/$patientId: ${response.statusCode}');
    if (response.statusCode == 200) {
      final patient = jsonDecode(response.body) as Map<String, dynamic>;
      final names = patient['name'] as List<dynamic>? ?? const [];
      final first = names.isEmpty ? null : names.first as Map<String, dynamic>;
      _say('patient name: ${first?['text'] ?? first}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final line in _lines) SelectableText(line)],
    ),
  );
}
