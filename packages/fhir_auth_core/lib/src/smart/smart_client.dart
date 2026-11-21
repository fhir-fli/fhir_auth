/// SMART on FHIR client implementation
library;

import 'dart:async';
import 'dart:convert';
import 'package:fhir_auth_core/fhir_auth_core.dart'
    show
        AuditEvent,
        AuditEventType,
        AuditLogger,
        AuditSeverity,
        AuthConfig,
        AuthenticationException,
        Authenticator,
        BackendServiceConfig,
        ConfigurationException,
        FhirAuthClient,
        FhirAuthException,
        JwtValidator,
        KeyValueStore,
        NetworkException,
        OAuthFlow,
        OAuthParameters,
        PendingRedirectLogin,
        RedirectTabRecord,
        SecurityException,
        SecurityViolationType,
        Session,
        SessionManager,
        SmartCapability,
        SmartConfig,
        SmartTokenResponse,
        TabTokenStorage,
        TimeoutReason,
        TokenIntrospector,
        TokenStorage,
        assertSecureAuthUrl;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Builds the client that [SmartFhirClient.completeRedirectLogin] returns,
/// so a package that extends [SmartFhirClient] gets its own type back.
typedef SmartFhirClientFactory =
    SmartFhirClient Function({
      required AuthConfig config,
      required TokenStorage tokenStorage,
      http.Client? httpClient,
      AuditLogger? auditLogger,
      SessionManager? sessionManager,
      Logger? logger,
    });

/// SMART on FHIR client for OAuth authentication
class SmartFhirClient extends FhirAuthClient {
  /// Create a SMART on FHIR client from [config] that keeps its tokens in
  /// [tokenStorage], with an optional [authenticator], pre-built
  /// [oauthFlow], HTTP client, audit logger, and session manager.
  ///
  /// [authenticator] runs the sign-in window for [login]. This package has
  /// none: it is pure Dart, and a pop-up or a phone's system browser needs
  /// platform code (the Flutter package `fhir_auth` has `WebAuthenticator`
  /// and `MobileAuthenticator`). Without one, [login] works for backend
  /// services only; a browser app signs in with [beginRedirectLogin] and
  /// [completeRedirectLogin], which need no authenticator.
  SmartFhirClient({
    required super.config,
    required super.tokenStorage,
    Authenticator? authenticator,
    OAuthFlow? oauthFlow,
    http.Client? httpClient,
    AuditLogger? auditLogger,
    SessionManager? sessionManager,
    super.logger,
  }) : _authenticator = authenticator,
       _oauthFlow = oauthFlow,
       _httpClient = httpClient ?? http.Client(),
       _auditLogger = auditLogger,
       _sessionManager = sessionManager,
       _logger = logger ?? Logger('SmartFhirClient'),
       super(innerClient: httpClient) {
    // When the session times out (idle or absolute), purge the in-memory
    // tokens so the client immediately stops sending the bearer token. The
    // session manager clears persistent storage separately.
    final sm = _sessionManager;
    if (sm != null) {
      _timeoutSub = sm.onTimeout.listen((_) => clearInMemoryTokens());
    }
  }

  /// Get SMART configuration (null if using BackendServiceConfig)
  SmartConfig? get smartConfig =>
      config is SmartConfig ? config as SmartConfig : null;

  /// Get backend service configuration (null if using SmartConfig)
  BackendServiceConfig? get backendConfig =>
      config is BackendServiceConfig ? config as BackendServiceConfig : null;

  /// Whether this client is configured for backend service auth
  bool get isBackendService => config is BackendServiceConfig;

  final Authenticator? _authenticator;
  final http.Client _httpClient;
  final AuditLogger? _auditLogger;
  final SessionManager? _sessionManager;
  final Logger _logger;
  OAuthFlow? _oauthFlow;

  /// Maximum time to wait for a discovery-document fetch before failing.
  static const Duration _discoveryTimeout = Duration(seconds: 30);

  /// SMART capabilities from server
  List<SmartCapability>? _serverCapabilities;

  /// Discovered endpoints
  Uri? _revocationEndpoint;
  Uri? _introspectionEndpoint;

  /// Discovered JWKS URI (used to verify id_token signatures)
  Uri? _jwksUri;

  /// Discovered authorization-server issuer (expected id_token `iss`)
  String? _issuer;

  /// Subscription that purges in-memory tokens on session timeout
  StreamSubscription<TimeoutReason>? _timeoutSub;

  /// Token introspector (lazy initialized)
  TokenIntrospector? _tokenIntrospector;

