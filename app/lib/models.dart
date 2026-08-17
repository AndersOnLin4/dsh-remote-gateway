/// 数据模型：网关 REST 接口的 JSON 解析。
library;

class SessionSummary {
  final String id;
  final String title;
  final String workspace;
  final String cwd;
  final double? lastActivity;
  final bool working;
  final int turns;
  final int steps;
  final int decodeTokens;
  final bool pendingCalls;

  SessionSummary({
    required this.id,
    required this.title,
    required this.workspace,
    required this.cwd,
    required this.lastActivity,
    required this.working,
    required this.turns,
    required this.steps,
    required this.decodeTokens,
    required this.pendingCalls,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> j) => SessionSummary(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        workspace: j['workspace'] ?? '',
        cwd: j['cwd'] ?? '',
        lastActivity: (j['lastActivity'] as num?)?.toDouble(),
        working: j['working'] == true,
        turns: (j['turns'] as num?)?.toInt() ?? 0,
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        decodeTokens: (j['decodeTokens'] as num?)?.toInt() ?? 0,
        pendingCalls: j['pendingCalls'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'workspace': workspace,
        'cwd': cwd,
        'lastActivity': lastActivity,
        'working': working,
        'turns': turns,
        'steps': steps,
        'decodeTokens': decodeTokens,
        'pendingCalls': pendingCalls,
      };
}

class QuestionOption {
  final String id;
  final String label;
  final String description;

  QuestionOption({required this.id, required this.label, required this.description});

  factory QuestionOption.fromJson(Map<String, dynamic> j) => QuestionOption(
        id: j['id'] ?? '',
        label: j['label'] ?? '',
        description: j['description'] ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'description': description};
}

class QuestionItem {
  final String id;
  final String question;
  final String header;
  final bool multiSelect;
  final List<QuestionOption> options;

  QuestionItem({
    required this.id,
    required this.question,
    required this.header,
    required this.multiSelect,
    required this.options,
  });

  factory QuestionItem.fromJson(Map<String, dynamic> j) => QuestionItem(
        id: j['id'] ?? '',
        question: j['question'] ?? '',
        header: j['header'] ?? '',
        multiSelect: j['multiSelect'] == true,
        options: ((j['options'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(QuestionOption.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'header': header,
        'multiSelect': multiSelect,
        'options': options.map((o) => o.toJson()).toList(),
      };
}

/// 会话尾段条目（网关侧已过滤：只保留提问 / 最终回答 / 选择题）。
class TailEntry {
  final String role; // user | assistant | question
  final String text;
  final double? time;
  final int? turn;
  final List<QuestionItem> questions;

  TailEntry({
    required this.role,
    required this.text,
    required this.time,
    required this.turn,
    required this.questions,
  });

  factory TailEntry.fromJson(Map<String, dynamic> j) => TailEntry(
        role: j['role'] ?? '',
        text: j['text'] ?? '',
        time: (j['time'] as num?)?.toDouble(),
        turn: (j['turn'] as num?)?.toInt(),
        questions: ((j['questions'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(QuestionItem.fromJson)
            .toList(),
      );
}

/// 挂起的选择题（/gw/questions 返回）。
class PendingQuestion {
  final String rpcId;
  final List<QuestionItem> questions;

  PendingQuestion({required this.rpcId, required this.questions});

  factory PendingQuestion.fromJson(Map<String, dynamic> j) => PendingQuestion(
        rpcId: j['rpcId'] ?? '',
        questions: ((j['questions'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(QuestionItem.fromJson)
            .toList(),
      );
}

class GatewayStatus {
  final bool running;
  final String dshUrl;
  final int sessionCount;
  final double? latestActivity;
  final String latestWorkspace;
  final bool startedByGateway;

  GatewayStatus({
    required this.running,
    required this.dshUrl,
    required this.sessionCount,
    required this.latestActivity,
    required this.latestWorkspace,
    required this.startedByGateway,
  });

  factory GatewayStatus.fromJson(Map<String, dynamic> j) => GatewayStatus(
        running: j['running'] == true,
        dshUrl: j['dsh_url'] ?? '',
        sessionCount: (j['session_count'] as num?)?.toInt() ?? 0,
        latestActivity: (j['latest_activity'] as num?)?.toDouble(),
        latestWorkspace: j['latest_workspace'] ?? '',
        startedByGateway: j['started_by_gateway'] == true,
      );
}

/// SSE 事件。
class GwEvent {
  final String type;
  final Map<String, dynamic> data;
  final double ts;

  GwEvent(this.type, this.data, this.ts);
}

/// 会话尾段请求结果（含增量协议标志）。
class TailResult {
  final List<TailEntry> entries;
  final bool unchanged;
  final int? fileSize;

  TailResult({required this.entries, required this.unchanged, required this.fileSize});
}
