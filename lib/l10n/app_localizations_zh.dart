// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Otoha';

  @override
  String get settings => '设置';

  @override
  String get desktop => 'Desktop';

  @override
  String get motion => '动画';

  @override
  String get reduceMotion => '减少动画';

  @override
  String get language => '语言';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get outputDevice => '输出设备';

  @override
  String get queue => '队列';

  @override
  String get noTrackSelected => '未选择歌曲';

  @override
  String get queueEmpty => '队列为空。';

  @override
  String get youtubeMusic => 'YouTube Music';

  @override
  String get closePanel => '关闭面板';

  @override
  String get systemDefault => '系统默认';

  @override
  String get outputUnavailable => '不可用';

  @override
  String get noAudioOutputDevices => '没有可用的音频输出设备。';

  @override
  String get changeOutputDeviceError => '无法切换音频输出设备。';

  @override
  String get home => '首页';

  @override
  String get explore => '探索';

  @override
  String get library => '音乐库';

  @override
  String get history => '历史记录';

  @override
  String get yourSpace => '你的空间';

  @override
  String get downloads => '下载';

  @override
  String get playlists => '播放列表';

  @override
  String get back => '返回';

  @override
  String get forward => '前进';

  @override
  String get profile => '个人资料';

  @override
  String get minimize => '最小化';

  @override
  String get maximize => '最大化';

  @override
  String get close => '关闭';

  @override
  String get search => '搜索';

  @override
  String get searchYourMusic => '搜索你的音乐';

  @override
  String get searchShortcut => '搜索（Ctrl/Cmd + K）';

  @override
  String get searchSongsArtistsAlbumsOrCommands => '搜索歌曲、艺人、专辑或命令';

  @override
  String get noYouTubeMusicMatches => '没有匹配的 YouTube Music 内容';

  @override
  String get noLocalMatches => '没有本地匹配项';

  @override
  String get openWorkspace => '打开工作区';

  @override
  String get command => '命令';

  @override
  String get previous => '上一首';

  @override
  String get pause => '暂停';

  @override
  String get play => '播放';

  @override
  String get next => '下一首';

  @override
  String get openFullLyrics => '打开完整歌词';

  @override
  String get shuffle => '随机播放';

  @override
  String get repeatOff => '关闭循环';

  @override
  String get repeatAll => '循环播放';

  @override
  String get repeatOne => '单曲循环';

  @override
  String get volume => '音量';

  @override
  String volumePercentage(int value) {
    return '$value%';
  }

  @override
  String outputDeviceWithValue(Object device, Object value) {
    return '$device：$value';
  }

  @override
  String get unknownDuration => '--:--';

  @override
  String get signInToYouTubeMusic => '登录 YouTube Music';

  @override
  String get youtubeMusicSignIn => '登录 YouTube Music';

  @override
  String get youtubeCookieHeader => 'YouTube Cookie 请求头';

  @override
  String get signIn => '登录';

  @override
  String get signOut => '退出登录';

  @override
  String get syncLibrary => '同步音乐库';

  @override
  String get fullYouTubeMusicSession => '完整 YouTube Music 会话';

  @override
  String playlistCount(int count) {
    return '$count 个播放列表';
  }

  @override
  String get yourLibrary => '你的音乐库';

  @override
  String get yourPlaylists => '你的播放列表';

  @override
  String get noPlaylistsFound => '未找到播放列表';

  @override
  String get backToPlaylists => '返回播放列表';

  @override
  String get playlist => '播放列表';

  @override
  String tracksCount(int count) {
    return '$count 首歌曲';
  }

  @override
  String get yourActivity => '你的活动';

  @override
  String get refreshHistory => '刷新历史记录';

  @override
  String get loadHistoryAgain => '重新加载历史记录';

  @override
  String get noPlaybackHistoryFound => '未找到播放历史记录。';

  @override
  String get forYourAccount => '为你的帐户推荐';

  @override
  String refreshSection(Object section) {
    return '刷新$section';
  }

  @override
  String get loadAgain => '重新加载';

  @override
  String get forYou => '为你推荐';

  @override
  String get scrollMoodsGenresLeft => '向左滚动心情和流派';

  @override
  String get scrollMoodsGenresRight => '向右滚动心情和流派';

  @override
  String scrollSectionLeft(Object section) {
    return '向左滚动$section';
  }

  @override
  String scrollSectionRight(Object section) {
    return '向右滚动$section';
  }

  @override
  String get album => '专辑';

  @override
  String get artist => '艺人';

  @override
  String get moodAndGenre => '心情与流派';

  @override
  String get episode => '单集';

  @override
  String get song => '歌曲';

  @override
  String get musicVideo => '音乐视频';

  @override
  String get genre => '流派';

  @override
  String get closeFullLyrics => '关闭完整歌词';

  @override
  String get previousTrack => '上一首歌曲';

  @override
  String get nextTrack => '下一首歌曲';

  @override
  String get playbackProgress => '播放进度';

  @override
  String get lyricsUnavailable => '暂无歌词。';

  @override
  String get lyricsUnavailableForTrack => '此歌曲暂无歌词。';

  @override
  String artwork(Object title) {
    return '$title 封面';
  }

  @override
  String profileImage(Object title) {
    return '$title 头像';
  }

  @override
  String backgroundArtwork(Object title) {
    return '$title 背景封面';
  }

  @override
  String moodAndGenreLabel(Object title) {
    return '$title 心情与流派';
  }

  @override
  String get unableToChangeAppLanguage => '无法切换应用语言。';

  @override
  String get youtubeAuthenticationFailed =>
      'YouTube 登录失败。请复制当前完整的 Cookie 请求头后重试。';

  @override
  String get unableToLoadYouTubeMusic => '无法加载 YouTube Music 数据。';

  @override
  String get unableToCompleteYouTubeMusicAction => '无法完成 YouTube Music 操作。';

  @override
  String get audioEngineCouldNotPlay => '音频引擎无法播放此歌曲。';

  @override
  String get audioStreamUnavailable => 'YouTube 未提供此歌曲的音频流。';

  @override
  String get unableToStartAudioPlayback => '无法开始播放此歌曲。';

  @override
  String get showWindow => '显示窗口';

  @override
  String get quitApplication => '退出';

  @override
  String get about => '关于';

  @override
  String appVersion(String version) {
    return '版本 $version';
  }

  @override
  String get versionUnavailable => '版本不可用';

  @override
  String get downloadLocation => '下载位置';

  @override
  String get saveDownloadLocation => '保存下载位置';

  @override
  String get downloadCurrentTrack => '下载当前歌曲';

  @override
  String get downloaded => '已下载';

  @override
  String get noDownloads => '还没有下载内容。';

  @override
  String get deleteDownload => '删除下载';

  @override
  String deleteDownloadConfirmation(String title) {
    return '确定从下载中删除《$title》吗？本地文件及其在离线播放列表中的引用都会被移除。';
  }

  @override
  String get cancel => '取消';

  @override
  String shortcutTooltip(String action, String shortcut) {
    return '$action（$shortcut）';
  }

  @override
  String get newPlaylist => '新建播放列表';

  @override
  String get createPlaylist => '创建播放列表';

  @override
  String get playlistName => '播放列表名称';

  @override
  String get addToPlaylist => '添加到播放列表';

  @override
  String get removeFromPlaylist => '从播放列表中移除';

  @override
  String get deletePlaylist => '删除播放列表';

  @override
  String get deletePlaylistConfirmation => '确定删除此播放列表吗？已下载的歌曲仍会保留。';

  @override
  String get renamePlaylist => '重命名播放列表';

  @override
  String get choosePlaylistCover => '选择播放列表封面';

  @override
  String get noOfflinePlaylists => '还没有离线播放列表。';

  @override
  String get noDownloadedTracksInPlaylist => '此播放列表中没有已下载歌曲。';
}