  /// Cached smart token response for synchronous access
  SmartTokenResponse? _cachedSmartTokens;

  /// Stream of session timeout warnings
  Stream<Duration>? get onSessionTimeoutWarning =>
      _sessionManager?.onTimeoutWarning;

  /// Stream of session timeout events
  Stream<TimeoutReason>? get onSessionTimeout => _sessionManager?.onTimeout;

  /// Get current session
  Session? get currentSession => _sessionManager?.currentSession;

  /// Get OAuth flow (lazy initialization)
  Future<OAuthFlow> _getOAuthFlow() async {
    if (_oauthFlow != null) return _oauthFlow!;

    // Backend services: token URL is in config, no authorization endpoint
    if (isBackendService) {
      final bc = backendConfig!;
      _oauthFlow = OAuthFlow(
        clientId: bc.clientId,
        authorizationEndpoint: bc.tokenUrl, // Not used for backend services
        tokenEndpoint: bc.tokenUrl,
        redirectUri: bc.redirectUri,
        scopes: bc.scopes,
        enablePkce: false,
        enableOpenId: false,
        allowInsecureConnections: bc.allowInsecureConnections,
        httpClient: _httpClient,
      );
      return _oauthFlow!;
    }

    final sc = smartConfig!;

    // PKCE is mandatory for public clients in the SMART authorization code
    // flow; a public client must never be able to silently disable it.
    if (sc.isPublicClient && !sc.enablePkce) {
      throw const ConfigurationException(
        'PKCE is required for public SMART clients',
        configurationField: 'enablePkce',
      );
    }

    // Get endpoints if not configured
    var authEndpoint = sc.authorizeUrl;
    var tokenEndpoint = sc.tokenUrl;

    if (authEndpoint == null || tokenEndpoint == null) {
      final endpoints = await _discoverEndpoints();
      authEndpoint ??= endpoints['authorization_endpoint'] as Uri;
      tokenEndpoint ??= endpoints['token_endpoint'] as Uri;
    }

    _oauthFlow = OAuthFlow(
      clientId: sc.clientId,
      authorizationEndpoint: authEndpoint,
      tokenEndpoint: tokenEndpoint,
      redirectUri: sc.redirectUri,
      clientSecret: sc.clientSecret,
      scopes: sc.buildScopes(),
      additionalParameters: sc.buildAuthorizationParameters(),
      enablePkce: sc.enablePkce,
      enableOpenId: sc.enableOpenId,
      // Verify the id_token signature against the discovered JWKS, and pin the
      // expected issuer/audience. When JWKS discovery yielded nothing the
      // signature is skipped (code flow over TLS) but claims are still checked.
      jwksUri: _jwksUri?.toString(),
      expectedIssuer: _issuer,
      expectedAudience: sc.clientId,
      allowInsecureConnections: sc.allowInsecureConnections,
      httpClient: _httpClient,
    );

    return _oauthFlow!;
  }

  @override
  Future<void> login() async {
    final authenticator = _authenticator;
    if (authenticator == null && !isBackendService) {
      throw const ConfigurationException(
        'No authenticator to open the sign-in window',
        details:
            'Pass an Authenticator (the Flutter package fhir_auth has '
            'WebAuthenticator and MobileAuthenticator), or, in a browser, '
            'sign in with beginRedirectLogin and completeRedirectLogin',
        configurationField: 'authenticator',
      );
    }
    _logger.fine('Starting SMART login');

    // Audit: log authentication attempt
    await _auditLogger?.logAuthenticationAttempt(userId: 'unknown');

    try {
      // Backend service flow: JWT client assertion, no browser
      if (isBackendService) {
        await _performBackendServiceLogin();
        return;
      }

      final sc = smartConfig!;

      // Get OAuth flow
      final oauthFlow = await _getOAuthFlow();

      // Build authorization URL
      final authUrl = oauthFlow.buildAuthorizationUrl(
        extraParameters: sc.customParameters,
      );

      _logger.fine('Launching authorization URL');

      // Launch authentication
      final responseUrl = await authenticator!.authenticate(
        authorizationUrl: authUrl,
        redirectUri: sc.redirectUri,
        callbackUrlScheme: sc.redirectUri.scheme,
      );

      // Handle authorization response
      final tokens = await oauthFlow.handleAuthorizationResponse(
        responseUrl.queryParameters,
      );

      await _finishLogin(tokens);
    } on Object catch (e, stackTrace) {
      await _loginFailed(e, stackTrace);
    }
  }

