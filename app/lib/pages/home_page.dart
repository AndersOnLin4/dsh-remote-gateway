import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../events.dart';
import '../helpers.dart';
import '../models.dart';
import '../notify.dart';
import '../store.dart';
import 'log_tab.dart';
import 'login_page.dart';
import 'monitor_tab.dart';
import 'session_detail_page.dart';
import 'sessions_tab.dart';

class HomePage extends StatefulWidget {
  final ServerConfig server;
  final String cookie;
  final String password;

  const HomePage({
    super.key,
    required this.server,
    required this.cookie,
    required this.password,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ApiClient api;
  late EventService events;
  late ServerConfig _server;

  int _tab = 0;
  Timer? _timer;
  GatewayStatus? status;
  List<SessionSummary> sessions = [];
  bool connLost = false;
  int _failedCount = 0;
  bool _switching = false;
  final Set<String> _notifiedRpcIds = {};

  @override
  void initState() {
    super.initState();
    _server = widget.server;
    api = ApiClient(_server.url)
      ..cookie = widget.cookie
      ..password = widget.password;
    events = EventService(baseUrl: _server.url, cookie: widget.cookie)
      ..onConnected = () {
        if (mounted) setState(() => connLost = false);
      }
      ..onDisconnected = () {
        if (mounted) setState(() => connLost = true);
      }
      ..start();
    events.addListener(_onEvent);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(silent: true));
  }

  void _onEvent(GwEvent ev) {
    switch (ev.type) {
      case 'question':
        if (ev.data['action'] == 'requested') {
          // 只对 60 秒内的新鲜事件弹通知，且同一 rpcId 只通知一次
          final rpcId = (ev.data['rpcId'] ?? '').toString();
          final ageSec = DateTime.now().millisecondsSinceEpoch / 1000 - ev.ts;
          final fresh = ageSec.abs() < 60;
          if (fresh && rpcId.isNotEmpty && _notifiedRpcIds.add(rpcId)) {
            NotificationService.instance.show('agent 正在向你提问', questionPreview(ev.data));
          }
          if (_notifiedRpcIds.length > 100) _notifiedRpcIds.clear();
          _refresh(silent: true);
        }
        break;
      case 'status':
        if (mounted) {
          setState(() {
            status = GatewayStatus.fromJson(ev.data);
            connLost = false;
          });
        }
        break;
      case 'heartbeat':
        if (mounted && connLost) setState(() => connLost = false);
        break;
      case 'auth-expired':
        _logout();
        break;
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final st = await api.getStatus();
      final ss = await api.getSessions();
      if (!mounted) return;
      setState(() {
        status = st;
        sessions = ss;
        connLost = false;
        _failedCount = 0;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 401) {
        _logout();
        return;
      }
      _failedCount++;
      if (!silent) setState(() => connLost = true);
      // 连续 3 次失败（约 30 秒）→ 自动尝试备用地址
      if (_failedCount >= 3) {
        _failedCount = 0;
        _switchAlt();
      }
    }
  }

  /// 运行时切换备用地址：主地址失联时逐个尝试，成功即无缝接管。
  Future<void> _switchAlt() async {
    if (_switching) return;
    final alts = List<String>.from(_server.altUrls);
    if (alts.isEmpty) return;
    _switching = true;
    try {
      for (final alt in alts) {
        final api2 = ApiClient(alt)..password = widget.password;
        try {
          await api2.login(widget.password);
        } catch (_) {
          continue;
        }
        events.stop();
        setState(() {
          _server = ServerConfig(
            name: _server.name,
            url: alt,
            altUrls: [..._server.altUrls.where((u) => u != alt), _server.url],
          );
          api = api2;
          events = EventService(baseUrl: alt, cookie: api2.cookie)
            ..onConnected = () {
              if (mounted) setState(() => connLost = false);
            }
            ..onDisconnected = () {
              if (mounted) setState(() => connLost = true);
            }
            ..start();
          events.addListener(_onEvent);
          connLost = false;
        });
        final store = AppStore.instance;
        await store.setActiveUrl(alt);
        await store.saveCookie(alt, api2.cookie);
        await store.upsertServer(_server);
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已自动切换连接地址：$alt')),
          );
        }
        return;
      }
    } finally {
      _switching = false;
    }
  }

  Future<void> _logout() async {
    events.stop();
    _timer?.cancel();
    await AppStore.instance.saveCookie(_server.url, '');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (r) => false,
    );
  }

  @override
  void dispose() {
    events.removeListener(_onEvent);
    events.stop();
    _timer?.cancel();
    super.dispose();
  }

  void _openSession(SessionSummary s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionDetailPage(api: api, events: events, session: s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_server.name, style: const TextStyle(fontSize: 16)),
            Text(
              '${_server.url}${connLost ? '（连接中断，重试中…）' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: connLost ? Colors.orange : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          MonitorTab(
            api: api,
            status: status,
            sessions: sessions,
            connLost: connLost,
            onRefresh: _refresh,
            onOpenSession: _openSession,
          ),
          SessionsTab(
            sessions: sessions,
            onRefresh: _refresh,
            onOpenSession: _openSession,
          ),
          LogTab(api: api),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: '监控'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: '会话'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '日志'),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('将清除本机保存的会话，服务器配置与密码保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) _logout();
  }
}
