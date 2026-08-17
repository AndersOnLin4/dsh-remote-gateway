import 'package:flutter/material.dart';

import '../store.dart';
import 'home_page.dart';
import 'login_page.dart';

/// 服务器管理：切换 / 新增 / 删除已保存的服务器。
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  List<ServerConfig> _servers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppStore.instance.servers();
    if (mounted) setState(() => _servers = list);
  }

  Future<void> _use(ServerConfig s) async {
    final store = AppStore.instance;
    await store.setActiveUrl(s.url);
    final password = await store.passwordFor(s.url);
    final cookie = await store.cookieFor(s.url);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => password != null && cookie != null
            ? HomePage(server: s, cookie: cookie, password: password)
            : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器管理')),
      body: _servers.isEmpty
          ? const Center(child: Text('还没有保存的服务器'))
          : ListView.builder(
              itemCount: _servers.length,
              itemBuilder: (context, i) {
                final s = _servers[i];
                return ListTile(
                  leading: const Icon(Icons.computer),
                  title: Text(s.name),
                  subtitle: Text(s.url),
                  onTap: () => _use(s),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await AppStore.instance.removeServer(s.url);
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}
