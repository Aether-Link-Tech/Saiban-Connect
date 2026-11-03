import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'env.dart';

/// Initializes Firebase for the cloud project, or for the local emulators when
/// built with --dart-define=USE_EMULATOR=true.
Future<void> initFirebase() async {
  if (!Env.useEmulator) {
    // Android reads android/app/google-services.json (created by `flutterfire configure`).
    await Firebase.initializeApp();
    return;
  }

  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: Env.isAndroid ? '1:000000000000:android:0000000000000000' : '1:000000000000:web:0000000000000000',
      messagingSenderId: '000000000000',
      projectId: Env.demoProjectId,
      storageBucket: '${Env.demoProjectId}.appspot.com',
    ),
  );
  final host = Env.emulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
}