  /// Store [tokens], start the session and audit the login.
  Future<void> _finishLogin(SmartTokenResponse tokens) async {
    // Store tokens and context
    await storeTokens(tokens);

    // Start session
    if (_sessionManager != null) {
      await _sessionManager.startSession(
        userId: tokens.fhirUser ?? 'unknown',
        metadata: <String, dynamic>{
          'scopes': tokens.scopesList,
          if (tokens.patientContext != null)
            'patient_context': tokens.patientContext,
          if (tokens.encounterContext != null)
            'encounter_context': tokens.encounterContext,
        },
      );
    }

    _logger.fine('SMART login successful');

    // Audit: log successful authentication
    await _auditLogger?.logAuthenticationSuccess(
      userId: tokens.fhirUser ?? 'unknown',
      details: <String, dynamic>{
        'scopes': tokens.scopesList,
        if (tokens.patientContext != null)
          'patient_context': tokens.patientContext,
        if (tokens.encounterContext != null)
          'encounter_context': tokens.encounterContext,
      },
    );

    // Audit: log token issued
    await _auditLogger?.logTokenIssued(
      userId: tokens.fhirUser,
      scopes: tokens.scopesList,
    );
  }

  /// Log and audit a failed login, then throw: [e] itself, with its stack
  /// trace, when it is one of [keep]; otherwise an [AuthenticationException]
  /// wrapping it. [login] keeps only [AuthenticationException]s.
  Future<Never> _loginFailed(
    Object e,
    StackTrace stackTrace, {
    bool Function(Object e) keep = _isAuthenticationException,
  }) async {
    _logger.severe('SMART login failed', e, stackTrace);

    // Audit: log authentication failure
    await _auditLogger?.logAuthenticationFailure(
      reason: e.toString(),
      errorCode:
          e is AuthenticationException
              ? 'authentication_failed'
              : 'unknown_error',
    );

    if (keep(e)) Error.throwWithStackTrace(e, stackTrace);

    throw AuthenticationException(
      'SMART authentication failed',
      details: e.toString(),
      innerException: e,
      stackTrace: stackTrace,
    );
  }

  /// How long a same-window login may take, from leaving for the
  /// authorization server to coming back. The same ten minutes
  /// [StateManager] gives a `state` by default.
  static const Duration redirectLoginLifetime = Duration(minutes: 10);

  /// Prefix of every same-window login record in session storage. Tokens
  /// live under a different prefix ([TabTokenStorage]), so no `state` can
  /// make a token entry read as a login record.
  static const String _redirectLoginPrefix = 'fhir_auth.login.';

  /// The session-storage key of the login record whose OAuth `state` is
  /// [tabKey].
  static String redirectTabKey(String tabKey) => '$_redirectLoginPrefix$tabKey';

  /// Remove the records of logins started more than [redirectLoginLifetime]
  /// ago that never came back (the user closed the tab at the sign-in page).
  /// Their secrets would otherwise stay in session storage, which Hyperspace
  /// shares across tabs, until the browser session ends. Finished logins
  /// hold no secrets and are kept: their tabs may still be open.
  static void _forgetAbandonedLogins(KeyValueStore store, DateTime now) {
    for (final key in store.keys.toList()) {
      if (!key.startsWith(_redirectLoginPrefix)) continue;
      final pending = _readRecord(store, key)?.pending;
      if (pending != null &&
          now.isAfter(pending.startedAt.add(redirectLoginLifetime))) {
        store.remove(key);
      }
    }
  }

  /// The login record stored under [key], or null when there is none or it
  /// cannot be read (an unreadable record is removed).
  static RedirectTabRecord? _readRecord(KeyValueStore store, String key) {
    final saved = store.read(key);
    if (saved == null) return null;
    try {
      return RedirectTabRecord.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } on Object {
      store.remove(key);
      return null;
    }
  }

