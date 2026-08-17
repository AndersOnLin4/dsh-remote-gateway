/// SSE 事件流客户端：订阅 /gw/events，自动重连。
/// - 200：正常流；断线后 1s 起步指数退避（上限 30s）
/// - 401：会话过期 → 停止并回调 auth-expired
/// - 其他状态码（如网关未升级、404）：低频重试（60s），不刷爆网关也不造成界面闪烁
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class EventService {
  final String baseUrl;
  final String cookie;

  final List<void Function(GwEvent)> _listeners = [];
  void Function()? onConnected;
  void Function()? onDisconnected;

  bool _running = false;

  EventService({required this.baseUrl, required this.cookie});

  void addListener(void Function(GwEvent) fn) => _listeners.add(fn);

  void removeListener(void Function(GwEvent) fn) => _listeners.remove(fn);

  void _emit(GwEvent ev) {
    for (final fn in List.of(_listeners)) {
      fn(ev);
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  void stop() {
    _running = false;
  }

  Future<void> _delay(int seconds) => Future<void>.delayed(Duration(seconds: seconds));

  Future<void> _loop() async {
    var backoff = 1;
    while (_running) {
      var client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse('$baseUrl/gw/events'));
        req.headers['Cookie'] = 'gw_session=$cookie';
        final resp = await client.send(req).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 401) {
          _emit(GwEvent('auth-expired', const {}, 0));
          _running = false;
          break;
        }
        if (resp.statusCode != 200) {
          // 端点不存在（网关未升级）或临时异常：低频重试
          try {
            await resp.stream.drain<void>();
          } catch (_) {}
          await _delay(60);
          continue;
        }
        onConnected?.call();
        await for (final line
            in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!_running) break;
          if (line.startsWith('data: ')) {
            try {
              final j = jsonDecode(line.substring(6)) as Map<String, dynamic>;
              _emit(GwEvent(
                (j['type'] ?? '').toString(),
                (j['data'] is Map<String, dynamic>)
                    ? j['data'] as Map<String, dynamic>
                    : const {},
                ((j['ts'] as num?)?.toDouble() ?? 0),
              ));
            } catch (_) {}
          }
        }
        backoff = 1;
      } catch (_) {
        // 网络抖动：退避重连
      } finally {
        client.close();
      }
      if (_running) {
        onDisconnected?.call();
        await _delay(backoff);
        backoff = (backoff * 2).clamp(1, 30);
      }
    }
  }
}
