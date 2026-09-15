import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/session/project_resume.dart';

/// F-123: where the work stood travels as a JSON map beside the project,
/// and every part of it answers for itself.
void main() {
  test('a resume point round-trips through its JSON', () {
    const resume = ProjectResume(
      cutId: CutId('c2'),
      layerId: LayerId('b'),
      frameIndex: 5,
      tools: {'tool': 'eraser'},
    );
    final back = ProjectResume.fromJson(resume.toJson());
    expect(back.cutId, const CutId('c2'));
    expect(back.layerId, const LayerId('b'));
    expect(back.frameIndex, 5);
    expect(back.tools, {'tool': 'eraser'});
  });

  test('nothing saved writes nothing', () {
    expect(ProjectResume.none.toJson(), isEmpty);
  });

  test('🚨each unreadable part falls back alone — the rest still lands', () {
    final back = ProjectResume.fromJson({
      'cutId': 7,
      'layerId': 'b',
      'frameIndex': -3,
      'tools': 'brush',
    });
    expect(back.cutId, isNull, reason: 'not a string: no cut was saved');
    expect(back.layerId, const LayerId('b'), reason: 'the readable part lands');
    expect(back.frameIndex, 0, reason: 'a negative frame is no frame');
    expect(back.tools, isEmpty, reason: 'not a map: no tools were saved');
  });
}
