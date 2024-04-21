import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhir_at_rest/r4.dart';
import 'package:fhir_auth/r4.dart';

import 'ids.dart';

Future gcsRequest() async {
  final client = GcpFhirClient(
    clientId: Api.gcsClientId,
    redirectUri: Api.fhirCallback,
    fhirUri: FhirUri(Api.gcsUrl),
  );

  await client.login();

  final newPatient = newPatient();
  print('Patient to be uploaded: ${newPatient.toJson()}');
  if (client.fhirUri.value != null) {
    final request1 = FhirRequest.create(
      base: client.fhirUri.value!,
      resource: newPatient,
      client: client,
    );

    String? newId;
    try {
      final response = await request1.request(headers: {});
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
        final response2 = await request2.request(headers: {});
        print('Response from read:\n${response2.toJson()}');
      } catch (e) {
        print(e);
      }
    }
  }
}
