import 'dart:math';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhir_at_rest/r4.dart';
import 'package:fhir_auth/fhir_client/epic_fhir_client.dart';
import 'package:fhir_auth/r4.dart';

import 'ids.dart';
import 'new_patient.dart';
import 'scopes.dart';

Future<void> epicClinicianRequest(Uri fhirCallback) async {
  final client = EpicFhirClient(
    fhirUri: FhirUri(Api.epicUrl),
    clientId: Api.epicClinicianClientId,
    redirectUri: FhirUri(fhirCallback),
    scopes: scopes.scopesList(),
  );

  print('created client');

  await client.login();

  print('logged in');

  if (client.fhirUri.value != null) {
    final patientToUpload = newPatient();
    print('Patient to be uploaded:\n${patientToUpload.toJson()}');
    final request1 = FhirRequest.create(
      base: client.fhirUri.value!,
      resource: patientToUpload,
      client: client,
    );

    String? newId;

    final response = await request1.request();
    print('Response from upload:\n${response.toJson()}');
    newId = response.fhirId;
  }
}

String generateRandomString(int len) {
  var r = Random();
  const chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  return List.generate(len, (index) => chars[r.nextInt(chars.length)]).join();
}
