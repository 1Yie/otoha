import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/youtube_library.dart';
import '../services/credential_store.dart';
import '../services/lyric_cache.dart';
import '../services/remote_metadata_cache.dart';
import '../services/youtube_sidecar_client.dart';

enum YouTubeAccountStatus { signedOut, restoring, authorizing, signedIn, error }

enum YouTubeLibraryError {
  authenticationFailed,
  languageChangeFailed,
  loadFailed,
  actionFailed,
}

class YouTubeLibraryController extends ChangeNotifier {
  YouTubeLibraryController({
    required YouTubeSidecarClient client,
    required CredentialStore credentialStore,
    Duration accountWriteCooldown = const Duration(seconds: 2),
    RemoteMetadataCache? metadataCache,
    LyricCache? lyricCache,
    String locale = 'en',
  }) : this._(
         client,
         credentialStore,
         accountWriteCooldown,
         metadataCache,
         lyricCache,
         _normalizeLocale(locale),
       );

  YouTubeLibraryController._(
    this._client,
    this._credentialStore,
    this._accountWriteCooldown,
    this._metadataCache,
    this._lyricCache,
    this._locale,
  ) {
    _eventSubscription = _client.events.listen(_handleEvent);
  }

  final YouTubeSidecarClient _client;
  final CredentialStore _credentialStore;
  final Duration _accountWriteCooldown;
  final RemoteMetadataCache? _metadataCache;
  final LyricCache? _lyricCache;
  String _locale;
  late final StreamSubscription<SidecarEvent> _eventSubscription;

  YouTubeAccountStatus _status = YouTubeAccountStatus.signedOut;
  List<YouTubePlaylist> _playlists = const <YouTubePlaylist>[];
  List<YouTubeTrack> _historyTracks = const <YouTubeTrack>[];
  YouTubePlaylistDetail? _selectedPlaylist;
  YouTubeFeedCollectionDetail? _selectedFeedCollection;
  YouTubeFeedBrowseDetail? _selectedFeedBrowse;
  List<YouTubeFeedSection> _homeSections = const <YouTubeFeedSection>[];
  List<YouTubeFeedSection> _exploreSections = const <YouTubeFeedSection>[];
  List<YouTubeFeedItem> _exploreCategories = const <YouTubeFeedItem>[];
  String? _selectedExploreCategoryId;
  List<YouTubeFeedItem> _searchResults = const <YouTubeFeedItem>[];
  List<YouTubeLyricLine> _lyricsLines = const <YouTubeLyricLine>[];
  List<YouTubeComment> _comments = const <YouTubeComment>[];
  final Map<String, YouTubeRating> _ratings = <String, YouTubeRating>{};
  String? _lyricsVideoId;
  String? _commentsVideoId;
  bool _hasLoadedLyrics = false;
  YouTubeLibraryError? _errorMessage;
  YouTubeLibraryError? _historyErrorMessage;
  YouTubeLibraryError? _homeErrorMessage;
  YouTubeLibraryError? _exploreErrorMessage;
  YouTubeLibraryError? _feedActionErrorMessage;
  String? _loadingFeedItemId;
  bool _isLoadingLibrary = false;
  bool _isLoadingHistory = false;
  bool _hasLoadedHistory = false;
  bool _isLoadingPlaylist = false;
  bool _isLoadingHome = false;
  bool _isLoadingMoreHome = false;
  bool _hasMoreHome = false;
  bool _isLoadingExplore = false;
  bool _isLoadingMoreExplore = false;
  bool _hasMoreExplore = false;
  bool _isLoadingFeedBrowse = false;
  bool _isSearching = false;
  bool _isLoadingLyrics = false;
  int _searchRequest = 0;
  int _lyricsRequest = 0;
  String _searchQuery = '';
  YouTubeLibraryError? _searchErrorMessage;
  String? _profileName;
  String? _profileAvatarUrl;
  String? _ratingVideoId;
  YouTubeLibraryError? _commentErrorMessage;
  bool _isLoadingComments = false;
  bool _isPostingComment = false;
  DateTime? _accountWriteCooldownUntil;
  Timer? _accountWriteCooldownTimer;
  bool _isRecoveringSidecar = false;

