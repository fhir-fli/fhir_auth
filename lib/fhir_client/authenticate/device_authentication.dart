// Package imports:
import 'package:fhir/primitive_types/primitive_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

// Project imports:
import 'base_authentication.dart';

/// BaseAuthentication for mobile
BaseAuthentication createAuthentication() => DeviceAuthentication();

/// MobileAuthentication Class
class DeviceAuthentication implements BaseAuthentication {
  /// Only method is to authenticate
  @override
  Future<String> authenticate({
    required Uri authorizationUrl,
    required FhirUri redirectUri,
  }) async {
    if (['android', 'ios'].contains(defaultTargetPlatform.name)) {
      return await FlutterWebAuth2.authenticate(
        callbackUrlScheme: redirectUri.value!.scheme,
        url: authorizationUrl.toString(),
        preferEphemeral: true,
      );
    } else {
      if (['linux', 'macos', 'windows'].contains(defaultTargetPlatform.name)) {
        return await FlutterWebAuth2.authenticate(
          callbackUrlScheme: redirectUri.value!.scheme,
          url: authorizationUrl.toString(),
          preferEphemeral: true,
        );
      }
      throw UnsupportedError(
          'Cannot authenticate without dart:html or dart:io.');
    }
  }
}
