/// The web `currentBrowserWindow()`, run in a real browser:
/// `flutter test --platform chrome test/web`.
@TestOn('browser')
library;

import 'package:fhir_auth/fhir_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final window = currentBrowserWindow();

  test('sessionStorage reads back what it was given and forgets on remove', () {
    final store = window.sessionStorage;
    const key = 'fhir_auth.test.browser_window';
    expect(store.read(key), isNull);
    store.write(key, 'value');
    expect(store.read(key), 'value');
    store.remove(key);
    expect(store.read(key), isNull);
  });

  test('replaceUrl changes the address without leaving the page', () {
    final before = window.location;
    final changed = before.replace(queryParameters: {'state': 'tab-1'});
    window.replaceUrl(changed);
    expect(window.location, changed);
    expect(
      SmartFhirClient.redirectCallbackUrlToKeep(
        before.replace(queryParameters: {'code': 'c', 'state': 'tab-1'}),
      ),
      changed,
    );
    window.replaceUrl(before);
    expect(window.location, before);
  });
}
