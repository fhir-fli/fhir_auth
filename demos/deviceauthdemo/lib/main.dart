import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'gcs_request.dart';
import 'hapi_request.dart';
import 'meld_request.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SafeArea(
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                children: [
                  ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all(Colors.white),
                        side: MaterialStateProperty.all(
                            const BorderSide(color: Colors.black)),
                      ),
                      child: Image.asset('assets/hapi.png'),
                      onPressed: () async => await hapiRequest()),
                  ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all(Colors.white),
                        side: MaterialStateProperty.all(
                            const BorderSide(color: Colors.black)),
                      ),
                      child: Image.asset('assets/meld.png'),
                      onPressed: () async => await meldRequest()),
                  ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all(Colors.white),
                        side: MaterialStateProperty.all(
                            const BorderSide(color: Colors.black)),
                      ),
                      child: Image.asset('assets/gcp.png'),
                      onPressed: () async => await gcsRequest()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
