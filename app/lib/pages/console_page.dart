import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 内嵌完整控制台：注入会话 Cookie 后加载网关代理的 DSH 原版 UI（不再跳系统浏览器）。
class ConsolePage extends StatefulWidget {
  final String baseUrl;
  final String cookie;

  const ConsolePage({super.key, required this.baseUrl, required this.cookie});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  late final WebViewController _ctrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse('${widget.baseUrl}/'));
    _injectCookie();
  }

  Future<void> _injectCookie() async {
    try {
      final uri = Uri.parse(widget.baseUrl);
      await WebViewCookieManager().setCookie(WebViewCookie(
        name: 'gw_session',
        value: widget.cookie,
        domain: uri.host,
        path: '/',
      ));
    } catch (_) {
      // Cookie 注入失败时页面会要求手动登录，可接受
    }
  }

  Future<void> _reload() async {
    await _injectCookie();
    await _ctrl.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('完整控制台'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: '用浏览器打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => launchUrl(Uri.parse('${widget.baseUrl}/')),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _ctrl),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
