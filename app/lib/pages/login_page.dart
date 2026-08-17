import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import 'home_page.dart';
import 'servers_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _urlCtrl = TextEditingController(text: 'http://');
  final _altCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _altCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _norm(String u) {
    var x = u.trim();
    while (x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  List<String> _candidates() {
    final list = <String>[];
    final primary = _norm(_urlCtrl.text);
    if (primary.startsWith('http://') || primary.startsWith('https://')) {
      list.add(primary);
    }
    for (final a in _altCtrl.text.split(',')) {
      final x = _norm(a);
      if ((x.startsWith('http://') || x.startsWith('https://')) && !list.contains(x)) {
        list.add(x);
      }
    }
    return list;
  }

  Future<void> _login() async {
    final candidates = _candidates();
    if (candidates.isEmpty) {
      setState(() => _error = '地址需以 http:// 或 https:// 开头');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? working;
    String lastErr = '';
    try {
      for (final url in candidates) {
        final api = ApiClient(url);
        try {
          await api.login(_passCtrl.text);
        } on ApiException catch (e) {
          if (e.status == 401) rethrow; // 密码错误是全局性的，不换地址重试
          lastErr = '${url.split('://').last}: ${e.message}';
          continue;
        } on TimeoutException {
          lastErr = '${url.split('://').last}: 超时';
          continue;
        } catch (e) {
          lastErr = '${url.split('://').last}: $e';
          continue;
        }
        working = url;
        final store = AppStore.instance;
        final name = _nameCtrl.text.trim().isEmpty ? Uri.parse(url).host : _nameCtrl.text.trim();
        final alts = candidates.where((u) => u != url).toList();
        final cfg = ServerConfig(name: name, url: url, altUrls: alts);
        await store.upsertServer(cfg);
        await store.setActiveUrl(url);
        await store.savePassword(url, _passCtrl.text);
        await store.saveCookie(url, api.cookie);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(server: cfg, cookie: api.cookie, password: api.password),
          ),
        );
        return;
      }
      setState(() => _error = '所有地址都无法连接（$lastErr）\n'
          '提示：局域网地址如 http://192.168.31.189:8080；外网 HTTPS 地址需手机 Tailscale 已开启');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSH 远程网关'),
        actions: [
          IconButton(
            tooltip: '服务器管理',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServersPage()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text('登录到你的网关',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('主地址连不上时自动尝试备用地址',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '主地址（含端口）',
                hintText: 'https://node.tail4e2630.ts.net',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _altCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '备用地址（可选，逗号分隔）',
                hintText: 'http://192.168.31.189:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '备注名（可选）',
                hintText: '家里的电脑',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问密码',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _login,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