  /// Start a same-window login: the first half of [login] for a web app
  /// that must not open a popup or a new tab, such as one embedded in an EHR
  /// (Epic Hyperspace shows apps in an iframe in the patient chart).
  ///
  /// Saves this login's `state`, `nonce` and PKCE code verifier in [store]
  /// (in a browser, `currentBrowserWindow().sessionStorage`) under a key made
  /// from the `state`, and returns the authorization URL. The caller then
  /// sends the window there (`currentBrowserWindow().assign(url)`); the
  /// page unloads. When the authorization server sends the browser back to
  /// the redirect URI, call [completeRedirectLogin] there.
  ///
  /// The `state` doubles as the tab's id. Epic's "Embedding in Multiple
  /// Tabs" (fhir.epic.com/Documentation, read 2026-11-19) asks for a tab id
  /// in the URL because Hyperspace shares session storage across tabs; the
  /// `state` comes back in the redirect URL and stays there. The SMART
  /// Health IT reference client does the same (fhirclient 2.5.4,
  /// lib/smart.js `ready()`: without `fullSessionStorageSupport` it "MUST
  /// keep the `state` url parameter").
  ///
  /// Only public clients: a browser app cannot keep a client secret, and
  /// the secret would otherwise have to wait in session storage.
  Future<Uri> beginRedirectLogin({
    required KeyValueStore store,
    DateTime Function() now = DateTime.now,
  }) async {
    final sc = smartConfig;
    if (sc == null) {
      throw const ConfigurationException(
        'A same-window login is for SMART user logins, not backend services',
        configurationField: 'config',
      );
    }
    if (!sc.isPublicClient || sc.clientSecret != null) {
      throw const ConfigurationException(
        'A same-window login is for public clients: a browser app cannot '
        'keep a client secret',
        configurationField: 'clientSecret',
      );
    }

    await _auditLogger?.logAuthenticationAttempt(userId: 'unknown');
    _forgetAbandonedLogins(store, now());

    final oauthFlow = await _getOAuthFlow();
    final authUrl = oauthFlow.buildAuthorizationUrl(
      extraParameters: sc.customParameters,
    );
    final secrets = oauthFlow.pendingSecrets;

    // The configuration as it will be needed on the way back: with the
    // endpoints discovery found, so finishing needs no second discovery.
    final configJson =
        sc.toJson()
          ..['authorizeUrl'] = oauthFlow.authorizationEndpoint.toString()
          ..['tokenUrl'] = oauthFlow.tokenEndpoint.toString();
    final record = RedirectTabRecord(
      config: SmartConfig.fromJson(configJson),
      jwksUri: _jwksUri,
      issuer: _issuer,
      revocationEndpoint: _revocationEndpoint,
      introspectionEndpoint: _introspectionEndpoint,
      pending: PendingRedirectLogin(
        startedAt: now(),
        nonce: secrets.nonce,
        codeVerifier: secrets.codeVerifier,
      ),
    );
    store.write(redirectTabKey(secrets.state), jsonEncode(record.toJson()));

    _logger.fine('Same-window login started');
    return authUrl;
  }

