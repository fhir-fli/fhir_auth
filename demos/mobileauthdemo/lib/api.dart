import 'package:fhir/r4.dart';

mixin Api {
  static const schema = 'dev.fhirfli.mobileauthdemo';

  /// redirect url for oauth2 authentication
  static final fhirCallback = FhirUri('dev.fhirfli.mobileauthdemo:/callback');

  /// HAPI
  static const hapiUrl = 'http://hapi.fhir.org/baseR4';

  /// GCS
  static const gcsUrl = 'https://healthcare.googleapis.com/v1/projects'
      '/fhir-379821/locations/us-central1/datasets/fhir-auth/fhirStores/fhir-auth/fhir';
  static const gcsClientId =
      '746873113207-5pl1qc38upkufp8eqprus1trh6ejeeu4.apps.googleusercontent.com';

  /// Meld
  static const meldClientId = '604185a0-efcd-4bee-aa29-d0f237adbab3';
  static const meldUrl = 'https://gw.interop.community/MayJuun/data';
}
