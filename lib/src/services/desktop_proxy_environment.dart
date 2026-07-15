import 'dart:io';

class DesktopProxyEnvironment {
  const DesktopProxyEnvironment._();

  static const _proxySchema = 'org.gnome.system.proxy';

  static Future<Map<String, String>> resolve({
    required Map<String, String> environment,
    required bool isLinux,
    Future<String?> Function(String schema, String key)? readSetting,
  }) async {
    final resolved = <String, String>{'NODE_USE_ENV_PROXY': '1'};
    final httpProxy = _environmentValue(environment, 'HTTP_PROXY');
    final httpsProxy = _environmentValue(environment, 'HTTPS_PROXY');
    final allProxy = _environmentValue(environment, 'ALL_PROXY');
    final noProxy = _environmentValue(environment, 'NO_PROXY');
    if (httpProxy != null) {
      resolved['HTTP_PROXY'] = httpProxy;
    }
    if (httpsProxy != null) {
      resolved['HTTPS_PROXY'] = httpsProxy;
    }
    if (allProxy != null) {
      resolved['HTTP_PROXY'] ??= allProxy;
      resolved['HTTPS_PROXY'] ??= allProxy;
    }
    if (noProxy != null) {
      resolved['NO_PROXY'] = noProxy;
    }
    if (httpProxy != null || httpsProxy != null || allProxy != null) {
      return resolved;
    }
    if (!isLinux) {
      return resolved;
    }

    final setting = readSetting ?? _readLinuxSetting;
    if (_settingValue(await setting(_proxySchema, 'mode')) != 'manual') {
      return resolved;
    }
    final values = await Future.wait(<Future<String?>>[
      setting('$_proxySchema.http', 'host'),
      setting('$_proxySchema.http', 'port'),
      setting('$_proxySchema.https', 'host'),
      setting('$_proxySchema.https', 'port'),
      setting(_proxySchema, 'use-same-proxy'),
    ]);
    final resolvedHttpProxy = _proxyUri(values[0], values[1]);
    var resolvedHttpsProxy = _proxyUri(values[2], values[3]);
    if (resolvedHttpsProxy == null && _settingValue(values[4]) == 'true') {
      resolvedHttpsProxy = resolvedHttpProxy;
    }
    if (resolvedHttpProxy != null) {
      resolved['HTTP_PROXY'] = resolvedHttpProxy;
    }
    if (resolvedHttpsProxy != null) {
      resolved['HTTPS_PROXY'] = resolvedHttpsProxy;
    }
    if (resolvedHttpProxy != null || resolvedHttpsProxy != null) {
      resolved['NO_PROXY'] ??= 'localhost,127.0.0.1,::1';
    }
    return resolved;
  }

  static String? proxyUrlFor(
    Uri uri, {
    required Map<String, String> environment,
  }) {
    final route = HttpClient.findProxyFromEnvironment(
      uri,
      environment: environment,
    );
    if (route
        .split(';')
        .map((directive) => directive.trim().toUpperCase())
        .contains('DIRECT')) {
      return null;
    }
    return _environmentValue(
          environment,
          uri.scheme == 'https' ? 'HTTPS_PROXY' : 'HTTP_PROXY',
        ) ??
        _environmentValue(environment, 'ALL_PROXY');
  }

  static String? _environmentValue(
    Map<String, String> environment,
    String name,
  ) {
    for (final entry in environment.entries) {
      if (entry.key.toUpperCase() == name && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
    return null;
  }

  static String? _proxyUri(String? rawHost, String? rawPort) {
    final host = _settingValue(rawHost);
    final port = int.tryParse(_settingValue(rawPort) ?? '');
    if (host == null ||
        host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    try {
      return Uri(scheme: 'http', host: host, port: port).toString();
    } on FormatException {
      return null;
    }
  }

  static String? _settingValue(String? rawValue) {
    if (rawValue == null) {
      return null;
    }
    final value = rawValue.trim();
    if (value.length >= 2 &&
        ((value.startsWith("'") && value.endsWith("'")) ||
            (value.startsWith('"') && value.endsWith('"')))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static Future<String?> _readLinuxSetting(String schema, String key) async {
    try {
      final result = await Process.run('gsettings', <String>[
        'get',
        schema,
        key,
      ]).timeout(const Duration(seconds: 2));
      return result.exitCode == 0 ? result.stdout as String : null;
    } on Object {
      return null;
    }
  }
}

class DesktopProxyHttpOverrides extends HttpOverrides {
  DesktopProxyHttpOverrides(this.environment);

  final Map<String, String> environment;

  String findProxy(Uri uri) =>
      HttpClient.findProxyFromEnvironment(uri, environment: environment);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..findProxy = findProxy;
  }
}
