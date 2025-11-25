import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase configuration options for different platforms.
///
/// For mobile (iOS/Android), native config files are used:
/// - Android: android/app/google-services.json
/// - iOS: ios/Runner/GoogleService-Info.plist
///
/// For web, we must provide explicit [FirebaseOptions].
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    // On mobile/desktop, Firebase will use the platform-specific config
    // bundled in the app (google-services.json / GoogleService-Info.plist),
    // so we don't need to pass options explicitly.
    throw UnsupportedError(
      'DefaultFirebaseOptions.currentPlatform is only used for web. '
      'For mobile/desktop, call Firebase.initializeApp() without options.',
    );
  }

  /// Web configuration from Firebase Console.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDxWP4tlfNvV3kPOa8GncZpFJT7NvM_fUE',
    authDomain: 'flutterloc-41cf3.firebaseapp.com',
    projectId: 'flutterloc-41cf3',
    storageBucket: 'flutterloc-41cf3.firebasestorage.app',
    messagingSenderId: '115117579254',
    appId: '1:115117579254:web:8f41ebf4ad74a2feae05d7',
    measurementId: 'G-090ZMNTYX5',
  );
}
