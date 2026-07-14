import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/desktop_shell_controllers.dart';

const desktopMinimumWindowSize = Size(1120, 720);

class TrayLabels {
  const TrayLabels({
    required this.showWindow,
    required this.play,
    required this.pause,
    required this.quit,
  });

  final String showWindow;
  final String play;
  final String pause;
  final String quit;
}

class DesktopTrayController with WindowListener, TrayListener {
  DesktopTrayController();

  static const _showWindowKey = 'show-window';
  static const _togglePlaybackKey = 'toggle-playback';
  static const _quitKey = 'quit';

  PlayerController? _playerController;
  TrayLabels _labels = const TrayLabels(
    showWindow: 'Show window',
    play: 'Play',
    pause: 'Pause',
    quit: 'Quit',
  );
  bool _isInitialized = false;
  bool _isExiting = false;
  bool? _wasPlaying;
  void Function()? _windowShownCallback;

  void setWindowShownCallback(void Function()? callback) {
    _windowShownCallback = callback;
  }

  Future<void> initialize(PlayerController playerController) async {
    if (_isInitialized) {
      return;
    }
    _playerController = playerController;
    _wasPlaying = playerController.isPlaying;
    playerController.addListener(_handlePlayerChanged);
    windowManager.addListener(this);
    trayManager.addListener(this);

    try {
      await trayManager.setIcon(await _trayIconPath());
      await _updateMenu();
      await windowManager.setPreventClose(true);
      _isInitialized = true;
    } on Object {
      playerController.removeListener(_handlePlayerChanged);
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
  }

  Future<void> updateLabels(TrayLabels labels) async {
    _labels = labels;
    if (_isInitialized) {
      await _updateMenu();
    }
  }

  void dispose() {
    _windowShownCallback = null;
    final playerController = _playerController;
    if (playerController != null) {
      playerController.removeListener(_handlePlayerChanged);
    }
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    if (_isInitialized) {
      unawaited(trayManager.destroy());
    }
  }

  @override
  void onWindowClose() {
    if (_isInitialized && !_isExiting) {
      unawaited(windowManager.hide());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showWindowKey:
        unawaited(_showWindow());
      case _togglePlaybackKey:
        _playerController?.togglePlaying();
      case _quitKey:
        unawaited(_quit());
    }
  }

  void _handlePlayerChanged() {
    final isPlaying = _playerController?.isPlaying;
    if (!_isInitialized || isPlaying == _wasPlaying) {
      return;
    }
    _wasPlaying = isPlaying;
    unawaited(_updateMenu());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.setMinimumSize(desktopMinimumWindowSize);
    await windowManager.focus();
    _windowShownCallback?.call();
  }

  Future<void> _quit() async {
    _isExiting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _updateMenu() {
    final isPlaying = _playerController?.isPlaying ?? false;
    return trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(key: _showWindowKey, label: _labels.showWindow),
          MenuItem(
            key: _togglePlaybackKey,
            label: isPlaying ? _labels.pause : _labels.play,
          ),
          MenuItem.separator(),
          MenuItem(key: _quitKey, label: _labels.quit),
        ],
      ),
    );
  }

  Future<String> _trayIconPath() async {
    final assetPath = Platform.isWindows
        ? 'windows/runner/resources/app_icon.ico'
        : 'assets/icon/icon.png';
    final extension = Platform.isWindows ? 'ico' : 'png';
    final data = await rootBundle.load(assetPath);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/otoha-tray.$extension');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }
}
