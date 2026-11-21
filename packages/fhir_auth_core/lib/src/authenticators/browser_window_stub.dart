/// `currentBrowserWindow()` where there is no browser.
library;

import 'package:fhir_auth_core/fhir_auth_core.dart' show BrowserWindow;

/// The window the app runs in. Throws [UnsupportedError] here: this build is
/// not for the web, so there is no browser window.
BrowserWindow currentBrowserWindow() =>
    throw UnsupportedError(
      'currentBrowserWindow() needs a web build; this build has no browser',
    );
