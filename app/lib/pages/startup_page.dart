import 'package:flutter/material.dart';

import '../store.dart';
import 'home_page.dart';
import 'login_page.dart';

/// 启动页：有可用会话 → 主页；否则 → 登录页。
class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final store = AppStore.instance;
    final url = await store.activeUrl();
    final cookie = url == null ? null : await store.cookieFor(url);
    final password = url == null ? null : await store.passwordFor(url);
    // 取完整服务器配置（含备用地址）
    ServerConfig? cfg;
    for (final s in await store.servers()) {
      if (s.url == url) {
        cfg = s;
        break;
      }
    }
    cfg ??= ServerConfig(name: url ?? '', url: url ?? '');
    if (!mounted) return;
    if (url != null && cookie != null && password != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            server: cfg!,
            cookie: cookie,
            password: password,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
