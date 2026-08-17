import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_gateway/models.dart';

void main() {
  test('SessionSummary 解析', () {
    final s = SessionSummary.fromJson(const {
      'id': 's1',
      'title': '标题',
      'workspace': '工作区',
      'cwd': '',
      'lastActivity': 1234.5,
      'working': true,
      'turns': 3,
      'steps': 10,
      'decodeTokens': 2048,
      'pendingCalls': false,
    });
    expect(s.id, 's1');
    expect(s.working, true);
    expect(s.decodeTokens, 2048);
  });

  test('QuestionItem 解析', () {
    final q = QuestionItem.fromJson(const {
      'id': 'q1',
      'question': '问题',
      'header': 'H',
      'multiSelect': true,
      'options': [
        {'id': 'o1', 'label': 'A', 'description': ''},
        {'id': 'o2', 'label': 'B', 'description': ''},
      ],
    });
    expect(q.multiSelect, true);
    expect(q.options.length, 2);
    expect(q.options.first.label, 'A');
  });
}
