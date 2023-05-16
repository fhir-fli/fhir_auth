import 'package:fhir/r4.dart';
import 'package:fhir_at_rest/r4.dart';

import 'package:fhir_auth/r4.dart';

import 'api.dart';
import 'new_patient.dart';

Future<void> gcsRequest(Uri fhirCallback) async {
  final client = GcpFhirClient(
    redirectUri: FhirUri(fhirCallback),
    fhirUri: FhirUri(Api.gcsUrl),
    clientId: Api.gcsClientId,
  );

  await client.login();

  final _newPatient = newPatient();
  print('Patient to be uploaded: ${_newPatient.toJson()}');
  if (client.fhirUri.value != null) {
    final request1 = FhirRequest.create(
      base: client.fhirUri.value!,
      resource: _newPatient,
      client: client,
    );

    String? newId;
    try {
      final response = await request1.request();
      newId = response.fhirId;
      print('Response from upload: ${response.toJson()}');
    } catch (e) {
      print(e);
    }

    if (newId is! String) {
      print(newId);
    } else {
      final request2 = FhirRequest.read(
        base: client.fhirUri.value!,
        type: R4ResourceType.Patient,
        fhirId: newId,
        client: client,
      );
      try {
        final response2 = await request2.request();
        print('Response from read:\n${response2.toJson()}');
      } catch (e) {
        print(e);
      }
    }
  }
}