  /// Finish a same-window login started by [beginRedirectLogin], or, when
  /// this tab's login already finished, rebuild its client after a reload.
  /// Call it every time the redirect-URI page loads, with that page's
  /// address as [callbackUrl] and the same [store].
  ///
  /// The tab is the one named by the `state` in [callbackUrl]. Its tokens
  /// are kept in [store] under that tab's keys ([TabTokenStorage]), so two
  /// tabs open on two patients never read each other's tokens.
  ///
  /// SMART App Launch STU2.2 (hl7.org/fhir/smart-app-launch/STU2.2/
  /// app-launch.html, "Obtain authorization code", read 2026-11-19): "The
  /// app SHALL validate the value of the state parameter upon return to the
  /// redirect URL" and "SHALL ensure that the state value is securely tied
  /// to the user's current session". A `state` this browser session did not
  /// write to [store] is refused, as is one older than
  /// [redirectLoginLifetime]. A started login can be finished once: its
  /// secrets are deleted before the code is exchanged.
  ///
  /// Afterwards, show the address without its `code`
  /// (`currentBrowserWindow().replaceUrl(redirectCallbackUrlToKeep(url))`) so
  /// a reload does not offer the spent code again; keep the `state`, which
  /// is the tab's id.
  ///
  /// [createClient] builds the returned client; a package that extends
  /// [SmartFhirClient] passes its own constructor to get its own type back.
  static Future<SmartFhirClient> completeRedirectLogin({
    required Uri callbackUrl,
    required KeyValueStore store,
    http.Client? httpClient,
    AuditLogger? auditLogger,
    SessionManager? sessionManager,
    Logger? logger,
    DateTime Function() now = DateTime.now,
    SmartFhirClientFactory createClient = SmartFhirClient.new,
  }) async {
    final params = callbackUrl.queryParameters;
    final state = params[OAuthParameters.state];
    if (state == null) {
      throw const SecurityException(
        'Missing state parameter in authorization response',
        securityViolationType: SecurityViolationType.stateMismatch,
      );
    }
    final key = redirectTabKey(state);
    final record = _readRecord(store, key);
    if (record == null) {
      throw const SecurityException(
        'Invalid state parameter - possible CSRF attack',
        details: 'No login with this state was started in this browser session',
        securityViolationType: SecurityViolationType.stateMismatch,
      );
    }

    final client =
        createClient(
            config: record.config,
            httpClient: httpClient,
            auditLogger: auditLogger,
            sessionManager: sessionManager,
            logger: logger,
            tokenStorage: TabTokenStorage(store: store, tabKey: state),
          )
          .._jwksUri = record.jwksUri
          .._issuer = record.issuer
          .._revocationEndpoint = record.revocationEndpoint
          .._introspectionEndpoint = record.introspectionEndpoint;

    final pending = record.pending;
    if (pending == null) {
      // This tab's login finished earlier; the page has been reloaded.
      final tokens = await client.getStoredTokens();
      if (tokens == null) {
        throw const AuthenticationException(
          'This tab is no longer signed in; launch the app again',
        );
      }
      client._cachedSmartTokens = tokens;
      return client;
    }

    // One use only: the secrets go before anything else can fail.
    store.write(key, jsonEncode(record.withoutPending().toJson()));

    try {
      if (now().isAfter(pending.startedAt.add(redirectLoginLifetime))) {
        throw const SecurityException(
          'Expired state parameter',
          details: 'The login took longer than the time allowed',
          securityViolationType: SecurityViolationType.stateMismatch,
        );
      }
      final oauthFlow =
          await client._getOAuthFlow()
            ..resumeAuthorization(
              state: state,
              nonce: pending.nonce,
              codeVerifier: pending.codeVerifier,
            );
      final tokens = await oauthFlow.handleAuthorizationResponse(params);
      await client._finishLogin(tokens);
      return client;
    } on Object catch (e, stackTrace) {
      // The code is spent whatever failed, so the tab keeps nothing: no
      // record, and no tokens if they were stored before the failure.
      store.remove(key);
      await client.tokenStorage.clearTokens();
      client.clearInMemoryTokens();
      // The caller must be able to tell a forged or expired state
      // (SecurityException) from a refused consent or code
      // (AuthorizationException), so every FhirAuthException is kept.
      await client._loginFailed(
        e,
        stackTrace,
        keep: (e) => e is FhirAuthException,
      );
    }
  }

  /// [callbackUrl] without the one-time authorization `code` (RFC 6749
  /// section 4.1.2), keeping everything else, including the `state` that
  /// names the tab.
  static Uri redirectCallbackUrlToKeep(Uri callbackUrl) {
    final kept = Map<String, List<String>>.of(
      callbackUrl.queryParametersAll,
    )..remove(OAuthParameters.code);
    return callbackUrl.replace(queryParameters: kept.isEmpty ? null : kept);
  }

  static bool _isAuthenticationException(Object e) =>
      e is AuthenticationException;

  /// Perform backend service login using JWT client assertion
  Future<void> _performBackendServiceLogin() async {
    final bc = backendConfig!;
    _logger.fine('Starting backend service authentication');

    // Create signed JWT for client assertion
    final clientAssertion = await JwtValidator.createSignedJwt(
      clientId: bc.clientId,
      audience: bc.tokenUrl.toString(),
      privateKeyPem: bc.privateKey,
      validity: bc.tokenLifetime,
      keyId: bc.keyId,
    );

    // Get OAuth flow
    final oauthFlow = await _getOAuthFlow();

    // Perform client credentials grant
    final tokens = await oauthFlow.performClientCredentialsGrant(
      clientAssertion: clientAssertion,
      scopes: bc.scopes,
    );

    // Store tokens
    await storeTokens(tokens);

    _logger.fine('Backend service authentication successful');

    // Audit: log successful authentication
    await _auditLogger?.logAuthenticationSuccess(
      userId: 'system:${bc.clientId}',
      details: <String, dynamic>{
        'scopes': tokens.scopesList,
        'auth_type': 'backend_service',
      },
    );

    // Audit: log token issued
    await _auditLogger?.logTokenIssued(
      userId: 'system:${bc.clientId}',
      scopes: tokens.scopesList,
    );
  }

