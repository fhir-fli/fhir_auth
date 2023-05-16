mixin Api {
  /// HAPI
  static const hapiUrl = 'http://hapi.fhir.org/baseR4';

  /// Meld
  static const meldClientId = '70b3d3b3-7ed6-414b-9d7b-e0e237354449';
  static const meldUrl = 'https://gw.interop.community/authdemo/data';

  /// Epic
  static const epicPatientClientId = '3fa5caf9-8a98-4828-92de-59e66bcb2064';
  static const epicClinicianClientId = '8a50630d-830f-479b-b738-f0b4ac07004d';
  static const epicUrl =
      'https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4';

  /// Cerner
  static const cernerPatientClientId = 'a6e6a60e-36cc-4cfe-ba19-fc2ffc334b66';
  static const cernerUrl =
      'https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d';

  /// user = nancysmart
  /// pw = Cerner01
  ///
  static const cernerClinicianClientId = 'da0d3bcf-146f-4a24-9ccd-c71aa0e62814';

  /// GCS
  static const gcsUrl = 'https://healthcare.googleapis.com/v1/projects'
      '/demos-322021/locations/us-central1/datasets/mayjuun/fhirStores/dev/fhir';
  static const gcsClientId =
      '691103016946-rj3hdtham6a9ial8ka3g6do9pj6k1o3l.apps.googleusercontent.com';
}