  YouTubeAccountStatus get status => _status;
  List<YouTubePlaylist> get playlists => _playlists;
  List<YouTubeTrack> get historyTracks => _historyTracks;
  YouTubePlaylistDetail? get selectedPlaylist => _selectedPlaylist;
  YouTubeFeedCollectionDetail? get selectedFeedCollection =>
      _selectedFeedCollection;
  YouTubeFeedBrowseDetail? get selectedFeedBrowse => _selectedFeedBrowse;
  List<YouTubeFeedSection> get homeSections => _homeSections;
  List<YouTubeFeedSection> get exploreSections => _exploreSections;
  List<YouTubeFeedItem> get exploreCategories => _exploreCategories;
  String? get selectedExploreCategoryId => _selectedExploreCategoryId;
  List<YouTubeFeedItem> get searchResults => _searchResults;
  List<YouTubeLyricLine> get lyricsLines => _lyricsLines;
  List<YouTubeComment> get comments => _comments;
  String? get lyricsVideoId => _lyricsVideoId;
  String? get commentsVideoId => _commentsVideoId;
  YouTubeLibraryError? get errorMessage => _errorMessage;
  YouTubeLibraryError? get historyErrorMessage => _historyErrorMessage;
  YouTubeLibraryError? get homeErrorMessage => _homeErrorMessage;
  YouTubeLibraryError? get exploreErrorMessage => _exploreErrorMessage;
  YouTubeLibraryError? get feedActionErrorMessage => _feedActionErrorMessage;
  String? get loadingFeedItemId => _loadingFeedItemId;
  bool get isLoadingLibrary => _isLoadingLibrary;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasLoadedHistory => _hasLoadedHistory;
  bool get isLoadingPlaylist => _isLoadingPlaylist;
  bool get isLoadingHome => _isLoadingHome;
  bool get isLoadingMoreHome => _isLoadingMoreHome;
  bool get hasMoreHome => _hasMoreHome;
  bool get isLoadingExplore => _isLoadingExplore;
  bool get isLoadingMoreExplore => _isLoadingMoreExplore;
  bool get hasMoreExplore => _hasMoreExplore;
  bool get isLoadingFeedBrowse => _isLoadingFeedBrowse;
  bool get isSearching => _isSearching;
  bool get isLoadingLyrics => _isLoadingLyrics;
  bool get isLoadingComments => _isLoadingComments;
  bool get isPostingComment => _isPostingComment;
  bool get isRating => _ratingVideoId != null;
  bool get isAccountWriteCoolingDown =>
      _accountWriteCooldownUntil?.isAfter(DateTime.now()) ?? false;
  String get searchQuery => _searchQuery;
  YouTubeLibraryError? get searchErrorMessage => _searchErrorMessage;
  YouTubeLibraryError? get commentErrorMessage => _commentErrorMessage;
  String? get profileName => _profileName;
  String? get profileAvatarUrl => _profileAvatarUrl;
  bool get isSignedIn => _status == YouTubeAccountStatus.signedIn;
  String get locale => _locale;

  YouTubeRating ratingFor(String videoId) =>
      _ratings[videoId] ?? YouTubeRating.none;

