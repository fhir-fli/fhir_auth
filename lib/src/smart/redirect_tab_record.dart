/// What a same-window SMART login keeps in session storage for one tab.
library;

import 'package:fhir_auth/fhir_auth.dart' show SmartConfig;

/// The record one browser tab's same-window login keeps in session storage,
/// under a key made from the login's OAuth `state`.
///
/// It holds what is needed to finish the login after the page comes back
/// from the authorization server, and to rebuild the client when the page
/// reloads. It never holds a client secret: [SmartConfig.toJson] leaves
/// secrets out, and the redirect login refuses confidential clients.
class RedirectTabRecord {
  /// A record for a login that has started and not yet come back.
  const RedirectTabRecord({
    required this.config,
    this.jwksUri,
    this.issuer,
    this.revocationEndpoint,
    this.introspectionEndpoint,
    this.pending,
  });

  /// Read a record written by [toJson].
  factory RedirectTabRecord.fromJson(Map<String, dynamic> json) {
    Uri? uri(String key) {
      final value = json[key] as String?;
      return value == null ? null : Uri.parse(value);
    }

    final pending = json['pending'] as Map<String, dynamic>?;
    return RedirectTabRecord(
      config: SmartConfig.fromJson(json['config'] as Map<String, dynamic>),
      jwksUri: uri('jwksUri'),
      issuer: json['issuer'] as String?,
      revocationEndpoint: uri('revocationEndpoint'),
      introspectionEndpoint: uri('introspectionEndpoint'),
      pending: pending == null ? null : PendingRedirectLogin.fromJson(pending),
    );
  }

  /// The SMART configuration, with the authorization and token endpoints
  /// filled in so that finishing the login needs no second discovery.
  final SmartConfig config;

  /// Discovered JWKS URI, to check the id_token signature.
  final Uri? jwksUri;

  /// Discovered issuer, the id_token `iss` to expect.
  final String? issuer;

  /// Discovered token revocation endpoint.
  final Uri? revocationEndpoint;

  /// Discovered token introspection endpoint.
  final Uri? introspectionEndpoint;

  /// The secrets of a login that has not come back yet; null once it has.
  final PendingRedirectLogin? pending;

  /// The same record with the pending login removed: it can be finished at
  /// most once.
  RedirectTabRecord withoutPending() => RedirectTabRecord(
    config: config,
    jwksUri: jwksUri,
    issuer: issuer,
    revocationEndpoint: revocationEndpoint,
    introspectionEndpoint: introspectionEndpoint,
  );

  /// The record as JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'config': config.toJson(),
    if (jwksUri != null) 'jwksUri': jwksUri.toString(),
    if (issuer != null) 'issuer': issuer,
    if (revocationEndpoint != null)
      'revocationEndpoint': revocationEndpoint.toString(),
    if (introspectionEndpoint != null)
      'introspectionEndpoint': introspectionEndpoint.toString(),
    if (pending != null) 'pending': pending!.toJson(),
  };
}

/// The secrets of an authorization request whose answer has not come back.
class PendingRedirectLogin {
  /// Secrets of the request sent at [startedAt].
  const PendingRedirectLogin({
    required this.startedAt,
    this.nonce,
    this.codeVerifier,
  });

  /// Read secrets written by [toJson].
  factory PendingRedirectLogin.fromJson(Map<String, dynamic> json) =>
      PendingRedirectLogin(
        startedAt: DateTime.parse(json['startedAt'] as String),
        nonce: json['nonce'] as String?,
        codeVerifier: json['codeVerifier'] as String?,
      );

  /// When the browser was sent to the authorization server.
  final DateTime startedAt;

  /// The OpenID Connect nonce sent, if any.
  final String? nonce;

  /// The PKCE code verifier whose challenge was sent, if any.
  final String? codeVerifier;

  /// The secrets as JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (nonce != null) 'nonce': nonce,
    if (codeVerifier != null) 'codeVerifier': codeVerifier,
  };
}
