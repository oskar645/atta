import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atta/src/app.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/widgets/app_error_view.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
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
