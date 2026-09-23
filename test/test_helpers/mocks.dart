/// Mock classes for testing
library;

import 'package:fhir_auth/fhir_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';

// Generate mocks with build_runner:
// flutter pub run build_runner build --delete-conflicting-outputs

@GenerateMocks([
  http.Client,
  TokenStorage,
  AuditLogger,
  SessionManager,
])
void main() {}
