// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Otoha';

  @override
  String get settings => 'Settings';

  @override
  String get desktop => 'Desktop';

  @override
  String get motion => 'Motion';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get outputDevice => 'Output device';

  @override
  String get queue => 'Queue';

  @override
  String get noTrackSelected => 'No track selected';

  @override
  String get queueEmpty => 'The queue is empty.';

  @override
  String get youtubeMusic => 'YouTube Music';

  @override
  String get closePanel => 'Close panel';

  @override
  String get systemDefault => 'System default';

  @override
  String get outputUnavailable => 'Unavailable';

  @override
  String get noAudioOutputDevices => 'No audio output devices are available.';

  @override
  String get changeOutputDeviceError =>
      'Unable to change the audio output device.';

  @override
  String get home => 'Home';

  @override
  String get explore => 'Explore';

  @override
  String get library => 'Media library';

  @override
  String get history => 'History';

  @override
  String get yourSpace => 'YOUR SPACE';

  @override
  String get downloads => 'Downloads';

  @override
  String get playlists => 'Playlists';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get profile => 'Profile';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get close => 'Close';

  @override
  String get search => 'Search';

  @override
  String get all => 'All';

  @override
  String get searchYourMusic => 'Search your music';

  @override
  String get searchShortcut => 'Search (Ctrl/Cmd + K)';

  @override
  String get searchSongsArtistsAlbumsOrCommands =>
      'Search songs, artists, albums, or commands';

  @override
  String get noYouTubeMusicMatches => 'No YouTube Music matches';

  @override
  String get noLocalMatches => 'No local matches';

  @override
  String get openWorkspace => 'Open workspace';

  @override
  String get command => 'Command';

  @override
  String get previous => 'Previous';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get next => 'Next';

  @override
  String get openFullLyrics => 'Open full lyrics';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get repeatOff => 'Repeat off';

  @override
  String get repeatAll => 'Repeat all';

  @override
  String get repeatOne => 'Repeat one';

  @override
  String get volume => 'Volume';

  @override
  String volumePercentage(int value) {
    return '$value%';
  }

  @override
  String outputDeviceWithValue(Object device, Object value) {
    return '$device: $value';
  }

  @override
  String get unknownDuration => '--:--';

  @override
  String get signInToYouTubeMusic => 'Sign in to YouTube Music';

  @override
  String get youtubeMusicSignIn => 'YouTube Music sign-in';

  @override
  String get youtubeCookieHeader => 'YouTube Cookie header';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get syncLibrary => 'Sync media library';

  @override
  String get fullYouTubeMusicSession => 'Full YouTube Music session';

  @override
  String playlistCount(int count) {
    return '$count playlists';
  }

  @override
  String get yourLibrary => 'YOUR LIBRARY';

  @override
  String get yourMediaLibrary => 'YOUR MEDIA LIBRARY';

  @override
  String get mediaLibrary => 'Media library';

  @override
  String get yourPlaylists => 'Your playlists';

  @override
  String get savedMusic => 'Saved music';

  @override
  String get podcasts => 'Podcasts';

  @override
  String get albums => 'Albums';

  @override
  String get saveToLibrary => 'Save to library';

  @override
  String get removeFromLibrary => 'Remove from library';

  @override
  String get savePodcastToLibrary => 'Save to library';

  @override
  String get removePodcastFromLibrary => 'Remove from library';

  @override
  String get followedArtists => 'Followed artists';

  @override
  String get follow => 'Follow';

  @override
  String get following => 'Following';

  @override
  String monthlyAudience(Object count) {
    return 'Monthly audience: $count';
  }

  @override
  String subscriberCount(Object count) {
    return 'Subscribers: $count';
  }

  @override
  String get saveEpisodeForLater => 'Save episode for later';

  @override
  String get episodeSavedForLater => 'Episode saved for later';

  @override
  String get noMediaFound => 'No media found';

  @override
  String get noPlaylistsFound => 'No playlists found';

  @override
  String get backToPlaylists => 'Back to playlists';

  @override
  String get playlist => 'PLAYLIST';

  @override
  String tracksCount(int count) {
    return '$count tracks';
  }

  @override
  String get yourActivity => 'YOUR ACTIVITY';

  @override
  String get refreshHistory => 'Refresh history';

  @override
  String get loadHistoryAgain => 'Load history again';

  @override
  String get noPlaybackHistoryFound => 'No playback history found.';

  @override
  String get forYourAccount => 'FOR YOUR ACCOUNT';

  @override
  String refreshSection(Object section) {
    return 'Refresh $section';
  }

  @override
  String get loadAgain => 'Load again';

  @override
  String get forYou => 'For you';

  @override
  String get scrollFeedFiltersLeft => 'Scroll filters left';

  @override
  String get scrollFeedFiltersRight => 'Scroll filters right';

  @override
  String scrollSectionLeft(Object section) {
    return 'Scroll $section left';
  }

  @override
  String scrollSectionRight(Object section) {
    return 'Scroll $section right';
  }

  @override
  String chartRank(int rank) {
    return 'Rank $rank';
  }

  @override
  String get chartTrendUp => 'Trending up';

  @override
  String get chartTrendDown => 'Trending down';

  @override
  String get chartTrendNeutral => 'No rank change';

  @override
  String get album => 'Album';

  @override
  String get artist => 'Artist';

  @override
  String get moodAndGenre => 'Mood & genre';

  @override
  String get episode => 'Episode';

  @override
  String get podcast => 'Podcast';

  @override
  String get podcastEpisodes => 'Episodes';

  @override
  String get noPodcastEpisodes => 'No episodes are available.';

  @override
  String get comments => 'Comments';

  @override
  String get noComments => 'No comments yet.';

  @override
  String get commentsUnavailable =>
      'Select a signed-in YouTube Music track to view comments.';

  @override
  String get writeComment => 'Write a comment';

  @override
  String get postComment => 'Post comment';

  @override
  String get like => 'Like';

  @override
  String get removeLike => 'Remove like';

  @override
  String get dislike => 'Dislike';

  @override
  String get removeDislike => 'Remove dislike';

  @override
  String get song => 'Song';

  @override
  String get musicVideo => 'Music video';

  @override
  String get genre => 'Genre';

  @override
  String get closeFullLyrics => 'Close full lyrics';

  @override
  String get openVideo => 'Open video';

  @override
  String get switchToVideo => 'Switch to video';

  @override
  String get switchToAudio => 'Switch to audio';

  @override
  String get collapseVideo => 'Collapse video';

  @override
  String get enterFullscreen => 'Enter fullscreen';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get videoEngineCouldNotPlay =>
      'The video engine could not play this video.';

  @override
  String get videoStreamUnavailable =>
      'YouTube did not provide a playable video stream.';

  @override
  String get unableToStartVideoPlayback => 'Unable to start video playback.';

  @override
  String get previousTrack => 'Previous track';

  @override
  String get nextTrack => 'Next track';

  @override
  String get playbackProgress => 'Playback progress';

  @override
  String get lyricsUnavailable => 'Lyrics are not available.';

  @override
  String get lyricsUnavailableForTrack =>
      'Lyrics are not available for this track.';

  @override
  String artwork(Object title) {
    return '$title artwork';
  }

  @override
  String profileImage(Object title) {
    return '$title profile image';
  }

  @override
  String backgroundArtwork(Object title) {
    return '$title background artwork';
  }

  @override
  String moodAndGenreLabel(Object title) {
    return '$title mood and genre';
  }

  @override
  String get unableToChangeAppLanguage => 'Unable to change the app language.';

  @override
  String get youtubeAuthenticationFailed =>
      'YouTube sign-in failed. Copy the current complete Cookie request header and try again.';

  @override
  String get unableToLoadYouTubeMusic => 'Unable to load YouTube Music data.';

  @override
  String get unableToCompleteYouTubeMusicAction =>
      'Unable to complete the YouTube Music action.';

  @override
  String get audioEngineCouldNotPlay =>
      'The audio engine could not play this track.';

  @override
  String get audioStreamUnavailable =>
      'YouTube did not provide an audio stream for this track.';

  @override
  String get unableToStartAudioPlayback =>
      'Unable to start audio playback for this track.';

  @override
  String get showWindow => 'Show window';

  @override
  String get quitApplication => 'Quit';

  @override
  String get about => 'About';

  @override
  String get licensesAndNotices => 'Licenses and notices';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get versionUnavailable => 'Version unavailable';

  @override
  String get downloadLocation => 'Download location';

  @override
  String get saveDownloadLocation => 'Save download location';

  @override
  String get downloadCurrentTrack => 'Download current track';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get noDownloads => 'No downloads yet.';

  @override
  String get deleteDownload => 'Delete download';

  @override
  String deleteDownloadConfirmation(String title) {
    return 'Delete $title from Downloads? The local file and its references in offline playlists will be removed.';
  }

  @override
  String get selectDownloads => 'Select downloads';

  @override
  String get exitDownloadSelection => 'Exit selection';

  @override
  String get selectAllDownloads => 'Select all downloads';

  @override
  String selectedDownloadsCount(int count) {
    return '$count selected';
  }

  @override
  String get addSelectedToPlaylist => 'Add selected to playlist';

  @override
  String get deleteSelectedDownloads => 'Delete selected downloads';

  @override
  String deleteSelectedDownloadsConfirmation(int count) {
    return 'Delete $count selected downloads? Their local files and references in offline playlists will be removed.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String shortcutTooltip(String action, String shortcut) {
    return '$action ($shortcut)';
  }

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get createPlaylist => 'Create playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get removeFromPlaylistConfirmation =>
      'Remove this song from the playlist? The downloaded file will remain available.';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get deletePlaylistConfirmation =>
      'Delete this playlist? Downloaded songs will remain available.';

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get choosePlaylistCover => 'Choose playlist cover';

  @override
  String get noOfflinePlaylists => 'No offline playlists yet.';

  @override
  String get noDownloadedTracksInPlaylist =>
      'No downloaded tracks in this playlist.';
}
