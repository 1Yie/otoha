import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/otoha_app.dart';
import 'src/services/desktop_tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  DesktopTrayController? desktopTrayController;

  if (!kIsWeb && _isDesktopPlatform()) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1440, 896),
      minimumSize: Size(1120, 720),
      center: true,
      backgroundColor: Color(0xFF111210),
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    desktopTrayController = DesktopTrayController();
  }

  runApp(OtohaApp(desktopTrayController: desktopTrayController));
}

bool _isDesktopPlatform() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}