  @override
  Future<SmartTokenResponse> performTokenRefresh(String refreshToken) async {
    // Backend services don't use refresh tokens — re-authenticate
    if (isBackendService) {
      _logger.fine('Backend service re-authenticating (no refresh tokens)');
      await _performBackendServiceLogin();
      return _cachedSmartTokens!;
    }

    _logger.fine('Performing SMART token refresh');

    try {
      final oauthFlow = await _getOAuthFlow();
      final newTokens = await oauthFlow.refreshAccessToken(refreshToken);

      // Record activity on token refresh
      await _sessionManager?.recordActivity();

      // Audit: log token refresh
      await _auditLogger?.logTokenRefreshed(
        userId: newTokens.fhirUser,
      );

      return newTokens;
    } catch (e) {
      _logger.severe('Token refresh failed', e);
      rethrow;
    }
  }

  @override
  Future<void> storeTokens(SmartTokenResponse tokens) async {
    _cachedSmartTokens = tokens;
    await super.storeTokens(tokens);
  }

  @override
  Future<void> logout() async {
    final userId = _cachedSmartTokens?.fhirUser ?? 'unknown';

    // End session
    if (_sessionManager != null) {
      await _sessionManager.endSession(TimeoutReason.logout);
    }

    // Revoke tokens if revocation endpoint is available
    if (_revocationEndpoint != null && _cachedSmartTokens != null) {
      try {
        _logger.fine('Attempting to revoke tokens during logout');
        await revokeCurrentTokens();
      } on Exception catch (e) {
        _logger.warning('Token revocation failed during logout', e);
        // Continue with logout even if revocation fails
      }
    }

    // Audit: log session ended
    await _auditLogger?.logEvent(
      AuditEvent(
        eventType: AuditEventType.sessionEnded,
        severity: AuditSeverity.info,
        message: 'User logged out',
        userId: userId,
        clientId: config.clientId,
        outcome: true,
      ),
    );

    _cachedSmartTokens = null;
    await super.logout();
  }

  /// Record user activity (prevents idle timeout)
  Future<void> recordActivity() async {
    await _sessionManager?.recordActivity();
  }

  /// Extend session (refresh activity timestamp)
  Future<void> extendSession() async {
    await _sessionManager?.extendSession();
  }

