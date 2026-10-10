import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Client configuration for Firebase project `intronews`.
/// Replace this file by running `flutterfire configure` before a production deploy.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => web,
    };
  }

  static const web = FirebaseOptions(
    apiKey: 'demo-intronews-web',
    appId: '1:000000000000:web:intronews',
    messagingSenderId: '000000000000',
    projectId: 'intronews',
    authDomain: 'intronews.firebaseapp.com',
    storageBucket: 'intronews.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: 'demo-intronews-android',
    appId: '1:000000000000:android:intronews',
    messagingSenderId: '000000000000',
    projectId: 'intronews',
    storageBucket: 'intronews.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'demo-intronews-ios',
    appId: '1:000000000000:ios:intronews',
    messagingSenderId: '000000000000',
    projectId: 'intronews',
    storageBucket: 'intronews.firebasestorage.app',
    iosBundleId: 'com.example.intronews',
  );
}
