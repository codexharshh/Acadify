// lib/firebase_options.dart
// Auto-generated Firebase config for Acadify.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC9VU3ycPiEfqstm4psvPbnOql7zO3LGc0',
    authDomain: 'acadify-f6372.firebaseapp.com',
    projectId: 'acadify-f6372',
    storageBucket: 'acadify-f6372.firebasestorage.app',
    messagingSenderId: '1083087964339',
    appId: '1:1083087964339:web:2d04ff02b31bd136df48c6',
    measurementId: 'G-W7LPZXRYWJ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC9VU3ycPiEfqstm4psvPbnOql7zO3LGc0',
    authDomain: 'acadify-f6372.firebaseapp.com',
    projectId: 'acadify-f6372',
    storageBucket: 'acadify-f6372.firebasestorage.app',
    messagingSenderId: '1083087964339',
    appId: '1:1083087964339:web:2d04ff02b31bd136df48c6',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC9VU3ycPiEfqstm4psvPbnOql7zO3LGc0',
    authDomain: 'acadify-f6372.firebaseapp.com',
    projectId: 'acadify-f6372',
    storageBucket: 'acadify-f6372.firebasestorage.app',
    messagingSenderId: '1083087964339',
    appId: '1:1083087964339:web:2d04ff02b31bd136df48c6',
  );
}
