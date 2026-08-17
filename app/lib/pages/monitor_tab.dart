import 'package:flutter/material.dart';

import '../api.dart';
import '../helpers.dart';
import '../models.dart';
import 'console_page.dart';

class MonitorTab extends StatelessWidget {
  final ApiClient api;
  final GatewayStatus? status;
  final List<SessionSummary> sessions;
  final bool connLost;
  final Future<void> Function() onRefresh;
  final void Function(SessionSummary) onOpenSession;

  const MonitorTab({
    super.key,
    required this.api,
    required this.status,
    required this.sessions,
    required this.connLost,
    required this.onRefresh,
    required this.onOpenSession,
  });

  Future<void> _control(BuildContext context, String action) async {
    final ctx = context;
    try {
      await api.control(action);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('已执行：$action')),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
    await onRefresh();
  }

  Future<void> _confirmAnd(BuildContext context, String action, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认$label DSH？'),
        content: const Text('远程执行将影响电脑上的 DSH 进程。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(label)),
        ],
      ),
    );
    if (ok == true) _control(context, action);
  }

  @override
  Widget build(BuildContext context) {
    final st = status;
    final running = st?.running == true;
    final working = sessions.where((s) => s.working).toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: connLost
                              ? const Color(0xFFF39C12)
                              : (running ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C)),
                          boxShadow: [
                            BoxShadow(
                              color: (connLost
                                      ? const Color(0xFFF39C12)
                                      : (running
                                          ? const Color(0xFF2ECC71)
                                          : const Color(0xFFE74C3C)))
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        connLost
                            ? '连接中断，正在重试…'
                            : (st == null
                                ? '检测中…'
                                : (running ? 'DSH 运行中' : 'DSH 已停止')),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: connLost ? const Color(0xFFF39C12) : null,
                        ),
                      ),
                      const Spacer(),
                      Text(st?.startedByGateway == true ? '网关托管' : '',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Stat(label: '会话', value: '${st?.sessionCount ?? '-'}'),
                      _Stat(label: '工作中', value: '${working.length}'),
                      _Stat(label: '最后活动', value: relTime(st?.latestActivity)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('完整控制台'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ConsolePage(baseUrl: api.baseUrl, cookie: api.cookie),
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: running ? null : () => _control(context, 'start'),
                        child: const Text('启动'),
                      ),
                      OutlinedButton(
                        onPressed: running ? () => _confirmAnd(context, 'restart', '重启') : null,
                        child: const Text('重启'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                        onPressed: running ? () => _confirmAnd(context, 'stop', '停止') : null,
                        child: const Text('停止'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '工作中的会话',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ),
                if (working.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...working.take(8).map(
                        (s) => ListTile(
                          dense: true,
                          leading: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFF39C12),
                            ),
                          ),
                          title: Text(s.title.isEmpty ? '(无标题)' : s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${s.workspace} · ${relTime(s.lastActivity)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onOpenSession(s),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }
}
