import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Otoha'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @desktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get desktop;

  /// No description provided for @motion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get motion;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @outputDevice.
  ///
  /// In en, this message translates to:
  /// **'Output device'**
  String get outputDevice;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @noTrackSelected.
  ///
  /// In en, this message translates to:
  /// **'No track selected'**
  String get noTrackSelected;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'The queue is empty.'**
  String get queueEmpty;

  /// No description provided for @youtubeMusic.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music'**
  String get youtubeMusic;

  /// No description provided for @closePanel.
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get closePanel;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @outputUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get outputUnavailable;

  /// No description provided for @noAudioOutputDevices.
  ///
  /// In en, this message translates to:
  /// **'No audio output devices are available.'**
  String get noAudioOutputDevices;

  /// No description provided for @changeOutputDeviceError.
  ///
  /// In en, this message translates to:
  /// **'Unable to change the audio output device.'**
  String get changeOutputDeviceError;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @yourSpace.
  ///
  /// In en, this message translates to:
  /// **'YOUR SPACE'**
  String get yourSpace;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximize;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchYourMusic.
  ///
  /// In en, this message translates to:
  /// **'Search your music'**
  String get searchYourMusic;

  /// No description provided for @searchShortcut.
  ///
  /// In en, this message translates to:
  /// **'Search (Ctrl/Cmd + K)'**
  String get searchShortcut;

  /// No description provided for @searchSongsArtistsAlbumsOrCommands.
  ///
  /// In en, this message translates to:
  /// **'Search songs, artists, albums, or commands'**
  String get searchSongsArtistsAlbumsOrCommands;

  /// No description provided for @noYouTubeMusicMatches.
  ///
  /// In en, this message translates to:
  /// **'No YouTube Music matches'**
  String get noYouTubeMusicMatches;

  /// No description provided for @noLocalMatches.
  ///
  /// In en, this message translates to:
  /// **'No local matches'**
  String get noLocalMatches;

  /// No description provided for @openWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get openWorkspace;

  /// No description provided for @command.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get command;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @openFullLyrics.
  ///
  /// In en, this message translates to:
  /// **'Open full lyrics'**
  String get openFullLyrics;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @repeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat off'**
  String get repeatOff;

  /// No description provided for @repeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat all'**
  String get repeatAll;

  /// No description provided for @repeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat one'**
  String get repeatOne;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @volumePercentage.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String volumePercentage(int value);

  /// No description provided for @outputDeviceWithValue.
  ///
  /// In en, this message translates to:
  /// **'{device}: {value}'**
  String outputDeviceWithValue(Object device, Object value);

  /// No description provided for @unknownDuration.
  ///
  /// In en, this message translates to:
  /// **'--:--'**
  String get unknownDuration;

  /// No description provided for @signInToYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Sign in to YouTube Music'**
  String get signInToYouTubeMusic;

  /// No description provided for @youtubeMusicSignIn.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music sign-in'**
  String get youtubeMusicSignIn;

  /// No description provided for @youtubeCookieHeader.
  ///
  /// In en, this message translates to:
  /// **'YouTube Cookie header'**
  String get youtubeCookieHeader;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @syncLibrary.
  ///
  /// In en, this message translates to:
  /// **'Sync library'**
  String get syncLibrary;

  /// No description provided for @fullYouTubeMusicSession.
  ///
  /// In en, this message translates to:
  /// **'Full YouTube Music session'**
  String get fullYouTubeMusicSession;

  /// No description provided for @playlistCount.
  ///
  /// In en, this message translates to:
  /// **'{count} playlists'**
  String playlistCount(int count);

  /// No description provided for @yourLibrary.
  ///
  /// In en, this message translates to:
  /// **'YOUR LIBRARY'**
  String get yourLibrary;

  /// No description provided for @yourPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get yourPlaylists;

  /// No description provided for @noPlaylistsFound.
  ///
  /// In en, this message translates to:
  /// **'No playlists found'**
  String get noPlaylistsFound;

  /// No description provided for @backToPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Back to playlists'**
  String get backToPlaylists;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'PLAYLIST'**
  String get playlist;

  /// No description provided for @tracksCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String tracksCount(int count);

  /// No description provided for @yourActivity.
  ///
  /// In en, this message translates to:
  /// **'YOUR ACTIVITY'**
  String get yourActivity;

  /// No description provided for @refreshHistory.
  ///
  /// In en, this message translates to:
  /// **'Refresh history'**
  String get refreshHistory;

  /// No description provided for @loadHistoryAgain.
  ///
  /// In en, this message translates to:
  /// **'Load history again'**
  String get loadHistoryAgain;

  /// No description provided for @noPlaybackHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No playback history found.'**
  String get noPlaybackHistoryFound;

  /// No description provided for @forYourAccount.
  ///
  /// In en, this message translates to:
  /// **'FOR YOUR ACCOUNT'**
  String get forYourAccount;

  /// No description provided for @refreshSection.
  ///
  /// In en, this message translates to:
  /// **'Refresh {section}'**
  String refreshSection(Object section);

  /// No description provided for @loadAgain.
  ///
  /// In en, this message translates to:
  /// **'Load again'**
  String get loadAgain;

  /// No description provided for @forYou.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get forYou;

  /// No description provided for @scrollMoodsGenresLeft.
  ///
  /// In en, this message translates to:
  /// **'Scroll moods and genres left'**
  String get scrollMoodsGenresLeft;

  /// No description provided for @scrollMoodsGenresRight.
  ///
  /// In en, this message translates to:
  /// **'Scroll moods and genres right'**
  String get scrollMoodsGenresRight;

  /// No description provided for @scrollSectionLeft.
  ///
  /// In en, this message translates to:
  /// **'Scroll {section} left'**
  String scrollSectionLeft(Object section);

  /// No description provided for @scrollSectionRight.
  ///
  /// In en, this message translates to:
  /// **'Scroll {section} right'**
  String scrollSectionRight(Object section);

  /// No description provided for @album.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get album;

  /// No description provided for @artist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artist;

  /// No description provided for @moodAndGenre.
  ///
  /// In en, this message translates to:
  /// **'Mood & genre'**
  String get moodAndGenre;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @song.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get song;

  /// No description provided for @musicVideo.
  ///
  /// In en, this message translates to:
  /// **'Music video'**
  String get musicVideo;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @closeFullLyrics.
  ///
  /// In en, this message translates to:
  /// **'Close full lyrics'**
  String get closeFullLyrics;

  /// No description provided for @previousTrack.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get previousTrack;

  /// No description provided for @nextTrack.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get nextTrack;

  /// No description provided for @playbackProgress.
  ///
  /// In en, this message translates to:
  /// **'Playback progress'**
  String get playbackProgress;

  /// No description provided for @lyricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Lyrics are not available.'**
  String get lyricsUnavailable;

  /// No description provided for @lyricsUnavailableForTrack.
  ///
  /// In en, this message translates to:
  /// **'Lyrics are not available for this track.'**
  String get lyricsUnavailableForTrack;

  /// No description provided for @artwork.
  ///
  /// In en, this message translates to:
  /// **'{title} artwork'**
  String artwork(Object title);

  /// No description provided for @profileImage.
  ///
  /// In en, this message translates to:
  /// **'{title} profile image'**
  String profileImage(Object title);

  /// No description provided for @backgroundArtwork.
  ///
  /// In en, this message translates to:
  /// **'{title} background artwork'**
  String backgroundArtwork(Object title);

  /// No description provided for @moodAndGenreLabel.
  ///
  /// In en, this message translates to:
  /// **'{title} mood and genre'**
  String moodAndGenreLabel(Object title);

  /// No description provided for @unableToChangeAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'Unable to change the app language.'**
  String get unableToChangeAppLanguage;

  /// No description provided for @youtubeAuthenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'YouTube authentication failed.'**
  String get youtubeAuthenticationFailed;

  /// No description provided for @unableToLoadYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Unable to load YouTube Music data.'**
  String get unableToLoadYouTubeMusic;

  /// No description provided for @unableToCompleteYouTubeMusicAction.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete the YouTube Music action.'**
  String get unableToCompleteYouTubeMusicAction;

  /// No description provided for @audioEngineCouldNotPlay.
  ///
  /// In en, this message translates to:
  /// **'The audio engine could not play this track.'**
  String get audioEngineCouldNotPlay;

  /// No description provided for @audioStreamUnavailable.
  ///
  /// In en, this message translates to:
  /// **'YouTube did not provide an audio stream for this track.'**
  String get audioStreamUnavailable;

  /// No description provided for @unableToStartAudioPlayback.
  ///
  /// In en, this message translates to:
  /// **'Unable to start audio playback for this track.'**
  String get unableToStartAudioPlayback;

  /// No description provided for @showWindow.
  ///
  /// In en, this message translates to:
  /// **'Show window'**
  String get showWindow;

  /// No description provided for @quitApplication.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get quitApplication;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @versionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Version unavailable'**
  String get versionUnavailable;

  /// No description provided for @downloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Download location'**
  String get downloadLocation;

  /// No description provided for @saveDownloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Save download location'**
  String get saveDownloadLocation;

  /// No description provided for @downloadCurrentTrack.
  ///
  /// In en, this message translates to:
  /// **'Download current track'**
  String get downloadCurrentTrack;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @noDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet.'**
  String get noDownloads;

  /// No description provided for @deleteDownload.
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get deleteDownload;

  /// No description provided for @deleteDownloadConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete {title} from Downloads? The local file and its references in offline playlists will be removed.'**
  String deleteDownloadConfirmation(String title);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @shortcutTooltip.
  ///
  /// In en, this message translates to:
  /// **'{action} ({shortcut})'**
  String shortcutTooltip(String action, String shortcut);

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @createPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create playlist'**
  String get createPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this playlist? Downloaded songs will remain available.'**
  String get deletePlaylistConfirmation;

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get renamePlaylist;

  /// No description provided for @choosePlaylistCover.
  ///
  /// In en, this message translates to:
  /// **'Choose playlist cover'**
  String get choosePlaylistCover;

  /// No description provided for @noOfflinePlaylists.
  ///
  /// In en, this message translates to:
  /// **'No offline playlists yet.'**
  String get noOfflinePlaylists;

  /// No description provided for @noDownloadedTracksInPlaylist.
  ///
  /// In en, this message translates to:
  /// **'No downloaded tracks in this playlist.'**
  String get noDownloadedTracksInPlaylist;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
