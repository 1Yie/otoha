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
  static const _mediaLibraryCacheKey = 'library.media.v4';

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
  List<YouTubePlaylist> _savedCollections = const <YouTubePlaylist>[];
  List<YouTubeFeedItem> _podcasts = const <YouTubeFeedItem>[];
  List<YouTubeFeedItem> _albums = const <YouTubeFeedItem>[];
  List<YouTubeFeedItem> _followedArtists = const <YouTubeFeedItem>[];
  List<YouTubeTrack> _historyTracks = const <YouTubeTrack>[];
  YouTubePlaylistDetail? _selectedPlaylist;
  YouTubeFeedCollectionDetail? _selectedFeedCollection;
  YouTubeFeedBrowseDetail? _selectedFeedBrowse;
  YouTubePodcastShowDetail? _selectedPodcastShow;
  List<YouTubeFeedSection> _homeSections = const <YouTubeFeedSection>[];
  List<String> _homeFilters = const <String>[];
  String? _selectedHomeFilter;
  List<YouTubeFeedSection> _exploreSections = const <YouTubeFeedSection>[];
  List<YouTubeFeedItem> _exploreCategories = const <YouTubeFeedItem>[];
  String? _selectedExploreCategoryId;
  List<YouTubeFeedItem> _searchResults = const <YouTubeFeedItem>[];
  List<YouTubeLyricLine> _lyricsLines = const <YouTubeLyricLine>[];
  List<YouTubeComment> _comments = const <YouTubeComment>[];
  final Map<String, YouTubeRating> _ratings = <String, YouTubeRating>{};
  final Set<String> _followingArtistIds = <String>{};
  final Set<String> _savedEpisodeVideoIds = <String>{};
  final Set<String> _podcastEpisodeVideoIds = <String>{};
  String? _lyricsVideoId;
  String? _commentsVideoId;
  bool _hasLoadedLyrics = false;
  YouTubeLibraryError? _errorMessage;
  YouTubeLibraryError? _historyErrorMessage;
  YouTubeLibraryError? _homeErrorMessage;
  YouTubeLibraryError? _exploreErrorMessage;
  YouTubeLibraryError? _feedActionErrorMessage;
  String? _loadingFeedItemId;
  String? _loadingPlaylistId;
  bool _isLoadingLibrary = false;
  bool _isLoadingHistory = false;
  bool _isLoadingMoreHistory = false;
  bool _hasLoadedHistory = false;
  bool _hasMoreHistory = false;
  bool _isLoadingPlaylist = false;
  bool _isLoadingMorePlaylist = false;
  bool _isLoadingHome = false;
  bool _isLoadingMoreHome = false;
  bool _hasMoreHome = false;
  bool _isHomeContinuationHydrated = false;
  bool _isLoadingExplore = false;
  bool _isLoadingMoreExplore = false;
  bool _hasMoreExplore = false;
  bool _isLoadingFeedBrowse = false;
  bool _isLoadingMorePodcast = false;
  bool _isSearching = false;
  bool _isLoadingLyrics = false;
  int _searchRequest = 0;
  int _lyricsRequest = 0;
  String _searchQuery = '';
  YouTubeMusicSearchFilter _searchFilter = YouTubeMusicSearchFilter.all;
  YouTubeLibraryError? _searchErrorMessage;
  String? _profileName;
  String? _profileAvatarUrl;
  String? _ratingVideoId;
  String? _followingArtistId;
  String? _savedEpisodeVideoId;
  String? _podcastLibraryWriteId;
  String? _albumLibraryWriteId;
  YouTubeLibraryError? _commentErrorMessage;
  String? _errorDiagnostic;
  bool _isLoadingComments = false;
  bool _isPostingComment = false;
  DateTime? _accountWriteCooldownUntil;
  Timer? _accountWriteCooldownTimer;
  bool _isRecoveringSidecar = false;

  YouTubeAccountStatus get status => _status;
  List<YouTubePlaylist> get playlists => _playlists;
  List<YouTubePlaylist> get savedCollections => _savedCollections;
  List<YouTubeFeedItem> get podcasts => _podcasts;
  List<YouTubeFeedItem> get albums => _albums;
  List<YouTubeFeedItem> get followedArtists => _followedArtists;
  List<YouTubeTrack> get historyTracks => _historyTracks;
  YouTubePlaylistDetail? get selectedPlaylist => _selectedPlaylist;
  YouTubeFeedCollectionDetail? get selectedFeedCollection =>
      _selectedFeedCollection;
  YouTubeFeedBrowseDetail? get selectedFeedBrowse => _selectedFeedBrowse;
  YouTubePodcastShowDetail? get selectedPodcastShow => _selectedPodcastShow;
  List<YouTubeFeedSection> get homeSections => _homeSections;
  List<String> get homeFilters => _homeFilters;
  String? get selectedHomeFilter => _selectedHomeFilter;
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
  String? get loadingPlaylistId => _loadingPlaylistId;
  bool get isLoadingLibrary => _isLoadingLibrary;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;
  bool get hasLoadedHistory => _hasLoadedHistory;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get isLoadingPlaylist => _isLoadingPlaylist;
  bool get isLoadingMorePlaylist => _isLoadingMorePlaylist;
  bool get isLoadingHome => _isLoadingHome;
  bool get isLoadingMoreHome => _isLoadingMoreHome;
  bool get hasMoreHome => _hasMoreHome;
  bool get isLoadingExplore => _isLoadingExplore;
  bool get isLoadingMoreExplore => _isLoadingMoreExplore;
  bool get hasMoreExplore => _hasMoreExplore;
  bool get isLoadingFeedBrowse => _isLoadingFeedBrowse;
  bool get isLoadingMorePodcast => _isLoadingMorePodcast;
  bool get isSearching => _isSearching;
  bool get isLoadingLyrics => _isLoadingLyrics;
  bool get isLoadingComments => _isLoadingComments;
  bool get isPostingComment => _isPostingComment;
  bool get isRating => _ratingVideoId != null;
  String? get followingArtistId => _followingArtistId;
  String? get savedEpisodeVideoId => _savedEpisodeVideoId;
  String? get podcastLibraryWriteId => _podcastLibraryWriteId;
  String? get albumLibraryWriteId => _albumLibraryWriteId;
  bool get isAccountWriteCoolingDown =>
      _accountWriteCooldownUntil?.isAfter(DateTime.now()) ?? false;
  String get searchQuery => _searchQuery;
  YouTubeMusicSearchFilter get searchFilter => _searchFilter;
  YouTubeLibraryError? get searchErrorMessage => _searchErrorMessage;
  YouTubeLibraryError? get commentErrorMessage => _commentErrorMessage;
  String? get errorDiagnostic => _errorDiagnostic;
  String? get profileName => _profileName;
  String? get profileAvatarUrl => _profileAvatarUrl;
  bool get isSignedIn => _status == YouTubeAccountStatus.signedIn;
  String get locale => _locale;

  YouTubeRating ratingFor(String videoId) =>
      _ratings[videoId] ?? YouTubeRating.none;

  bool isFollowingArtist(String channelId) =>
      _followingArtistIds.contains(channelId);

  bool isSavedEpisode(String videoId) =>
      _savedEpisodeVideoIds.contains(videoId);

  bool isPodcastEpisode(String videoId) =>
      _podcastEpisodeVideoIds.contains(videoId);

  bool isPodcastSaved(String podcastId) =>
      _podcasts.any((podcast) => podcast.id == podcastId);

  bool isAlbumSaved(String albumId) =>
      _albums.any((album) => album.id == albumId);

  Future<void> initialize() async {
    _status = YouTubeAccountStatus.restoring;
    _errorDiagnostic = null;
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
    _errorDiagnostic = null;
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
    _savedCollections = const <YouTubePlaylist>[];
    _podcasts = const <YouTubeFeedItem>[];
    _albums = const <YouTubeFeedItem>[];
    _followedArtists = const <YouTubeFeedItem>[];
    _historyTracks = const <YouTubeTrack>[];
    _selectedPlaylist = null;
    _selectedFeedCollection = null;
    _selectedFeedBrowse = null;
    _selectedPodcastShow = null;
    _homeSections = const <YouTubeFeedSection>[];
    _homeFilters = const <String>[];
    _selectedHomeFilter = null;
    _isLoadingMoreHome = false;
    _hasMoreHome = false;
    _isHomeContinuationHydrated = false;
    _exploreSections = const <YouTubeFeedSection>[];
    _exploreCategories = const <YouTubeFeedItem>[];
    _selectedExploreCategoryId = null;
    _isLoadingMoreExplore = false;
    _hasMoreExplore = false;
    _isLoadingMorePodcast = false;
    _searchResults = const <YouTubeFeedItem>[];
    _lyricsLines = const <YouTubeLyricLine>[];
    _comments = const <YouTubeComment>[];
    _ratings.clear();
    _followingArtistIds.clear();
    _savedEpisodeVideoIds.clear();
    _podcastEpisodeVideoIds.clear();
    _lyricsVideoId = null;
    _commentsVideoId = null;
    _hasLoadedLyrics = false;
    _searchQuery = '';
    _searchFilter = YouTubeMusicSearchFilter.all;
    _searchErrorMessage = null;
    _isSearching = false;
    _isLoadingHistory = false;
    _isLoadingMoreHistory = false;
    _hasLoadedHistory = false;
    _hasMoreHistory = false;
    _isLoadingMorePlaylist = false;
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
    _followingArtistId = null;
    _savedEpisodeVideoId = null;
    _podcastLibraryWriteId = null;
    _albumLibraryWriteId = null;
    _commentErrorMessage = null;
    _errorDiagnostic = null;
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
      _selectedPodcastShow = null;
      _savedCollections = const <YouTubePlaylist>[];
      _podcasts = const <YouTubeFeedItem>[];
      _albums = const <YouTubeFeedItem>[];
      _followedArtists = const <YouTubeFeedItem>[];
      _followingArtistIds.clear();
      _savedEpisodeVideoIds.clear();
      _podcastEpisodeVideoIds.clear();
      _historyTracks = const <YouTubeTrack>[];
      _hasLoadedHistory = false;
      _hasMoreHistory = false;
      _homeSections = const <YouTubeFeedSection>[];
      _homeFilters = const <String>[];
      _selectedHomeFilter = null;
      _exploreSections = const <YouTubeFeedSection>[];
      _exploreCategories = const <YouTubeFeedItem>[];
      _selectedExploreCategoryId = null;
      _hasMoreHome = false;
      _isHomeContinuationHydrated = false;
      _hasMoreExplore = false;
      _isLoadingMorePodcast = false;
      _isLoadingMoreHistory = false;
      _isLoadingMorePlaylist = false;
      notifyListeners();
      await _syncAccountData();
    } on Object {
      _errorMessage = YouTubeLibraryError.languageChangeFailed;
      notifyListeners();
    }
  }

  Future<void> loadMediaLibrary({bool forceRefresh = false}) async {
    if (!isSignedIn || _isLoadingLibrary) {
      return;
    }
    _isLoadingLibrary = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final cached = forceRefresh
          ? null
          : await _metadataCache?.read(_mediaLibraryCacheKey);
      if (cached != null) {
        _applyMediaLibrary(cached.data);
        notifyListeners();
        if (cached.isFresh(const Duration(minutes: 10))) {
          return;
        }
      }
      final result = await _client.call('library.media');
      _applyMediaLibrary(result);
      await _metadataCache?.write(_mediaLibraryCacheKey, result);
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
        _isLoadingMoreHistory ||
        (_hasLoadedHistory && !forceRefresh)) {
      return;
    }
    _isLoadingHistory = true;
    _historyErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('history.get');
      _historyTracks = _decodeTracks(result);
      _hasLoadedHistory = true;
      _hasMoreHistory = result['hasMore'] as bool? ?? false;
    } on Object catch (error) {
      _historyErrorMessage = _requestErrorFor(error);
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHistory() async {
    if (!isSignedIn ||
        !_hasMoreHistory ||
        _isLoadingHistory ||
        _isLoadingMoreHistory) {
      return;
    }
    _isLoadingMoreHistory = true;
    _historyErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('history.more');
      final byVideoId = <String, YouTubeTrack>{
        for (final track in _historyTracks) track.videoId: track,
        for (final track in _decodeTracks(result)) track.videoId: track,
      };
      _historyTracks = List<YouTubeTrack>.unmodifiable(byVideoId.values);
      _hasMoreHistory = result['hasMore'] as bool? ?? false;
    } on Object catch (error) {
      _historyErrorMessage = _requestErrorFor(error);
    } finally {
      _isLoadingMoreHistory = false;
      notifyListeners();
    }
  }

  Future<void> openPlaylist(YouTubePlaylist playlist) async {
    if (!isSignedIn || _isLoadingPlaylist) {
      return;
    }
    _isLoadingPlaylist = true;
    _loadingPlaylistId = playlist.id;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call(
        playlist.specialKind == null ? 'library.playlist' : 'library.special',
        playlist.specialKind == null
            ? <String, Object?>{'playlistId': playlist.id}
            : <String, Object?>{'kind': playlist.specialKind},
      );
      _selectedPlaylist = YouTubePlaylistDetail.fromJson(result);
      _podcastEpisodeVideoIds.addAll(
        _selectedPlaylist!.tracks
            .where((track) => _isPodcastEpisodeItemType(track.itemType))
            .map((track) => track.videoId),
      );
      if (_isSavedEpisodesPlaylist(_selectedPlaylist!.playlist)) {
        _savedEpisodeVideoIds
          ..clear()
          ..addAll(_selectedPlaylist!.tracks.map((track) => track.videoId));
      }
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingPlaylist = false;
      _loadingPlaylistId = null;
      notifyListeners();
    }
  }

  Future<void> loadMorePlaylist() async {
    final detail = _selectedPlaylist;
    if (detail == null ||
        !detail.hasMore ||
        _isLoadingPlaylist ||
        _isLoadingMorePlaylist) {
      return;
    }
    _isLoadingMorePlaylist = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final playlist = detail.playlist;
      final result = await _client.call(
        playlist.specialKind == null
            ? 'library.playlist.more'
            : 'library.special.more',
        playlist.specialKind == null
            ? <String, Object?>{'playlistId': playlist.id}
            : <String, Object?>{'kind': playlist.specialKind},
      );
      if (_selectedPlaylist?.playlist.id != playlist.id) {
        return;
      }
      final byVideoId = <String, YouTubeTrack>{
        for (final track in detail.tracks) track.videoId: track,
        for (final track in _decodeTracks(result)) track.videoId: track,
      };
      _selectedPlaylist = detail.copyWith(
        tracks: List<YouTubeTrack>.unmodifiable(byVideoId.values),
        hasMore: result['hasMore'] as bool? ?? false,
      );
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingMorePlaylist = false;
      notifyListeners();
    }
  }

  Future<void> loadHome({bool forceRefresh = false}) async {
    if (!isSignedIn || _isLoadingHome) {
      return;
    }
    _isLoadingHome = true;
    _isHomeContinuationHydrated = false;
    _homeErrorMessage = null;
    notifyListeners();
    try {
      final cached = forceRefresh
          ? null
          : await _metadataCache?.read('feed.home.v2');
      if (cached != null) {
        _applyHomeResult(cached.data);
        _hasMoreHome = cached.data['hasMore'] == true;
        notifyListeners();
        if (!_hasMoreHome &&
            _homeFilters.isNotEmpty &&
            cached.isFresh(const Duration(minutes: 10))) {
          return;
        }
      }
      final result = await _client.call('feed.home');
      _applyHomeResult(result);
      _hasMoreHome = result['hasMore'] == true;
      _isHomeContinuationHydrated = true;
      await _metadataCache?.write('feed.home.v2', result);
    } on Object catch (error) {
      _homeErrorMessage = _requestErrorFor(error);
      _hasMoreHome = false;
      _isHomeContinuationHydrated = false;
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  Future<void> selectHomeFilter(
    String filter, {
    bool forceRefresh = false,
  }) async {
    final value = filter.trim();
    if (!isSignedIn ||
        _isLoadingHome ||
        !_homeFilters.contains(value) ||
        (_selectedHomeFilter == value && !forceRefresh)) {
      return;
    }
    final previousFilter = _selectedHomeFilter;
    _selectedHomeFilter = value;
    _isLoadingHome = true;
    _homeErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.home.filter', <String, Object?>{
        'filter': value,
      });
      _applyHomeResult(result);
      _hasMoreHome = result['hasMore'] == true;
      _isHomeContinuationHydrated = true;
    } on Object catch (error) {
      _selectedHomeFilter = previousFilter;
      _homeErrorMessage = _requestErrorFor(error);
      _hasMoreHome = false;
      _isHomeContinuationHydrated = false;
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHome() async {
    if (!isSignedIn ||
        !_hasMoreHome ||
        !_isHomeContinuationHydrated ||
        _isLoadingHome ||
        _isLoadingMoreHome) {
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
          : await _metadataCache?.read('feed.explore.v4');
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
      await _metadataCache?.write('feed.explore.v4', result);
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

  Future<void> searchMusic(
    String query, {
    YouTubeMusicSearchFilter filter = YouTubeMusicSearchFilter.all,
  }) async {
    final normalizedQuery = query.trim();
    final request = ++_searchRequest;
    final identityChanged =
        normalizedQuery != _searchQuery || filter != _searchFilter;
    _searchQuery = normalizedQuery;
    _searchFilter = filter;
    _searchErrorMessage = null;
    if (identityChanged) {
      _searchResults = const <YouTubeFeedItem>[];
    }
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
        'filter': filter.protocolValue,
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
    if (tracks.length == 1 && item.itemType != 'album') {
      return tracks;
    }
    _selectedFeedCollection = YouTubeFeedCollectionDetail(
      source: source,
      id: item.itemType == 'album' ? item.id : item.browseIdentity,
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
    if (_isPodcastEpisodeItemType(item.itemType) && item.videoId != null) {
      _podcastEpisodeVideoIds.add(item.videoId!);
    }
    final fallback = _feedTrackFromItem(item);
    if (!_shouldResolveFeedDuration(item.durationSeconds)) {
      return fallback;
    }

    _loadingFeedItemId = item.id;
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      return await _requestFeedTrack(item);
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
      return fallback;
    } finally {
      _loadingFeedItemId = null;
      notifyListeners();
    }
  }

  Future<int> resolveFeedTrackDuration(YouTubeFeedItem item) async {
    if (!_shouldResolveFeedDuration(item.durationSeconds)) {
      return item.durationSeconds;
    }
    try {
      return (await _requestFeedTrack(item)).durationSeconds;
    } on Object {
      return item.durationSeconds;
    }
  }

  YouTubeTrack _feedTrackFromItem(YouTubeFeedItem item) {
    return YouTubeTrack(
      videoId: item.videoId!,
      title: item.title,
      artists: item.artists,
      durationSeconds: item.durationSeconds,
      itemType: item.itemType,
      album: item.album,
      thumbnailUrl: item.thumbnailUrl,
    );
  }

  Future<YouTubeTrack> _requestFeedTrack(YouTubeFeedItem item) async {
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
      durationSeconds: track.durationSeconds > 0
          ? track.durationSeconds
          : item.durationSeconds,
      itemType: item.itemType,
      album: item.album,
      thumbnailUrl: track.thumbnailUrl ?? item.thumbnailUrl,
    );
  }

  bool _shouldResolveFeedDuration(int durationSeconds) {
    // Older cached feed entries may contain only the clock's seconds component.
    return durationSeconds < Duration.secondsPerMinute;
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

  Future<Map<String, Object?>> downloadMediaBundle({
    required String videoId,
    required String directory,
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
    required String artworkUrl,
  }) async {
    if (!isSignedIn || videoId.isEmpty) {
      throw const SidecarException('AUTHENTICATION_REQUIRED', '');
    }
    return _client.call('download.track', <String, Object?>{
      'videoId': videoId,
      'directory': directory,
      'title': title,
      'artist': artist,
      'album': album,
      'durationSeconds': durationSeconds,
      'artworkUrl': artworkUrl,
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

  Future<void> toggleArtistFollow(String channelId) async {
    if (!isSignedIn ||
        channelId.isEmpty ||
        _followingArtistId != null ||
        isAccountWriteCoolingDown) {
      return;
    }
    final shouldFollow = !_followingArtistIds.contains(channelId);
    _followingArtistId = channelId;
    _beginAccountWriteCooldown();
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call(
        'interaction.subscription',
        <String, Object?>{'channelId': channelId, 'subscribed': shouldFollow},
      );
      final resolvedChannelId =
          _nonEmptyString(result['channelId']) ?? channelId;
      final isSubscribed = result['subscribed'] is bool
          ? result['subscribed']! as bool
          : shouldFollow;
      _followingArtistIds.remove(channelId);
      if (isSubscribed) {
        _followingArtistIds.add(resolvedChannelId);
      } else {
        _followingArtistIds.remove(resolvedChannelId);
      }
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _followingArtistId = null;
      notifyListeners();
    }
  }

  Future<void> toggleSavedEpisode(
    String videoId, {
    required String title,
    required String artist,
    required String album,
    required String artworkUrl,
    required int durationSeconds,
  }) async {
    if (!isSignedIn ||
        videoId.isEmpty ||
        !isPodcastEpisode(videoId) ||
        _savedEpisodeVideoId != null ||
        isAccountWriteCoolingDown) {
      return;
    }
    final shouldSave = !_savedEpisodeVideoIds.contains(videoId);
    _savedEpisodeVideoId = videoId;
    _beginAccountWriteCooldown();
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      await _client.call('podcast.episode_later.set', <String, Object?>{
        'videoId': videoId,
        'saved': shouldSave,
      });
      if (shouldSave) {
        _savedEpisodeVideoIds.add(videoId);
      } else {
        _savedEpisodeVideoIds.remove(videoId);
      }
      _updateOpenSavedEpisodes(
        videoId,
        shouldSave,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        durationSeconds: durationSeconds,
      );
      await loadMediaLibrary(forceRefresh: true);
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _savedEpisodeVideoId = null;
      notifyListeners();
    }
  }

  Future<void> togglePodcastLibrary(YouTubePodcastShowDetail detail) async {
    if (!isSignedIn ||
        detail.id.isEmpty ||
        _podcastLibraryWriteId != null ||
        isAccountWriteCoolingDown) {
      return;
    }
    final shouldSave = !isPodcastSaved(detail.id);
    _podcastLibraryWriteId = detail.id;
    _beginAccountWriteCooldown();
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      await _client.call('podcast.library.set', <String, Object?>{
        'podcastId': detail.libraryId,
        'saved': shouldSave,
      });
      await loadMediaLibrary(forceRefresh: true);
      _setPodcastSaved(detail, shouldSave);
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _podcastLibraryWriteId = null;
      notifyListeners();
    }
  }

  Future<void> toggleAlbumLibrary(YouTubeFeedCollectionDetail detail) async {
    if (!isSignedIn ||
        detail.itemType != 'album' ||
        detail.id.isEmpty ||
        _albumLibraryWriteId != null ||
        isAccountWriteCoolingDown) {
      return;
    }
    final wasSaved = isAlbumSaved(detail.id);
    final shouldSave = !wasSaved;
    _albumLibraryWriteId = detail.id;
    _beginAccountWriteCooldown();
    _feedActionErrorMessage = null;
    _setAlbumSaved(detail, shouldSave);
    notifyListeners();
    bool? confirmedSaved;
    try {
      final result = await _client.call('album.library.set', <String, Object?>{
        'albumId': detail.id,
        'saved': shouldSave,
      });
      confirmedSaved = result['saved'] is bool
          ? result['saved']! as bool
          : shouldSave;
      _setAlbumSaved(detail, confirmedSaved);
    } on Object {
      _setAlbumSaved(detail, wasSaved);
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _albumLibraryWriteId = null;
      notifyListeners();
    }
    if (confirmedSaved == null) {
      return;
    }
    await loadMediaLibrary(forceRefresh: true);
    _setAlbumSaved(detail, confirmedSaved);
    notifyListeners();
  }

  void _setAlbumSaved(YouTubeFeedCollectionDetail detail, bool saved) {
    final remaining = _albums
        .where((album) => album.id != detail.id)
        .toList(growable: false);
    _albums = List<YouTubeFeedItem>.unmodifiable(<YouTubeFeedItem>[
      if (saved)
        YouTubeFeedItem(
          id: detail.id,
          itemType: 'album',
          title: detail.title,
          subtitle: detail.artists.join(', '),
          artists: detail.artists,
          durationSeconds: 0,
          thumbnailUrl: detail.thumbnailUrl,
        ),
      ...remaining,
    ]);
  }

  void _setPodcastSaved(YouTubePodcastShowDetail detail, bool saved) {
    final remaining = _podcasts
        .where((podcast) => podcast.id != detail.id)
        .toList(growable: false);
    _podcasts = List<YouTubeFeedItem>.unmodifiable(<YouTubeFeedItem>[
      if (saved)
        YouTubeFeedItem(
          id: detail.id,
          itemType: 'podcast',
          title: detail.title,
          subtitle: detail.subtitle,
          description: detail.description,
          artists: const <String>[],
          durationSeconds: 0,
          thumbnailUrl: detail.thumbnailUrl,
        ),
      ...remaining,
    ]);
  }

  void _updateOpenSavedEpisodes(
    String videoId,
    bool shouldSave, {
    required String title,
    required String artist,
    required String album,
    required String artworkUrl,
    required int durationSeconds,
  }) {
    final detail = _selectedPlaylist;
    if (!_isSavedEpisodesPlaylist(detail?.playlist)) {
      return;
    }
    final tracks = <YouTubeTrack>[...detail!.tracks];
    if (shouldSave) {
      if (tracks.any((track) => track.videoId == videoId)) {
        return;
      }
      tracks.insert(
        0,
        YouTubeTrack(
          videoId: videoId,
          title: title,
          artists: artist.isEmpty ? const <String>[] : <String>[artist],
          durationSeconds: durationSeconds,
          itemType: 'non_music_track',
          album: album.isEmpty ? null : album,
          thumbnailUrl: artworkUrl.isEmpty ? null : artworkUrl,
        ),
      );
    } else {
      tracks.removeWhere((track) => track.videoId == videoId);
    }
    _selectedPlaylist = detail.copyWith(
      tracks: List<YouTubeTrack>.unmodifiable(tracks),
    );
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
      if (item.itemType == 'podcast') {
        final podcast = (result['podcast']! as Map<Object?, Object?>)
            .cast<String, Object?>();
        _selectedFeedBrowse = null;
        _selectedPodcastShow = YouTubePodcastShowDetail.fromJson(
          podcast,
          source: source,
        );
      } else if (source == 'explore' && item.itemType == 'category') {
        final sections = _decodeFeedSections(result);
        _selectedFeedBrowse = null;
        _selectedPodcastShow = null;
        _exploreSections = _withoutExploreCategories(sections);
        _hasMoreExplore = false;
        _selectedExploreCategoryId = item.browseIdentity;
      } else {
        final sections = _decodeFeedSections(result);
        final artist = result['artist'] is Map<Object?, Object?>
            ? (result['artist']! as Map<Object?, Object?>)
                  .cast<String, Object?>()
            : null;
        final channelId =
            _nonEmptyString(artist?['channelId']) ??
            (item.itemType == 'artist' ? item.id : null);
        final isSubscribed = artist?['subscribed'];
        if (channelId != null && isSubscribed is bool) {
          if (isSubscribed) {
            _followingArtistIds.add(channelId);
          } else {
            _followingArtistIds.remove(channelId);
          }
        }
        _selectedPodcastShow = null;
        _selectedFeedBrowse = YouTubeFeedBrowseDetail(
          source: source,
          id: item.browseIdentity,
          itemType: item.itemType,
          title: _nonEmptyString(artist?['title']) ?? item.title,
          subtitle: _nonEmptyString(artist?['subtitle']) ?? item.subtitle,
          audience: _nonEmptyString(artist?['audience']),
          thumbnailUrl:
              _nonEmptyString(artist?['thumbnailUrl']) ?? item.thumbnailUrl,
          channelId: channelId,
          subscriberCount: _nonEmptyString(artist?['subscriberCount']),
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

  Future<void> loadMorePodcastShow() async {
    final detail = _selectedPodcastShow;
    if (detail == null || !detail.hasMore || _isLoadingMorePodcast) {
      return;
    }
    _isLoadingMorePodcast = true;
    _feedActionErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.browse.more', <String, Object?>{
        'itemType': 'podcast',
        'id': detail.id,
      });
      if (_selectedPodcastShow?.id != detail.id) {
        return;
      }
      final appended = (result['episodes']! as List<Object?>)
          .map(
            (item) => YouTubeFeedItem.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
      final byId = <String, YouTubeFeedItem>{
        for (final episode in detail.episodes) episode.id: episode,
        for (final episode in appended) episode.id: episode,
      };
      _selectedPodcastShow = detail.copyWith(
        episodes: List<YouTubeFeedItem>.unmodifiable(byId.values),
        hasMore: result['hasMore'] as bool? ?? false,
      );
    } on Object {
      _feedActionErrorMessage = YouTubeLibraryError.actionFailed;
    } finally {
      _isLoadingMorePodcast = false;
      notifyListeners();
    }
  }

  void closeFeedDetail() {
    if (_selectedFeedCollection != null) {
      _selectedFeedCollection = null;
    } else if (_selectedPodcastShow != null) {
      _selectedPodcastShow = null;
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
    _isLoadingMorePlaylist = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    _errorDiagnostic = null;
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
        _errorDiagnostic = null;
        notifyListeners();
      case 'auth.error':
        _errorMessage = YouTubeLibraryError.authenticationFailed;
        _errorDiagnostic = 'AUTHENTICATION_FAILED';
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
      loadMediaLibrary(),
      loadHome(),
      loadExplore(),
    ]);
  }

  static String _normalizeLocale(String locale) =>
      locale.toLowerCase().startsWith('zh') ? 'zh-CN' : 'en';

  static String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static bool _isSavedEpisodesPlaylist(YouTubePlaylist? playlist) {
    return playlist?.id == 'SE';
  }

  static bool _isPodcastEpisodeItemType(String itemType) {
    return itemType == 'episode' || itemType == 'non_music_track';
  }

  List<YouTubeFeedSection> _decodeFeedSections(Map<String, Object?> result) {
    return (result['sections']! as List<Object?>)
        .map(
          (item) => YouTubeFeedSection.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  void _applyMediaLibrary(Map<String, Object?> result) {
    _playlists = _decodePlaylists(result['playlists']);
    _savedCollections = _decodePlaylists(result['savedCollections']);
    _podcasts = _decodeFeedItems(result['podcasts']);
    _albums = _decodeFeedItems(result['albums']);
    _followedArtists = _decodeFeedItems(result['followedArtists']);
    _followingArtistIds
      ..clear()
      ..addAll(_followedArtists.map((artist) => artist.id));
  }

  List<YouTubePlaylist> _decodePlaylists(Object? value) {
    return (value as List<Object?>? ?? const <Object?>[])
        .map(
          (item) => YouTubePlaylist.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  List<YouTubeFeedItem> _decodeFeedItems(Object? value) {
    return (value as List<Object?>? ?? const <Object?>[])
        .map(
          (item) => YouTubeFeedItem.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  List<YouTubeTrack> _decodeTracks(Map<String, Object?> result) {
    final tracks = (result['tracks'] as List<Object?>? ?? const <Object?>[])
        .map(
          (track) => YouTubeTrack.fromJson(
            (track! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
    _podcastEpisodeVideoIds.addAll(
      tracks
          .where((track) => _isPodcastEpisodeItemType(track.itemType))
          .map((track) => track.videoId),
    );
    return tracks;
  }

  void _applyExploreSections(List<YouTubeFeedSection> sections) {
    _exploreCategories = _extractExploreCategories(sections);
    _exploreSections = _withoutExploreCategories(sections);
    _selectedExploreCategoryId = null;
  }

  void _applyHomeResult(Map<String, Object?> result) {
    _homeSections = _decodeFeedSections(result);
    _homeFilters = (result['filters'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    _selectedHomeFilter = result['selectedFilter'] as String?;
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
      merged[index] = YouTubeFeedSection(
        title: current.title,
        subtitle: current.subtitle,
        items: items,
        itemsPerColumn: current.itemsPerColumn,
      );
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
              : YouTubeFeedSection(
                  title: section.title,
                  subtitle: section.subtitle,
                  items: items,
                  itemsPerColumn: section.itemsPerColumn,
                );
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
      }.contains(error.code);

  void _setError(Object error, {bool preserveSignedIn = false}) {
    _errorMessage = _requestErrorFor(error);
    _errorDiagnostic = _diagnosticFor(error);
    if (!preserveSignedIn) {
      _status = YouTubeAccountStatus.error;
    }
    notifyListeners();
  }

  String? _diagnosticFor(Object error) {
    if (error is! SidecarException) {
      return null;
    }
    final parts = <String>[error.code];
    final details = error.details;
    if (details is Map<Object?, Object?>) {
      final stage = details['diagnosticStage'];
      if (stage is String &&
          RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(stage)) {
        parts.add(stage);
      }
      final statusCode = details['statusCode'];
      if (statusCode is int && statusCode >= 100 && statusCode <= 599) {
        parts.add('HTTP $statusCode');
      }
      final upstreamCode = details['upstreamCode'];
      if (upstreamCode is String &&
          upstreamCode != error.code &&
          RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(upstreamCode)) {
        parts.add(upstreamCode);
      }
    }
    return parts.join(' / ');
  }
}
