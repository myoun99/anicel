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

  group('each cut\'s timeline zoom (F-253 → F-267)', () {
    test('round-trips through the JSON', () {
      final resume = ProjectResume(
        timelineZoom: {const CutId('c2'): 37.5, const CutId('c3'): 6},
      );
      expect(ProjectResume.fromJson(resume.toJson()).timelineZoom, {
        const CutId('c2'): 37.5,
        const CutId('c3'): 6.0,
      });
    });

    test('🚨a zoom that cannot be read is dropped ALONE', () {
      final back = ProjectResume.fromJson({
        'timelineZoom': {
          'c2': 'wide',
          'c3': -1,
          'c4': 0,
          '': 3,
          'c5': double.infinity,
          'c6': 20,
        },
      });
      expect(back.timelineZoom, {const CutId('c6'): 20.0});
      expect(
        ProjectResume.fromJson({'timelineZoom': 'wide'}).timelineZoom,
        isEmpty,
        reason: 'not a map: no zoom was saved',
      );
    });
  });

  group('the conte\'s zoom and each panel\'s scroll (F-267)', () {
    test('round-trip through the JSON', () {
      const resume = ProjectResume(
        storyboardZoom: 3.5,
        frameAxisOffsets: {'timeline': 480, 'storyboard': 96.5},
      );
      final back = ProjectResume.fromJson(resume.toJson());
      expect(back.storyboardZoom, 3.5);
      expect(back.frameAxisOffsets, {'timeline': 480.0, 'storyboard': 96.5});
    });

    test('🚨a part that cannot be read is dropped ALONE', () {
      final back = ProjectResume.fromJson({
        'storyboardZoom': 'wide',
        'frameAxisOffsets': {
          'timeline': -4,
          'xsheet': double.nan,
          '': 30,
          'storyboard': 12,
        },
      });
      expect(back.storyboardZoom, isNull);
      expect(back.frameAxisOffsets, {'storyboard': 12.0});
      expect(
        ProjectResume.fromJson({'storyboardZoom': 0}).storyboardZoom,
        isNull,
        reason: 'a zoom of nothing is no zoom',
      );
    });
  });
}
