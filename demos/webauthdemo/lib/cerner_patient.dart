import 'dart:convert';

import 'package:fhir/r4.dart';
import 'package:fhir_at_rest/r4.dart';
import 'package:fhir_auth/r4.dart';

import 'api.dart';
import 'scopes.dart';

Future<void> cernerPatientRequest(Uri fhirCallback) async {
  final client = SmartFhirClient(
    fhirUri: FhirUri(Api.cernerUrl),
    clientId: Api.cernerPatientClientId,
    redirectUri: FhirUri(fhirCallback),
    scopes: cernerScopes.scopesList(),
  );

  print('created client');

  await client.login();

  print(client.patientId);

  if (client.fhirUri.value != null && client.patientId != null) {
    final request = FhirRequest.read(
      base: client.fhirUri.value ?? Uri.parse('127.0.0.1'),
      type: R4ResourceType.Patient,
      fhirId: '${client.patientId}',
      client: client,
    );
    try {
      final response = await request.request();
      print(jsonEncode(response.toJson()));
      print('Response from read:\n${response.toJson()}');
    } catch (e) {
      print(e);
    }
  }
}