  Future<void> initialize() async {
    _status = YouTubeAccountStatus.restoring;
    notifyListeners();
    try {
      final saved = await _credentialStore.read();
      if (saved == null) {
        _status = YouTubeAccountStatus.signedOut;
        notifyListeners();
        return;
      }
      final credential = SavedCredential.fromJson(
        (jsonDecode(saved)! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      if (credential.kind != 'cookie') {
        await _credentialStore.delete();
        _status = YouTubeAccountStatus.signedOut;
        notifyListeners();
        return;
      }
      final result = await _client.call('session.restore', <String, Object?>{
        'credential': credential.toJson(),
        'locale': _locale,
      });
      if (result['authenticated'] != true) {
        await _credentialStore.delete();
        _status = YouTubeAccountStatus.signedOut;
        notifyListeners();
        return;
      }
      _applyProfile(result);
      _status = YouTubeAccountStatus.signedIn;
      notifyListeners();
      await _syncAccountData();
    } on Object catch (error) {
      if (_isAuthenticationFailure(error)) {
        await _credentialStore.delete();
      }
      _setError(error);
    }
  }

  Future<void> signInWithCookie(String cookie) async {
    _status = YouTubeAccountStatus.authorizing;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('auth.cookie.signIn', <String, Object?>{
        'cookie': cookie,
        'locale': _locale,
      });
      _applyProfile(result);
      _status = YouTubeAccountStatus.signedIn;
      notifyListeners();
      await _syncAccountData();
    } on Object catch (error) {
      if (_isAuthenticationFailure(error)) {
        await _credentialStore.delete();
      }
      _setError(error);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.call('auth.signOut');
    } on Object {
      // Local sign-out still clears the sensitive credential and account data.
    }
    await _credentialStore.delete();
    await _metadataCache?.clear();
    _status = YouTubeAccountStatus.signedOut;
    _playlists = const <YouTubePlaylist>[];
    _historyTracks = const <YouTubeTrack>[];
    _selectedPlaylist = null;
    _selectedFeedCollection = null;
    _selectedFeedBrowse = null;
    _homeSections = const <YouTubeFeedSection>[];
    _isLoadingMoreHome = false;
    _hasMoreHome = false;
    _exploreSections = const <YouTubeFeedSection>[];
    _exploreCategories = const <YouTubeFeedItem>[];
    _selectedExploreCategoryId = null;
    _isLoadingMoreExplore = false;
    _hasMoreExplore = false;
    _searchResults = const <YouTubeFeedItem>[];
    _lyricsLines = const <YouTubeLyricLine>[];
    _comments = const <YouTubeComment>[];
    _ratings.clear();
    _lyricsVideoId = null;
    _commentsVideoId = null;
    _hasLoadedLyrics = false;
    _searchQuery = '';
    _searchErrorMessage = null;
    _isSearching = false;
    _isLoadingHistory = false;
    _hasLoadedHistory = false;
    _isLoadingLyrics = false;
    _isLoadingComments = false;
    _isPostingComment = false;
    _accountWriteCooldownUntil = null;
    _accountWriteCooldownTimer?.cancel();
    _accountWriteCooldownTimer = null;
    _searchRequest += 1;
    _lyricsRequest += 1;
    _errorMessage = null;
    _historyErrorMessage = null;
    _homeErrorMessage = null;
    _exploreErrorMessage = null;
    _feedActionErrorMessage = null;
    _profileName = null;
    _profileAvatarUrl = null;
    _ratingVideoId = null;
    _commentErrorMessage = null;
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    final normalizedLocale = _normalizeLocale(locale);
    if (_locale == normalizedLocale) {
      return;
    }
    _locale = normalizedLocale;
    if (!isSignedIn) {
      return;
    }
    try {
      await _client.call('session.setLocale', <String, Object?>{
        'locale': _locale,
      });
      await _metadataCache?.clear();
      _selectedPlaylist = null;
      _selectedFeedCollection = null;
      _selectedFeedBrowse = null;
      _historyTracks = const <YouTubeTrack>[];
      _hasLoadedHistory = false;
      _homeSections = const <YouTubeFeedSection>[];
      _exploreSections = const <YouTubeFeedSection>[];
      _exploreCategories = const <YouTubeFeedItem>[];
      _selectedExploreCategoryId = null;
      _hasMoreHome = false;
      _hasMoreExplore = false;
      notifyListeners();
      await _syncAccountData();
    } on Object {
      _errorMessage = YouTubeLibraryError.languageChangeFailed;
      notifyListeners();
    }
  }

  Future<void> loadPlaylists() async {
    if (!isSignedIn || _isLoadingLibrary) {
      return;
    }
    _isLoadingLibrary = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final cached = await _metadataCache?.read('library.playlists');
      if (cached != null) {
        _applyPlaylists(cached.data);
        notifyListeners();
        if (cached.isFresh(const Duration(minutes: 10))) {
          return;
        }
      }
      final result = await _client.call('library.playlists');
      _applyPlaylists(result);
      await _metadataCache?.write('library.playlists', result);
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingLibrary = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory({bool forceRefresh = false}) async {
    if (!isSignedIn ||
        _isLoadingHistory ||
        (_hasLoadedHistory && !forceRefresh)) {
      return;
    }
    _isLoadingHistory = true;
    _historyErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('history.get');
      _historyTracks = (result['tracks']! as List<Object?>)
          .map(
            (track) => YouTubeTrack.fromJson(
              (track! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
      _hasLoadedHistory = true;
    } on Object catch (error) {
      _historyErrorMessage = _requestErrorFor(error);
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> openPlaylist(YouTubePlaylist playlist) async {
    _isLoadingPlaylist = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final key = 'library.playlist:${playlist.id}';
      final cached = await _metadataCache?.read(key);
      if (cached != null) {
        _selectedPlaylist = YouTubePlaylistDetail.fromJson(cached.data);
        notifyListeners();
        if (cached.isFresh(const Duration(hours: 1))) {
          return;
        }
      }
      final result = await _client.call('library.playlist', <String, Object?>{
        'playlistId': playlist.id,
      });
      _selectedPlaylist = YouTubePlaylistDetail.fromJson(result);
      await _metadataCache?.write(key, result);
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingPlaylist = false;
      notifyListeners();
    }
  }

  Future<void> loadHome({bool forceRefresh = false}) async {
    if (!isSignedIn || _isLoadingHome) {
      return;
    }
    _isLoadingHome = true;
    _homeErrorMessage = null;
    notifyListeners();
    try {
      final cached = forceRefresh
          ? null
          : await _metadataCache?.read('feed.home');
      if (cached != null) {
        _homeSections = _decodeFeedSections(cached.data);
        _hasMoreHome = false;
        notifyListeners();
        if (cached.isFresh(const Duration(minutes: 10))) {
          return;
        }
      }
      final result = await _client.call('feed.home');
      _homeSections = _decodeFeedSections(result);
      _hasMoreHome = result['hasMore'] == true;
      await _metadataCache?.write('feed.home', result);
    } on Object catch (error) {
      _homeErrorMessage = _requestErrorFor(error);
      _hasMoreHome = false;
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHome() async {
    if (!isSignedIn || !_hasMoreHome || _isLoadingHome || _isLoadingMoreHome) {
      return;
    }
    _isLoadingMoreHome = true;
    _homeErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.home.more');
      _homeSections = _mergeFeedSections(
        _homeSections,
        _decodeFeedSections(result),
      );
      _hasMoreHome = result['hasMore'] == true;
    } on Object catch (error) {
      _homeErrorMessage = _requestErrorFor(error);
    } finally {
      _isLoadingMoreHome = false;
      notifyListeners();
    }
  }

  Future<void> loadExplore({bool forceRefresh = false}) async {
    if (!isSignedIn || _isLoadingExplore) {
      return;
    }
    _isLoadingExplore = true;
    _hasMoreExplore = false;
    _exploreErrorMessage = null;
    notifyListeners();
    try {
      final cached = forceRefresh
          ? null
          : await _metadataCache?.read('feed.explore');
      if (cached != null) {
        _applyExploreSections(_decodeFeedSections(cached.data));
        notifyListeners();
        if (cached.isFresh(const Duration(hours: 6))) {
          return;
        }
      }
      final result = await _client.call('feed.explore');
      _applyExploreSections(_decodeFeedSections(result));
      _hasMoreExplore = result['hasMore'] == true;
      await _metadataCache?.write('feed.explore', result);
    } on Object catch (error) {
      _exploreErrorMessage = _requestErrorFor(error);
      _hasMoreExplore = false;
    } finally {
      _isLoadingExplore = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreExplore() async {
    if (!isSignedIn ||
        !_hasMoreExplore ||
        _isLoadingExplore ||
        _isLoadingMoreExplore) {
      return;
    }
    _isLoadingMoreExplore = true;
    _exploreErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.explore.more');
      _exploreSections = _mergeFeedSections(
        _exploreSections,
        _withoutExploreCategories(_decodeFeedSections(result)),
      );
      _hasMoreExplore = result['hasMore'] == true;
    } on Object catch (error) {
      _exploreErrorMessage = _requestErrorFor(error);
    } finally {
      _isLoadingMoreExplore = false;
      notifyListeners();
    }
  }

  Future<void> searchMusic(String query) async {
    final normalizedQuery = query.trim();
    final request = ++_searchRequest;
    _searchQuery = normalizedQuery;
    _searchErrorMessage = null;
    if (!isSignedIn || normalizedQuery.isEmpty) {
      _searchResults = const <YouTubeFeedItem>[];
      _isSearching = false;
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    try {
      final result = await _client.call('search.music', <String, Object?>{
        'query': normalizedQuery,
      });
      if (request != _searchRequest) {
        return;
      }
      _searchResults = (result['items']! as List<Object?>)
          .map(
            (item) => YouTubeFeedItem.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on Object catch (error) {
      if (request == _searchRequest) {
        _searchResults = const <YouTubeFeedItem>[];
        _searchErrorMessage = _requestErrorFor(error);
      }
    } finally {
      if (request == _searchRequest) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  void clearSearchResults() {
    _searchRequest += 1;
    if (_searchQuery.isEmpty && _searchResults.isEmpty && !_isSearching) {
      return;
    }
    _searchQuery = '';
    _searchResults = const <YouTubeFeedItem>[];
    _searchErrorMessage = null;
    _isSearching = false;
    notifyListeners();
  }

  Future<List<YouTubeTrack>> loadFeedCollection(YouTubeFeedItem item) async {
    if (!item.isCollection) {
      return const <YouTubeTrack>[];
    }
    _loadingFeedItemId = item.id;
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.collection', <String, Object?>{
        'itemType': item.itemType,
        'id': item.id,
      });
      return (result['tracks']! as List<Object?>)
          .map(
            (track) => YouTubeTrack.fromJson(
              (track! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
      return const <YouTubeTrack>[];
    } finally {
      _loadingFeedItemId = null;
      notifyListeners();
    }
  }

  Future<List<YouTubeTrack>> openFeedCollection(
    YouTubeFeedItem item, {
    required String source,
  }) async {
    final tracks = await loadFeedCollection(item);
    if (tracks.isEmpty) {
      return tracks;
    }
    if (tracks.length == 1) {
      return tracks;
    }
    _selectedFeedCollection = YouTubeFeedCollectionDetail(
      source: source,
      title: item.title,
      itemType: item.itemType,
      tracks: tracks,
      artists: item.artists,
      thumbnailUrl: item.thumbnailUrl,
    );
    notifyListeners();
    return tracks;
  }

  Future<YouTubeTrack> resolveFeedTrack(YouTubeFeedItem item) async {
    final fallback = YouTubeTrack(
      videoId: item.videoId!,
      title: item.title,
      artists: item.artists,
      durationSeconds: item.durationSeconds,
      album: item.album,
      thumbnailUrl: item.thumbnailUrl,
    );
    if (item.durationSeconds > 0) {
      return fallback;
    }

    _loadingFeedItemId = item.id;
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.track', <String, Object?>{
        'videoId': item.videoId,
      });
      final track = YouTubeTrack.fromJson(
        (result['track']! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      return YouTubeTrack(
        videoId: track.videoId,
        title: track.title,
        artists: track.artists.isEmpty ? item.artists : track.artists,
        durationSeconds: track.durationSeconds,
        album: item.album,
        thumbnailUrl: track.thumbnailUrl ?? item.thumbnailUrl,
      );
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
      return fallback;
    } finally {
      _loadingFeedItemId = null;
      notifyListeners();
    }
  }

  Future<void> loadLyrics({
    required String videoId,
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    if (!isSignedIn || videoId.isEmpty) {
      return;
    }
    if (_lyricsVideoId == videoId && (_isLoadingLyrics || _hasLoadedLyrics)) {
      return;
    }

    final request = ++_lyricsRequest;
    _lyricsVideoId = videoId;
    _lyricsLines = const <YouTubeLyricLine>[];
    _hasLoadedLyrics = false;
    _isLoadingLyrics = true;
    notifyListeners();
    try {
      List<YouTubeLyricLine>? cachedLyrics;
      try {
        cachedLyrics = await _lyricCache?.read(videoId);
      } on Object {
        cachedLyrics = null;
      }
      if (request != _lyricsRequest) {
        return;
      }
      if (_hasTimedLyrics(cachedLyrics)) {
        _lyricsLines = cachedLyrics!;
        _hasLoadedLyrics = true;
        return;
      }
      final result = await _client.call('lyrics.get', <String, Object?>{
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationSeconds': durationSeconds,
      });
      if (request != _lyricsRequest) {
        return;
      }
      final lines = (result['lines']! as List<Object?>)
          .map(
            (line) => YouTubeLyricLine.fromJson(
              (line! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
      final hasTimedLyrics = _hasTimedLyrics(lines);
      _lyricsLines = hasTimedLyrics || result['source'] == 'youtube_music'
          ? lines
          : const <YouTubeLyricLine>[];
      _hasLoadedLyrics = true;
      final lyricCache = _lyricCache;
      if (lyricCache != null && hasTimedLyrics) {
        unawaited(lyricCache.write(videoId, _lyricsLines));
      }
    } on Object {
      if (request == _lyricsRequest) {
        _lyricsLines = const <YouTubeLyricLine>[];
      }
    } finally {
      if (request == _lyricsRequest) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  bool _hasTimedLyrics(List<YouTubeLyricLine>? lines) =>
      lines != null &&
      lines.isNotEmpty &&
      lines.every((line) => line.startSeconds != null);

  Future<Map<String, Object?>> downloadAudio({
    required String videoId,
    required String directory,
  }) async {
    if (!isSignedIn || videoId.isEmpty) {
      throw const SidecarException('AUTHENTICATION_REQUIRED', '');
    }
    return _client.call('download.track', <String, Object?>{
      'videoId': videoId,
      'directory': directory,
    });
  }

  Future<void> rateVideo(String videoId, YouTubeRating rating) async {
    if (!isSignedIn ||
        videoId.isEmpty ||
        _ratingVideoId != null ||
        isAccountWriteCoolingDown) {
      return;
    }
    _ratingVideoId = videoId;
    _beginAccountWriteCooldown();
    _commentErrorMessage = null;
    notifyListeners();
    try {
      await _client.call('interaction.rate', <String, Object?>{
        'videoId': videoId,
        'rating': rating.protocolValue,
      });
      _ratings[videoId] = rating;
    } on Object {
      _commentErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _ratingVideoId = null;
      notifyListeners();
    }
  }

  Future<void> loadComments(String videoId, {bool force = false}) async {
    if (!isSignedIn || videoId.isEmpty || _isLoadingComments) {
      return;
    }
    if (!force && _commentsVideoId == videoId) {
      return;
    }
    _commentsVideoId = videoId;
    _comments = const <YouTubeComment>[];
    _commentErrorMessage = null;
    _isLoadingComments = true;
    notifyListeners();
    try {
      final result = await _client.call('comments.get', <String, Object?>{
        'videoId': videoId,
      });
      if (_commentsVideoId != videoId) {
        return;
      }
      _comments = (result['comments']! as List<Object?>)
          .map(
            (comment) => YouTubeComment.fromJson(
              (comment! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on Object catch (error) {
      if (_commentsVideoId == videoId) {
        _commentErrorMessage = _requestErrorFor(error);
      }
    } finally {
      if (_commentsVideoId == videoId) {
        _isLoadingComments = false;
        notifyListeners();
      }
    }
  }

  Future<bool> postComment(String videoId, String text) async {
    final comment = text.trim();
    if (!isSignedIn ||
        videoId.isEmpty ||
        comment.isEmpty ||
        _isPostingComment ||
        isAccountWriteCoolingDown) {
      return false;
    }
    _isPostingComment = true;
    _beginAccountWriteCooldown();
    _commentErrorMessage = null;
    notifyListeners();
    try {
      await _client.call('comments.create', <String, Object?>{
        'videoId': videoId,
        'text': comment,
      });
      await loadComments(videoId, force: true);
      return true;
    } on Object {
      _commentErrorMessage = YouTubeLibraryError.actionFailed;
      return false;
    } finally {
      _isPostingComment = false;
      notifyListeners();
    }
  }

  Future<void> openFeedBrowse(
    YouTubeFeedItem item, {
    required String source,
  }) async {
    if (!item.isBrowsable || _isLoadingFeedBrowse) {
      return;
    }
    _loadingFeedItemId = item.id;
    _isLoadingFeedBrowse = true;
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.browse', <String, Object?>{
        'itemType': item.itemType,
        'id': item.id,
        if (item.browseParams != null) 'browseParams': item.browseParams,
      });
      _selectedFeedCollection = null;
      final sections = _decodeFeedSections(result);
      if (source == 'explore') {
        _selectedFeedBrowse = null;
        _exploreSections = _withoutExploreCategories(sections);
        _hasMoreExplore = false;
        if (item.itemType == 'category') {
          _selectedExploreCategoryId = item.browseIdentity;
        }
      } else {
        _selectedFeedBrowse = YouTubeFeedBrowseDetail(
          source: source,
          title: item.title,
          sections: sections,
        );
      }
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _loadingFeedItemId = null;
      _isLoadingFeedBrowse = false;
      notifyListeners();
    }
  }

  void closeFeedDetail() {
    if (_selectedFeedCollection != null) {
      _selectedFeedCollection = null;
    } else if (_selectedFeedBrowse != null) {
      _selectedFeedBrowse = null;
    } else {
      return;
    }
    notifyListeners();
  }

  void closePlaylist() {
    if (_selectedPlaylist == null) {
      return;
    }
    _selectedPlaylist = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_status == YouTubeAccountStatus.error) {
      _status = YouTubeAccountStatus.signedOut;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _accountWriteCooldownTimer?.cancel();
    unawaited(_eventSubscription.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }

  Future<void> _handleEvent(SidecarEvent event) async {
    switch (event.name) {
      case 'auth.credentials':
        final credential = SavedCredential.fromJson(
          (event.data['credential']! as Map<Object?, Object?>)
              .cast<String, Object?>(),
        );
        await _credentialStore.write(jsonEncode(credential.toJson()));
        _status = YouTubeAccountStatus.signedIn;
        _errorMessage = null;
        notifyListeners();
      case 'auth.error':
        _errorMessage = YouTubeLibraryError.authenticationFailed;
        _status = YouTubeAccountStatus.error;
        notifyListeners();
      case 'sidecar.exit':
        unawaited(_recoverAfterSidecarExit());
    }
  }

  Future<void> _recoverAfterSidecarExit() async {
    if (_isRecoveringSidecar || !isSignedIn) {
      return;
    }
    _isRecoveringSidecar = true;
    _status = YouTubeAccountStatus.restoring;
    notifyListeners();
    try {
      final saved = await _credentialStore.read();
      if (saved == null) {
        _status = YouTubeAccountStatus.signedOut;
        notifyListeners();
        return;
      }
      final credential = SavedCredential.fromJson(
        (jsonDecode(saved)! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      if (credential.kind != 'cookie') {
        _status = YouTubeAccountStatus.signedOut;
        notifyListeners();
        return;
      }
      final result = await _client.call('session.restore', <String, Object?>{
        'credential': credential.toJson(),
        'locale': _locale,
      });
      if (result['authenticated'] != true) {
        throw const SidecarException('AUTHENTICATION_REQUIRED', '');
      }
      _applyProfile(result);
      _status = YouTubeAccountStatus.signedIn;
      _errorMessage = null;
      notifyListeners();
      await _syncAccountData();
    } on Object catch (error) {
      if (_isAuthenticationFailure(error)) {
        await _credentialStore.delete();
      }
      _setError(error);
    } finally {
      _isRecoveringSidecar = false;
    }
  }

  Future<void> _syncAccountData() async {
    await Future.wait(<Future<void>>[
      loadPlaylists(),
      loadHome(),
      loadExplore(),
    ]);
  }

  static String _normalizeLocale(String locale) =>
      locale.toLowerCase().startsWith('zh') ? 'zh-CN' : 'en';

  List<YouTubeFeedSection> _decodeFeedSections(Map<String, Object?> result) {
    return (result['sections']! as List<Object?>)
        .map(
          (item) => YouTubeFeedSection.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  void _applyPlaylists(Map<String, Object?> result) {
    _playlists = (result['playlists']! as List<Object?>)
        .map(
          (item) => YouTubePlaylist.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  void _applyExploreSections(List<YouTubeFeedSection> sections) {
    _exploreCategories = _extractExploreCategories(sections);
    _exploreSections = _withoutExploreCategories(sections);
    _selectedExploreCategoryId = null;
  }

  List<YouTubeFeedSection> _mergeFeedSections(
    List<YouTubeFeedSection> existing,
    List<YouTubeFeedSection> appended,
  ) {
    final merged = <YouTubeFeedSection>[...existing];
    for (final section in appended) {
      final index = merged.indexWhere((entry) => entry.title == section.title);
      if (index < 0) {
        merged.add(section);
        continue;
      }
      final current = merged[index];
      final seen = <String>{
        for (final item in current.items) '${item.itemType}:${item.id}',
      };
      final items = <YouTubeFeedItem>[...current.items];
      for (final item in section.items) {
        if (seen.add('${item.itemType}:${item.id}')) {
          items.add(item);
        }
      }
      merged[index] = YouTubeFeedSection(title: current.title, items: items);
    }
    return List<YouTubeFeedSection>.unmodifiable(merged);
  }

  List<YouTubeFeedItem> _extractExploreCategories(
    List<YouTubeFeedSection> sections,
  ) {
    final categories = <YouTubeFeedItem>[];
    final seen = <String>{};
    for (final section in sections) {
      for (final item in section.items) {
        if (item.itemType == 'category' && seen.add(item.browseIdentity)) {
          categories.add(item);
        }
      }
    }
    return List<YouTubeFeedItem>.unmodifiable(categories);
  }

  List<YouTubeFeedSection> _withoutExploreCategories(
    List<YouTubeFeedSection> sections,
  ) {
    return sections
        .map((section) {
          final items = section.items
              .where((item) => item.itemType != 'category')
              .toList(growable: false);
          return items.isEmpty
              ? null
              : YouTubeFeedSection(title: section.title, items: items);
        })
        .whereType<YouTubeFeedSection>()
        .toList(growable: false);
  }

  void _applyProfile(Map<String, Object?> result) {
    final profile = result['profile'];
    if (profile is! Map<Object?, Object?>) {
      return;
    }
    _profileName = profile['displayName'] as String?;
    _profileAvatarUrl = profile['avatarUrl'] as String?;
  }

  void _beginAccountWriteCooldown() {
    if (_accountWriteCooldown <= Duration.zero) {
      return;
    }
    _accountWriteCooldownUntil = DateTime.now().add(_accountWriteCooldown);
    _accountWriteCooldownTimer?.cancel();
    _accountWriteCooldownTimer = Timer(_accountWriteCooldown, () {
      _accountWriteCooldownUntil = null;
      notifyListeners();
    });
  }

  YouTubeLibraryError _requestErrorFor(Object error) =>
      _isAuthenticationFailure(error)
      ? YouTubeLibraryError.authenticationFailed
      : YouTubeLibraryError.loadFailed;

  bool _isAuthenticationFailure(Object error) =>
      error is SidecarException &&
      const <String>{
        'INVALID_COOKIE',
        'INVALID_CREDENTIAL',
        'AUTH_REQUIRED',
        'AUTHENTICATION_REQUIRED',
        'AUTHENTICATION_FAILED',
      }.contains(error.code);

  void _setError(Object error, {bool preserveSignedIn = false}) {
    _errorMessage = _requestErrorFor(error);
    if (!preserveSignedIn) {
      _status = YouTubeAccountStatus.error;
    }
    notifyListeners();
  }
}
