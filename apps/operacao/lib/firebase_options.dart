// Configuração do Firebase.
//
// Jeito recomendado: rode `flutterfire configure` nesta pasta; ele
// substitui este arquivo pelo do seu projeto.
// Alternativa: passe os valores na compilação, por exemplo
//   flutter run --dart-define-from-file=../../firebase.env.json
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');

  static bool get configurado => _apiKey.isNotEmpty;

  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: _apiKey,
        appId: String.fromEnvironment('FIREBASE_APP_ID_OPERACAO'),
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      );
}
