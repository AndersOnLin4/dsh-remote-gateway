import 'package:flutter/material.dart';

import '../helpers.dart';
import '../models.dart';

class SessionsTab extends StatelessWidget {
  final List<SessionSummary> sessions;
  final Future<void> Function() onRefresh;
  final void Function(SessionSummary) onOpenSession;

  const SessionsTab({
    super.key,
    required this.sessions,
    required this.onRefresh,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 200),
            Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sessions.length,
        itemBuilder: (context, i) {
          final s = sessions[i];
          return ListTile(
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.working ? const Color(0xFFF39C12) : Colors.grey.shade700,
                boxShadow: s.working
                    ? [
                        BoxShadow(
                          color: const Color(0xFFF39C12).withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            title: Text(
              s.title.isEmpty ? '(无标题)' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${s.workspace} · ${relTime(s.lastActivity)} · ${s.turns} 轮 · ${fmtTokens(s.decodeTokens)} tok',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenSession(s),
          );
        },
      ),
    );
  }
}
