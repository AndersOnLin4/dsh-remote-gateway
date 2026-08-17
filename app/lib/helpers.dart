/// 小工具：时间格式化等。
library;

String relTime(double? ts) {
  if (ts == null || ts <= 0) return '—';
  final diff = DateTime.now().millisecondsSinceEpoch / 1000 - ts;
  if (diff < 60) return '刚刚';
  if (diff < 3600) return '${(diff / 60).floor()} 分钟前';
  if (diff < 86400) return '${(diff / 3600).floor()} 小时前';
  if (diff < 86400 * 30) return '${(diff / 86400).floor()} 天前';
  final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  final two = (int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String fmtTokens(int tokens) {
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
  if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
  return '$tokens';
}

String questionPreview(Map<String, dynamic> data) {
  final qs = (data['questions'] as List?) ?? const [];
  if (qs.isEmpty) return 'agent 正在向你提问';
  final first = qs.first is Map ? qs.first as Map<String, dynamic> : const {};
  return (first['question'] ?? first['header'] ?? 'agent 正在向你提问').toString();
}
