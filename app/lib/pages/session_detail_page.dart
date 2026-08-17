import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../events.dart';
import '../helpers.dart';
import '../models.dart';

/// 会话详情：过滤后的气泡对话 + 挂起选择题作答 + 直接回复。
/// 通过共享 EventService 接收 session-updated 推送，新消息秒级同步。
class SessionDetailPage extends StatefulWidget {
  final ApiClient api;
  final EventService events;
  final SessionSummary session;

  const SessionDetailPage({
    super.key,
    required this.api,
    required this.events,
    required this.session,
  });

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  List<TailEntry> _entries = [];
  List<PendingQuestion> _questions = [];
  final Map<String, Set<String>> _selected = {}; // questionId -> option labels
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  Timer? _qTimer;
  Timer? _tailTimer;
  Timer? _fastTimer;
  bool _sending = false;
  bool _submitting = false;
  String? _error;
  int? _fileSize; // 上次拿到的会话文件大小（增量协议）

  @override
  void initState() {
    super.initState();
    widget.events.addListener(_onGwEvent);
    _loadTail();
    _qTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollQuestions());
    _tailTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadTail(silent: true));
  }

  /// 共享事件流：本会话有新写入 → 立刻刷新；新问题 → 立刻拉取。
  void _onGwEvent(GwEvent ev) {
    final sid = (ev.data['sid'] ?? '').toString();
    if (sid.isEmpty || sid != widget.session.id) return;
    switch (ev.type) {
      case 'session-updated':
        _loadTail(silent: true);
        break;
      case 'question':
        _pollQuestions();
        break;
    }
  }

  @override
  void dispose() {
    widget.events.removeListener(_onGwEvent);
    _qTimer?.cancel();
    _tailTimer?.cancel();
    _fastTimer?.cancel();
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTail({bool silent = false}) async {
    try {
      final r = await widget.api.getTail(widget.session.id, n: 60, unchanged: _fileSize);
      if (!mounted) return;
      if (r.unchanged) {
        // 文件未变化：保留现有内容，零渲染开销
        if (_error != null) setState(() => _error = null);
        return;
      }
      setState(() {
        _entries = r.entries;
        _fileSize = r.fileSize;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      if (e is ApiException && e.status == 401) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = '加载失败：$e');
    }
  }

  Future<void> _pollQuestions() async {
    try {
      final qs = await widget.api.getQuestions(widget.session.id);
      if (!mounted) return;
      setState(() => _questions = qs);
      if (qs.isEmpty) _fastTimer?.cancel();
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendPrompt(widget.session.id, text);
      _replyCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已发送，等待回复…')));
      }
      await _loadTail();
      _fastPoll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 发送后快速追更：每 3 秒直到出现新内容或超时。
  void _fastPoll() {
    _fastTimer?.cancel();
    var tries = 0;
    final baseCount = _entries.length;
    _fastTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      tries++;
      try {
        final r = await widget.api.getTail(widget.session.id, n: 8);
        if (r.entries.length > baseCount || tries >= 30) t.cancel();
        if (!mounted) return;
        if (!r.unchanged) {
          setState(() {
            if (r.entries.length > baseCount) _entries = r.entries;
            _fileSize = r.fileSize ?? _fileSize;
          });
        }
      } catch (_) {
        if (tries >= 30) t.cancel();
      }
    });
  }

  void _toggleOption(QuestionItem q, String label, bool multi) {
    setState(() {
      final sel = _selected.putIfAbsent(q.id, () => <String>{});
      if (multi) {
        if (sel.contains(label)) {
          sel.remove(label);
        } else {
          sel.add(label);
        }
      } else {
        sel.clear();
        sel.add(label);
      }
    });
  }

  Future<void> _submitAnswers(PendingQuestion pq) async {
    if (_submitting) return;
    final answers = <Map<String, dynamic>>[];
    var any = false;
    for (final q in pq.questions) {
      final sel = _selected[q.id] ?? const <String>{};
      if (sel.isNotEmpty) any = true;
      answers.add({'id': q.id, 'selected': sel.toList()});
    }
    if (!any) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择答案')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.api.answer(widget.session.id, pq.rpcId, answers);
      setState(() => _questions = []);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✓ 已提交，等待 agent 继续')));
      _fastPoll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.title.isEmpty ? '(无标题)' : widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                ..._entries.map(_bubble),
                ..._questions.map(_questionCard),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '输入回复，回车发送',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(TailEntry e) {
    if (e.role == 'question') {
      return Card(
        color: const Color(0xFF3A2E14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📋 agent 提问', style: TextStyle(color: Colors.orange.shade300, fontSize: 12)),
              const SizedBox(height: 6),
              Text(e.text),
            ],
          ),
        ),
      );
    }
    final isUser = e.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1F6F43) : const Color(0xFF262B36),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.text),
            const SizedBox(height: 2),
            Text(
              relTime(e.time),
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(PendingQuestion pq) {
    return Card(
      color: const Color(0xFF3A2E14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔔 agent 正在向你提问（请选择）',
                style: TextStyle(color: Colors.orange.shade300, fontSize: 12)),
            const SizedBox(height: 8),
            ...pq.questions.map((q) {
              final sel = _selected[q.id] ?? const <String>{};
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.question.isEmpty ? (q.header.isEmpty ? q.id : q.header) : q.question,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (q.options.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: q.options
                          .map((o) => FilterChip(
                                label: Text(o.label),
                                selected: sel.contains(o.label),
                                onSelected: (v) => _toggleOption(q, o.label, q.multiSelect),
                                selectedColor: Colors.orange.shade800,
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _submitting ? null : () => _submitAnswers(pq),
                child: Text(_submitting ? '提交中…' : '提交选择'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
