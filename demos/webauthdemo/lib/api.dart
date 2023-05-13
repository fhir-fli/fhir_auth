mixin Api {
  /// Cerner
  static const cernerPatientClientId = 'a6e6a60e-36cc-4cfe-ba19-fc2ffc334b66';
  static const cernerPatientUrl =
      'https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d';

  /// user = nancysmart
  /// pw = Cerner01
  ///
  static const cernerClinicianClientId = 'da0d3bcf-146f-4a24-9ccd-c71aa0e62814';
  static const cernerClinicianUrl =
      'https://fhir-ehr-code.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d';

  /// Epic
  static const epicPatientClientId = '3fa5caf9-8a98-4828-92de-59e66bcb2064';
  static const epicClinicianClientId = '8a50630d-830f-479b-b738-f0b4ac07004d';
  static const epicUrl =
      'https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4';

  /// GCS
  static const gcsUrl = 'https://healthcare.googleapis.com/v1/projects'
      '/demos-322021/locations/us-central1/datasets/mayjuun/fhirStores/dev/fhir';
  static const gcsClientId =
      '691103016946-plc42eg1qr49ke0gbd1rsd650eo0el5p.apps.googleusercontent.com';

  /// HAPI
  static const hapiUrl = 'http://hapi.fhir.org/baseR4';

  /// Meld
  static const meldClientId = '7cf38a3c-ae85-419e-b3ee-a35094797aca';
  static const meldUrl = 'https://gw.interop.community/MayJuun/data';
}
