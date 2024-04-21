// ignore_for_file: unreachable_from_main

import 'dart:developer';

import 'package:fhir_auth/r4.dart';
import 'package:fhir_primitives/fhir_primitives.dart';
import 'package:fhir_r4/fhir_r4.dart';

Future<void> main() async {
  const String url = 'http://fhirurl';
  const String clientId = 'myClienId';
  const String fhirCallback = 'fhir_auth://callback';
  final Scopes scopes = Scopes(
    clinicalScopes: <ClinicalScope>[
      ClinicalScope(
        role: Role.patient,
        resourceType: R4ResourceType.Patient,
        interaction: Interaction.any,
      ),
    ],
    openid: true,
    offlineAccess: true,
  );

  final SmartFhirClient client = SmartFhirClient(
    fhirUri: FhirUri(url),
    clientId: clientId,
    redirectUri: FhirUri(fhirCallback),
    scopes: scopes.scopesList(),
  );

  try {
    await client.login();
    if (client.fhirUri.value != null) {
      const Patient newPatient = Patient(id: '12345');
      log('Patient to be uploaded:\n${newPatient.toJson()}');
      final FhirRequest request1 = FhirRequest.create(
        base: client.fhirUri.value,
        //?? Uri.parse('127.0.0.1'),
        resource: newPatient,
        client: client,
      );

      String? newId;
      try {
        final Resource response = await request1.request();
        log('Response from upload:\n${response.toJson()}');
        newId = response.id;
      } catch (e) {
        log(e.toString());
      }
      if (newId is! FhirId) {
        log(newId.toString());
      } else {
        final FhirRequest request2 = FhirRequest.read(
          base: client.fhirUri.value ?? Uri.parse('127.0.0.1'),
          type: R4ResourceType.Patient,
          id: newId,
          client: client,
        );
        try {
          final Resource response = await request2.request();
          log('Response from read:\n${response.toJson()}');
        } catch (e) {
          log(e.toString());
        }
      }
    }
  } catch (e, stack) {
    log('Error $e');
    log('Stack $stack');
  }
}

/// Just to remove errors from this file, doesn't actually do anything
class FhirRequest {
  Uri? base;
  R4ResourceType? type;
  String? id;
  FhirClient? client;
  Resource? resource;

  FhirRequest(this.base, this.type, this.id, this.client, this.resource);

  FhirRequest copyWith({
    Uri? base,
    R4ResourceType? type,
    String? id,
    FhirClient? client,
    Resource? resource,
  }) =>
      FhirRequest(base ?? this.base, type ?? this.type, id ?? this.id,
          client ?? this.client, resource ?? this.resource);

  Future<Resource> request() async => const Patient();

  factory FhirRequest.read({
    Uri? base,
    R4ResourceType? type,
    String? id,
    FhirClient? client,
  }) =>
      FhirRequest(base, type, id, client, null);
  factory FhirRequest.create({
    Uri? base,
    Resource? resource,
    FhirClient? client,
  }) =>
      FhirRequest(base, null, null, client, resource);
}
