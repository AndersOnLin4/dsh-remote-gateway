/// 服务器配置与凭据存储：服务器列表在 SharedPreferences，密码/Cookie 在 Android Keystore 加密区。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  final String name;
  final String url;
  final List<String> altUrls; // 备用地址：主地址连不上时依次尝试

  ServerConfig({required this.name, required this.url, this.altUrls = const []});

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        name: j['name'] ?? '',
        url: j['url'] ?? '',
        altUrls: ((j['altUrls'] as List?) ?? []).whereType<String>().toList(),
      );

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'altUrls': altUrls};
}

class AppStore {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _serversKey = 'servers';
  static const _activeKey = 'active_url';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---------- 服务器列表 ----------

  Future<List<ServerConfig>> servers() async {
    final raw = _prefs?.getString(_serversKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return ((jsonDecode(raw) as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ServerConfig.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsertServer(ServerConfig c) async {
    final list = await servers();
    list.removeWhere((s) => s.url == c.url);
    list.insert(0, c);
    await _prefs?.setString(_serversKey, jsonEncode(list.map((s) => s.toJson()).toList()));
  }

  Future<void> removeServer(String url) async {
    final list = await servers();
    list.removeWhere((s) => s.url == url);
    await _prefs?.setString(_serversKey, jsonEncode(list.map((s) => s.toJson()).toList()));
    await clearCredentials(url);
  }

  Future<String?> activeUrl() async => _prefs?.getString(_activeKey);

  Future<void> setActiveUrl(String url) async => _prefs?.setString(_activeKey, url);

  // ---------- 凭据（Keystore 加密） ----------

  Future<String?> passwordFor(String url) async => _secure.read(key: 'pass_$url');

  Future<void> savePassword(String url, String pwd) async =>
      _secure.write(key: 'pass_$url', value: pwd);

  Future<String?> cookieFor(String url) async => _secure.read(key: 'cookie_$url');

  Future<void> saveCookie(String url, String cookie) async =>
      _secure.write(key: 'cookie_$url', value: cookie);

  Future<void> clearCredentials(String url) async {
    await _secure.delete(key: 'pass_$url');
    await _secure.delete(key: 'cookie_$url');
  }
}
