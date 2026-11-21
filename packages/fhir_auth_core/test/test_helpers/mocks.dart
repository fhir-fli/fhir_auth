/// Mock classes for testing
library;

import 'package:fhir_auth_core/fhir_auth_core.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';

// Generate mocks with build_runner:
// dart run build_runner build --delete-conflicting-outputs

@GenerateMocks([
  http.Client,
  TokenStorage,
  AuditLogger,
  SessionManager,
])
void main() {}
