import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/youtube_library.dart';
import '../services/credential_store.dart';
import '../services/youtube_sidecar_client.dart';

enum YouTubeAccountStatus { signedOut, restoring, authorizing, signedIn, error }

class YouTubeLibraryController extends ChangeNotifier {
  YouTubeLibraryController({
    required YouTubeSidecarClient client,
    required CredentialStore credentialStore,
  }) : this._(client, credentialStore);

  YouTubeLibraryController._(this._client, this._credentialStore) {
    _eventSubscription = _client.events.listen(_handleEvent);
  }

  final YouTubeSidecarClient _client;
  final CredentialStore _credentialStore;
  late final StreamSubscription<SidecarEvent> _eventSubscription;

  YouTubeAccountStatus _status = YouTubeAccountStatus.signedOut;
  List<YouTubePlaylist> _playlists = const <YouTubePlaylist>[];
  YouTubePlaylistDetail? _selectedPlaylist;
  YouTubeFeedCollectionDetail? _selectedFeedCollection;
  YouTubeFeedBrowseDetail? _selectedFeedBrowse;
  List<YouTubeFeedSection> _homeSections = const <YouTubeFeedSection>[];
  List<YouTubeFeedSection> _exploreSections = const <YouTubeFeedSection>[];
  List<YouTubeFeedItem> _searchResults = const <YouTubeFeedItem>[];
  String? _errorMessage;
  String? _homeErrorMessage;
  String? _exploreErrorMessage;
  String? _feedActionErrorMessage;
  String? _loadingFeedItemId;
  bool _isLoadingLibrary = false;
  bool _isLoadingPlaylist = false;
  bool _isLoadingHome = false;
  bool _isLoadingExplore = false;
  bool _isLoadingFeedBrowse = false;
  bool _isSearching = false;
  int _searchRequest = 0;
  String _searchQuery = '';
  String? _searchErrorMessage;
  String? _profileName;
  String? _profileAvatarUrl;

  YouTubeAccountStatus get status => _status;
  List<YouTubePlaylist> get playlists => _playlists;
  YouTubePlaylistDetail? get selectedPlaylist => _selectedPlaylist;
  YouTubeFeedCollectionDetail? get selectedFeedCollection =>
      _selectedFeedCollection;
  YouTubeFeedBrowseDetail? get selectedFeedBrowse => _selectedFeedBrowse;
  List<YouTubeFeedSection> get homeSections => _homeSections;
  List<YouTubeFeedSection> get exploreSections => _exploreSections;
  List<YouTubeFeedItem> get searchResults => _searchResults;
  String? get errorMessage => _errorMessage;
  String? get homeErrorMessage => _homeErrorMessage;
  String? get exploreErrorMessage => _exploreErrorMessage;
  String? get feedActionErrorMessage => _feedActionErrorMessage;
  String? get loadingFeedItemId => _loadingFeedItemId;
  bool get isLoadingLibrary => _isLoadingLibrary;
  bool get isLoadingPlaylist => _isLoadingPlaylist;
  bool get isLoadingHome => _isLoadingHome;
  bool get isLoadingExplore => _isLoadingExplore;
  bool get isLoadingFeedBrowse => _isLoadingFeedBrowse;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  String? get searchErrorMessage => _searchErrorMessage;
  String? get profileName => _profileName;
  String? get profileAvatarUrl => _profileAvatarUrl;
  bool get isSignedIn => _status == YouTubeAccountStatus.signedIn;

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
      });
      _applyProfile(result);
      _status = YouTubeAccountStatus.signedIn;
      notifyListeners();
      await _syncAccountData();
    } on Object catch (error) {
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
    _status = YouTubeAccountStatus.signedOut;
    _playlists = const <YouTubePlaylist>[];
    _selectedPlaylist = null;
    _selectedFeedCollection = null;
    _selectedFeedBrowse = null;
    _homeSections = const <YouTubeFeedSection>[];
    _exploreSections = const <YouTubeFeedSection>[];
    _searchResults = const <YouTubeFeedItem>[];
    _searchQuery = '';
    _searchErrorMessage = null;
    _isSearching = false;
    _searchRequest += 1;
    _errorMessage = null;
    _homeErrorMessage = null;
    _exploreErrorMessage = null;
    _feedActionErrorMessage = null;
    _profileName = null;
    _profileAvatarUrl = null;
    notifyListeners();
  }

  Future<void> loadPlaylists() async {
    if (!isSignedIn || _isLoadingLibrary) {
      return;
    }
    _isLoadingLibrary = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('library.playlists');
      _playlists = (result['playlists']! as List<Object?>)
          .map(
            (item) => YouTubePlaylist.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingLibrary = false;
      notifyListeners();
    }
  }

  Future<void> openPlaylist(YouTubePlaylist playlist) async {
    _isLoadingPlaylist = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('library.playlist', <String, Object?>{
        'playlistId': playlist.id,
      });
      _selectedPlaylist = YouTubePlaylistDetail.fromJson(result);
    } on Object catch (error) {
      _setError(error, preserveSignedIn: true);
    } finally {
      _isLoadingPlaylist = false;
      notifyListeners();
    }
  }

  Future<void> loadHome() async {
    if (!isSignedIn || _isLoadingHome) {
      return;
    }
    _isLoadingHome = true;
    _homeErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.home');
      _homeSections = _decodeFeedSections(result);
    } on Object catch (error) {
      _homeErrorMessage = _messageFor(error);
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  Future<void> loadExplore() async {
    if (!isSignedIn || _isLoadingExplore) {
      return;
    }
    _isLoadingExplore = true;
    _exploreErrorMessage = null;
    notifyListeners();
    try {
      final result = await _client.call('feed.explore');
      _exploreSections = _decodeFeedSections(result);
    } on Object catch (error) {
      _exploreErrorMessage = _messageFor(error);
    } finally {
      _isLoadingExplore = false;
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
        _searchErrorMessage = _messageFor(error);
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
    } on Object catch (error) {
      _feedActionErrorMessage = _messageFor(error);
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
    } on Object catch (error) {
      _feedActionErrorMessage = _messageFor(error);
      return fallback;
    } finally {
      _loadingFeedItemId = null;
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
        _exploreSections = sections;
      } else {
        _selectedFeedBrowse = YouTubeFeedBrowseDetail(
          source: source,
          title: item.title,
          sections: sections,
        );
      }
    } on Object catch (error) {
      _feedActionErrorMessage = _messageFor(error);
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
        _setError(event.data['message'] ?? 'YouTube authentication failed.');
    }
  }

  Future<void> _syncAccountData() async {
    await Future.wait(<Future<void>>[
      loadPlaylists(),
      loadHome(),
      loadExplore(),
    ]);
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

  void _applyProfile(Map<String, Object?> result) {
    final profile = result['profile'];
    if (profile is! Map<Object?, Object?>) {
      return;
    }
    _profileName = profile['displayName'] as String?;
    _profileAvatarUrl = profile['avatarUrl'] as String?;
  }

  String _messageFor(Object error) {
    return switch (error) {
      SidecarException(:final message) => message,
      _ => error.toString(),
    };
  }

  void _setError(Object error, {bool preserveSignedIn = false}) {
    _errorMessage = _messageFor(error);
    if (!preserveSignedIn) {
      _status = YouTubeAccountStatus.error;
    }
    notifyListeners();
  }
}
