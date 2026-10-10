import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'firebase_options.dart';

class Backend {
  static late final FirebaseFunctions functions;

  static Future<void> start() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    functions = FirebaseFunctions.instanceFor(region: AppConfig.region);
    if (!AppConfig.useEmulators) return;
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8088);
    await FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
    functions.useFunctionsEmulator('127.0.0.1', 5001);
  }

  static Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call(data);
    final raw = result.data;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'ok': true};
  }
}
