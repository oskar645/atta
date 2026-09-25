import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:atta/src/app.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/push_notification_service.dart';
import 'package:atta/src/widgets/app_error_view.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await Firebase.initializeApp();
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
        } catch (_) {
          // Firebase Android configuration is supplied at release time.
        }
      }
      usePathUrlStrategy();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (details) {
        return const Material(
          child: AppErrorView(
            message: 'Экран временно недоступен. Попробуйте снова.',
            compact: true,
          ),
        );
      };
      runApp(const AttaApp());
    },
    (error, stackTrace) {
      if (ChatSocketService.isExpectedSocketCloseError(error)) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ATTA zone',
        ),
      );
    },
  );
}
