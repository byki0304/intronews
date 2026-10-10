import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Client configuration for Firebase project `intronews`.
/// The web app values come from the Firebase console SDK config.
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
    apiKey: 'AIzaSyCHPPU0MzMvd30VafxRTKOr99Ru9xA6hAg',
    appId: '1:588543998826:web:2cd13468c3fec74a4d4313',
    messagingSenderId: '588543998826',
    projectId: 'intronews',
    authDomain: 'intronews.firebaseapp.com',
    storageBucket: 'intronews.firebasestorage.app',
    measurementId: 'G-TT9JSLDWQ7',
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
