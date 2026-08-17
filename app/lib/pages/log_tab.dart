import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';

class LogTab extends StatefulWidget {
  final ApiClient api;

  const LogTab({super.key, required this.api});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  String _log = '加载中…';
  bool _autoScroll = true;
  Timer? _timer;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    _scrollCtrl.addListener(() {
      final atBottom = _scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 60;
      if (!atBottom && _autoScroll) {
        setState(() => _autoScroll = false);
      } else if (atBottom && !_autoScroll) {
        setState(() => _autoScroll = true);
      }
    });
  }

  Future<void> _load() async {
    try {
      final log = await widget.api.getLog(n: 300);
      if (!mounted) return;
      setState(() => _log = log.isEmpty ? '（暂无日志）' : log);
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _log = '读取日志失败：$e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text('DSH 日志（每 8 秒刷新）',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                    size: 16),
                label: Text(_autoScroll ? '自动滚动' : '已暂停', style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() => _autoScroll = !_autoScroll);
                  if (_autoScroll && _scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: SelectableText(
                _log,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
