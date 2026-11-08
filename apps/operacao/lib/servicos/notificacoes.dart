import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';

/// Registra o token de push e inscreve o entregador nos avisos da zona.
class Notificacoes {
  static Future<void> iniciar(String papel) async {
    try {
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission();
      final token = await fcm.getToken();
      if (token != null) await db.doc('users/$uid').update({'fcmToken': token});
      fcm.onTokenRefresh.listen((t) => db.doc('users/$uid').update({'fcmToken': t}));
      if (papel == 'entregador') {
        await fcm.subscribeToTopic('entregadores');
        final e = await db.doc('entregadores/$uid').get();
        final zona = e.data()?['zonaId'] as String?;
        if (zona != null) await fcm.subscribeToTopic('zona_$zona');
      }
    } on FirebaseException {
      // push é conveniência; o app continua funcionando pelo Firestore
    }
  }
}
