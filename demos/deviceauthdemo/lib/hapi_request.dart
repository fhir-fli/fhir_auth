import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhir_at_rest/r4.dart';
import 'package:fhir_auth/r4.dart';

import 'ids.dart';
import 'scopes.dart';

Future hapiRequest() async {
  final client = FhirClient(
    fhirUri: FhirUri(Uri.encodeFull(Api.hapiUrl)),
    scopes: scopes.scopesList(),
  );

  try {
    if (client.fhirUri.value != null) {
      final newPatient = newPatient();
      print('Patient to be uploaded:\n${newPatient.toJson()}');
      final request1 = FhirRequest.create(
        base: client.fhirUri.value!,
        //?? Uri.parse('127.0.0.1'),
        resource: newPatient,
        client: client,
      );

      String? newId;
      try {
        final response = await request1.request(headers: {});
        print('Response from upload:\n${response.toJson()}');
        newId = response.fhirId;
      } catch (e) {
        print(e);
      }
      if (newId is! String) {
        print(newId);
      } else {
        final request2 = FhirRequest.read(
          base: client.fhirUri.value ?? Uri.parse('127.0.0.1'),
          type: R4ResourceType.Patient,
          fhirId: newId,
          client: client,
        );
        try {
          final response = await request2.request(headers: {});
          print('Response from read:\n${response.toJson()}');
        } catch (e) {
          print(e);
        }
      }
    }
  } catch (e, stack) {
    print('Error $e');
    print('Stack $stack');
  }
}
