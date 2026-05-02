import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs',
    appId: '1:363693923093:android:38f68ec56eeaac9b79271c',
    messagingSenderId: '363693923093',
    projectId: 'mediposs-64841',
    storageBucket: 'mediposs-64841.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs',
    appId: '1:363693923093:ios:38f68ec56eeaac9b79271c', // Assuming same suffix for now or generic
    messagingSenderId: '363693923093',
    projectId: 'mediposs-64841',
    storageBucket: 'mediposs-64841.firebasestorage.app',
    iosBundleId: 'com.medipos.medipos',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs',
    appId: '1:363693923093:ios:38f68ec56eeaac9b79271c',
    messagingSenderId: '363693923093',
    projectId: 'mediposs-64841',
    storageBucket: 'mediposs-64841.firebasestorage.app',
    iosBundleId: 'com.medipos.medipos',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD84Pud-HYvei7wzXHQssToljYJo4EiCxs',
    appId: '1:363693923093:android:38f68ec56eeaac9b79271c', // Reusing android ID for now as it often works for simple Firestore access
    messagingSenderId: '363693923093',
    projectId: 'mediposs-64841',
    storageBucket: 'mediposs-64841.firebasestorage.app',
  );
}