  /// Get session information
  Map<String, dynamic>? getSessionInfo() => _sessionManager?.getSessionInfo();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Record activity on API requests
    await recordActivity();
    return super.send(request);
  }

  /// Discover OAuth endpoints from metadata
  Future<Map<String, dynamic>> _discoverEndpoints() async {
    _logger.fine('Discovering SMART endpoints');

    // Try .well-known/smart-configuration first. The discovery document is the
    // root of trust for every OAuth endpoint, so it MUST be fetched over TLS —
    // otherwise a network attacker could substitute malicious endpoints.
    final metadataUrl = Uri.parse(
      '${config.fhirBaseUrl}/.well-known/smart-configuration',
    );
    assertSecureAuthUrl(
      metadataUrl,
      field: 'fhirBaseUrl (SMART discovery)',
      allowInsecure: config.allowInsecureConnections,
    );

    try {
      final response = await _httpClient
          .get(metadataUrl)
          .timeout(_discoveryTimeout);

      if (response.statusCode == 200) {
        final metadata = jsonDecode(response.body) as Map<String, dynamic>;

        // Parse capabilities if present
        if (metadata['capabilities'] is List) {
          _serverCapabilities =
              (metadata['capabilities'] as List)
                  .map(
                    (c) => SmartCapability.values.firstWhere(
                      (cap) => cap.value == c,
                      orElse: () => SmartCapability.launchStandalone,
                    ),
                  )
                  .toList();
        }

        // Capture JWKS URI and issuer for id_token signature/claim validation
        if (metadata['jwks_uri'] != null) {
          _jwksUri = Uri.parse(metadata['jwks_uri'] as String);
          _logger.fine('Discovered JWKS URI: $_jwksUri');
        }
        if (metadata['issuer'] != null) {
          _issuer = metadata['issuer'] as String;
          _logger.fine('Discovered issuer: $_issuer');
        }

        // Store discovered endpoints
        if (metadata['revocation_endpoint'] != null) {
          _revocationEndpoint = Uri.parse(
            metadata['revocation_endpoint'] as String,
          );
          _logger.fine('Discovered revocation endpoint: $_revocationEndpoint');
        }

        if (metadata['introspection_endpoint'] != null) {
          _introspectionEndpoint = Uri.parse(
            metadata['introspection_endpoint'] as String,
          );
          _logger.fine(
            'Discovered introspection endpoint: $_introspectionEndpoint',
          );
        }

        return <String, dynamic>{
          'authorization_endpoint': Uri.parse(
            metadata['authorization_endpoint'] as String,
          ),
          'token_endpoint': Uri.parse(metadata['token_endpoint'] as String),
          if (_revocationEndpoint != null)
            'revocation_endpoint': _revocationEndpoint,
          if (_introspectionEndpoint != null)
            'introspection_endpoint': _introspectionEndpoint,
        };
      }
    } on Exception catch (e) {
      _logger.warning('Failed to fetch .well-known/smart-configuration', e);
    }

    // Fall back to CapabilityStatement
    return _discoverFromCapabilityStatement();
  }

  /// Discover endpoints from CapabilityStatement
  Future<Map<String, dynamic>> _discoverFromCapabilityStatement() async {
    _logger.fine('Fetching CapabilityStatement for endpoint discovery');

    final metadataUrl = Uri.parse('${config.fhirBaseUrl}/metadata');
    assertSecureAuthUrl(
      metadataUrl,
      field: 'fhirBaseUrl (CapabilityStatement discovery)',
      allowInsecure: config.allowInsecureConnections,
    );

    final response = await _httpClient
        .get(
          metadataUrl,
          headers: <String, String>{'Accept': 'application/fhir+json'},
        )
        .timeout(_discoveryTimeout);

    if (response.statusCode != 200) {
      throw NetworkException(
        'Failed to fetch CapabilityStatement',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    // The CapabilityStatement is read as JSON: this package serves every
    // FHIR version, so it names no version's model type. The path is
    // rest[0].security.extension, per the SMART App Launch
    // conformance page (oauth-uris and capabilities extensions).
    final capabilityStatement =
        jsonDecode(response.body) as Map<String, dynamic>;
    final rest =
        (capabilityStatement['rest'] as List<dynamic>?)?.firstOrNull
            as Map<String, dynamic>?;
    final security = rest?['security'] as Map<String, dynamic>?;
    final oauth = (security?['service'] as List<dynamic>?)?.firstOrNull;

    if (oauth == null) {
      throw const ConfigurationException(
        'No OAuth configuration found in CapabilityStatement',
        configurationField: 'rest.security.service',
      );
    }

    // Extract OAuth URIs and capabilities from extensions
    String? authEndpoint;
    String? tokenEndpoint;
    String? revocationEndpoint;
    String? introspectionEndpoint;
    final capabilities = <SmartCapability>[];

    final extensions =
        (security?['extension'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    for (final extension in extensions) {
      if (extension['url'] ==
          'http://fhir-registry.smarthealthit.org/StructureDefinition/oauth-uris') {
        final inner =
            (extension['extension'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        for (final ext in inner) {
          if (ext['url'] == 'authorize') {
            authEndpoint = ext['valueUri'] as String?;
          } else if (ext['url'] == 'token') {
            tokenEndpoint = ext['valueUri'] as String?;
          } else if (ext['url'] == 'revoke') {
            revocationEndpoint = ext['valueUri'] as String?;
            _revocationEndpoint =
                revocationEndpoint == null
                    ? null
                    : Uri.parse(revocationEndpoint);
            _logger.fine(
              'Discovered revocation endpoint: $_revocationEndpoint',
            );
          } else if (ext['url'] == 'introspect') {
            introspectionEndpoint = ext['valueUri'] as String?;
            _introspectionEndpoint =
                introspectionEndpoint == null
                    ? null
                    : Uri.parse(introspectionEndpoint);
            _logger.fine(
              'Discovered introspection endpoint: $_introspectionEndpoint',
            );
          }
        }
      } else if (extension['url'] ==
          'http://fhir-registry.smarthealthit.org/StructureDefinition/capabilities') {
        final valueCode = extension['valueCode'] as String?;
        if (valueCode != null) {
          final capability = SmartCapability.values
              .cast<SmartCapability?>()
              .firstWhere((cap) => cap!.value == valueCode, orElse: () => null);
          if (capability == null) {
            _logger.warning('Unknown SMART capability: $valueCode');
          } else {
            capabilities.add(capability);
            _logger.fine('Discovered capability: $valueCode');
          }
        }
      }
    }

    // Store capabilities
    _serverCapabilities = capabilities;

    if (authEndpoint == null || tokenEndpoint == null) {
      throw const ConfigurationException(
        'Missing OAuth endpoints in CapabilityStatement',
        configurationField: 'oauth-uris extension',
      );
    }

    return <String, dynamic>{
      'authorization_endpoint': Uri.parse(authEndpoint),
      'token_endpoint': Uri.parse(tokenEndpoint),
      if (_revocationEndpoint != null)
        'revocation_endpoint': _revocationEndpoint,
      if (_introspectionEndpoint != null)
        'introspection_endpoint': _introspectionEndpoint,
    };
  }

  /// Get server capabilities
  Future<List<SmartCapability>> getServerCapabilities() async {
    if (_serverCapabilities == null) {
      await _discoverEndpoints();
    }
    return _serverCapabilities ?? <SmartCapability>[];
  }

  /// Check if server supports a capability
  Future<bool> supportsCapability(SmartCapability capability) async {
    final capabilities = await getServerCapabilities();
    return capabilities.contains(capability);
  }

  /// Get revocation endpoint (may be null if not supported)
  Uri? get revocationEndpoint => _revocationEndpoint;

  /// Get introspection endpoint (may be null if not supported)
  Uri? get introspectionEndpoint => _introspectionEndpoint;

  /// Revoke the current access token
  Future<void> revokeAccessToken() async {
    if (_revocationEndpoint == null) {
      _logger.warning('No revocation endpoint available');
      throw const ConfigurationException(
        'Token revocation not supported by server',
        configurationField: 'revocation_endpoint',
      );
    }

    final tokens = _cachedSmartTokens ?? await getStoredTokens();
    if (tokens == null) {
      _logger.warning('No tokens available to revoke');
      return;
    }

    final oauthFlow = await _getOAuthFlow();
    await oauthFlow.revokeToken(
      tokens.accessToken,
      revocationEndpoint: _revocationEndpoint!,
      tokenTypeHint: 'access_token',
    );

    _logger.fine('Access token revoked');
  }

  /// Revoke the current refresh token
  Future<void> revokeRefreshToken() async {
    if (_revocationEndpoint == null) {
      _logger.warning('No revocation endpoint available');
      throw const ConfigurationException(
        'Token revocation not supported by server',
        configurationField: 'revocation_endpoint',
      );
    }

    final tokens = _cachedSmartTokens ?? await getStoredTokens();
    if (tokens?.refreshToken == null) {
      _logger.warning('No refresh token available to revoke');
      return;
    }

    final oauthFlow = await _getOAuthFlow();
    await oauthFlow.revokeToken(
      tokens!.refreshToken!,
      revocationEndpoint: _revocationEndpoint!,
    );

    _logger.fine('Refresh token revoked');
  }

  /// Revoke both access and refresh tokens
  Future<void> revokeCurrentTokens() async {
    try {
      await revokeAccessToken();
    } on Exception catch (e) {
      _logger.warning('Failed to revoke access token', e);
    }

    try {
      await revokeRefreshToken();
    } on Exception catch (e) {
      _logger.warning('Failed to revoke refresh token', e);
    }
  }

  /// Get token introspector (lazy initialization)
  TokenIntrospector getTokenIntrospector() {
    if (_introspectionEndpoint == null) {
      throw const ConfigurationException(
        'Token introspection not supported by server',
        configurationField: 'introspection_endpoint',
      );
    }

    return _tokenIntrospector ??= TokenIntrospector(
      introspectionEndpoint: _introspectionEndpoint!,
      clientId: config.clientId,
      clientSecret: config.clientSecret,
      allowInsecureConnections: config.allowInsecureConnections,
      httpClient: _httpClient,
      logger: _logger,
    );
  }

  /// Check if current access token is active
  Future<bool> isAccessTokenActive() async {
    try {
      final tokens = _cachedSmartTokens ?? await getStoredTokens();
      if (tokens == null) return false;

      final introspector = getTokenIntrospector();
      return await introspector.isTokenActive(tokens.accessToken);
    } on Exception catch (e) {
      _logger.warning('Failed to check token status', e);
      return false;
    }
  }

  /// Get need patient banner flag from current tokens
  bool? get needPatientBanner => _cachedSmartTokens?.needPatientBanner;

  /// Get SMART style URL from current tokens
  String? get smartStyleUrl => _cachedSmartTokens?.smartStyleUrl;

  /// Get launch intent from current tokens
  String? get intent => _cachedSmartTokens?.intent;

  /// Get tenant from current tokens
  String? get tenant => _cachedSmartTokens?.tenant;

  @override
  void clearInMemoryTokens() {
    _cachedSmartTokens = null;
    super.clearInMemoryTokens();
  }

  @override
  void close() {
    unawaited(_timeoutSub?.cancel());
    _timeoutSub = null;
    _sessionManager?.dispose();
    _oauthFlow?.dispose();
    _tokenIntrospector?.dispose();
    super.close();
  }
}
