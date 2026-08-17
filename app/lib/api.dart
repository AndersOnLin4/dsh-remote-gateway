/// 网关 REST 客户端：与 static/app.js 使用同一套 /gw/* 接口。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int? status;
  final String message;

  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  String cookie = '';
  String password = '';

  ApiClient(this.baseUrl);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (cookie.isNotEmpty) 'Cookie': 'gw_session=$cookie',
      };

  dynamic _decode(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) throw ApiException(401, '登录已过期，请重新登录');
    if (r.statusCode != 200) throw ApiException(r.statusCode, 'HTTP ${r.statusCode}');
    return _decode(r);
  }

  Future<dynamic> _post(String path, [Object? body]) async {
    final r = await http
        .post(Uri.parse('$baseUrl$path'),
            headers: _headers, body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 401) throw ApiException(401, '登录已过期，请重新登录');
    final data = r.bodyBytes.isEmpty ? null : _decode(r);
    if (r.statusCode != 200) {
      final detail = (data is Map && data['detail'] != null) ? data['detail'].toString() : 'HTTP ${r.statusCode}';
      throw ApiException(r.statusCode, detail);
    }
    return data;
  }

  /// 登录：密码换会话 Cookie。
  Future<void> login(String pwd) async {
    final r = await http
        .post(Uri.parse('$baseUrl/gw/login'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'password': pwd}))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 401) throw ApiException(401, '密码错误');
    if (r.statusCode == 429) throw ApiException(429, '尝试次数过多，请稍后再试');
    if (r.statusCode != 200) throw ApiException(r.statusCode, '网关不可达（HTTP ${r.statusCode}）');
    var tok = '';
    for (final part in (r.headers['set-cookie'] ?? '').split(',')) {
      final p = part.trim();
      if (p.startsWith('gw_session=')) {
        tok = p.split(';').first.substring('gw_session='.length);
        break;
      }
    }
    if (tok.isEmpty) throw ApiException(0, '登录响应缺少会话 Cookie');
    cookie = tok;
    password = pwd;
  }

  Future<GatewayStatus> getStatus() async => GatewayStatus.fromJson(await _get('/gw/status'));

  Future<List<SessionSummary>> getSessions() async {
    final j = await _get('/gw/sessions');
    final list = (j is Map ? j['sessions'] : null) as List?;
    return (list ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SessionSummary.fromJson)
        .toList();
  }

  /// 会话尾段（增量协议：传 unchanged=上次文件大小，文件未变时服务端返回轻量响应）。
  Future<TailResult> getTail(String sid, {int n = 60, int? unchanged}) async {
    final q = 'n=$n${unchanged != null ? '&unchanged=$unchanged' : ''}';
    final j = await _get('/gw/session/${Uri.encodeComponent(sid)}/tail?$q');
    final entries = (j is Map ? j['entries'] : null) as List?;
    return TailResult(
      entries: (entries ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TailEntry.fromJson)
          .toList(),
      unchanged: j is Map && j['unchanged'] == true,
      fileSize: j is Map ? (j['file_size'] as num?)?.toInt() : null,
    );
  }

  Future<void> sendPrompt(String sid, String text) async {
    await _post('/gw/session/${Uri.encodeComponent(sid)}/send', {
      'text': text,
      'tz': 'Asia/Shanghai',
    });
  }

  Future<List<PendingQuestion>> getQuestions(String sid) async {
    final j = await _get('/gw/questions?sid=${Uri.encodeComponent(sid)}');
    final list = (j is Map ? j['questions'] : null) as List?;
    return (list ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PendingQuestion.fromJson)
        .toList();
  }

  Future<void> answer(String sid, String rpcId, List<Map<String, dynamic>> answers) async {
    await _post('/gw/session/${Uri.encodeComponent(sid)}/answer', {
      'rpcId': rpcId,
      'answers': answers,
    });
  }

  Future<String> getLog({int n = 300}) async {
    final j = await _get('/gw/log?n=$n');
    return (j is Map ? j['log'] ?? '' : '').toString();
  }

  Future<void> control(String action) async {
    await _post('/gw/control/$action');
  }
}
