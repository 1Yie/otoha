import 'package:otoha/l10n/app_localizations.dart';

import '../state/youtube_library_controller.dart';

String localizeYouTubeLibraryError(
  YouTubeLibraryError error,
  AppLocalizations l10n,
) => switch (error) {
  YouTubeLibraryError.authenticationFailed => l10n.youtubeAuthenticationFailed,
  YouTubeLibraryError.languageChangeFailed => l10n.unableToChangeAppLanguage,
  YouTubeLibraryError.loadFailed => l10n.unableToLoadYouTubeMusic,
  YouTubeLibraryError.actionFailed => l10n.unableToCompleteYouTubeMusicAction,
};
