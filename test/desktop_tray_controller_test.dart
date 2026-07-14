import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/services/desktop_tray_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tray activation restores window constraints and focus', (
    tester,
  ) async {
    const channel = MethodChannel('window_manager');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'isMinimized' => false,
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final windowShown = Completer<void>();
    final controller = DesktopTrayController()
      ..setWindowShownCallback(windowShown.complete);
    addTearDown(controller.dispose);

    controller.onTrayIconMouseDown();
    await windowShown.future;

    expect(
      calls.map((call) => call.method),
      orderedEquals(<String>['isMinimized', 'show', 'setMinimumSize', 'focus']),
    );
    final minimumSizeCall = calls.singleWhere(
      (call) => call.method == 'setMinimumSize',
    );
    expect(
      minimumSizeCall.arguments,
      containsPair('width', desktopMinimumWindowSize.width),
    );
    expect(
      minimumSizeCall.arguments,
      containsPair('height', desktopMinimumWindowSize.height),
    );
  });
}
