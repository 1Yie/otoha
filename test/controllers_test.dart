import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/data/mock_catalog.dart';
import 'package:otoha/src/services/player_session_store.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';

void main() {
  group('WorkspaceController', () {
    test('restores prior workspaces through history', () {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);

      controller.navigateTo(WorkspacePage.explore);
      controller.navigateTo(WorkspacePage.library);

      expect(controller.current, WorkspacePage.library);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isFalse);

      controller.goBack();

      expect(controller.current, WorkspacePage.explore);
      expect(controller.canGoForward, isTrue);

      controller.goForward();

      expect(controller.current, WorkspacePage.library);
    });
  });

  group('PlayerController', () {
    test('changes tracks and retains local playback state', () {
      final controller = PlayerController(MockCatalog.tracks);
      addTearDown(controller.dispose);

      controller.selectTrack(MockCatalog.tracks[1]);

      expect(controller.currentTrack, MockCatalog.tracks[1]);
      expect(controller.positionSeconds, 0);
      expect(controller.isPlaying, isTrue);

      controller.next();

      expect(controller.currentTrack, MockCatalog.tracks[2]);
      expect(controller.positionSeconds, 0);

      controller.toggleShuffle();

      expect(controller.isShuffled, isTrue);
      expect(controller.queue.first, controller.currentTrack);

      controller.cycleRepeatMode();

      expect(controller.repeatMode, PlaybackRepeatMode.all);
    });

    test('restores a simulated playlist session after restart', () async {
      final store = _MemoryPlayerSessionStore();
      final source = PlayerController(MockCatalog.tracks, sessionStore: store);
      addTearDown(source.dispose);
      source.playTracks(MockCatalog.tracks.take(3).toList(growable: false));
      source.selectTrack(MockCatalog.tracks[1]);
      source.seekTo(73);
      source.setVolume(0.4);
      source.cycleRepeatMode();
      await Future<void>.delayed(Duration.zero);

      final restored = PlayerController(
        MockCatalog.tracks,
        sessionStore: store,
      );
      addTearDown(restored.dispose);
      await restored.restoreSession();

      expect(restored.queue.map((track) => track.id), <String>[
        'soft-signal',
        'after-image',
        'room-for-light',
      ]);
      expect(restored.currentTrack.id, 'after-image');
      expect(restored.positionSeconds, 73);
      expect(restored.volume, 0.4);
      expect(restored.repeatMode, PlaybackRepeatMode.all);
      expect(restored.isPlaying, isTrue);
    });
  });
}

class _MemoryPlayerSessionStore implements PlayerSessionStore {
  Map<String, Object?>? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<Map<String, Object?>?> read() async => value;

  @override
  Future<void> write(Map<String, Object?> value) async {
    this.value = value;
  }
}
