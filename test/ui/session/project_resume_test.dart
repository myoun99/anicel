import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_sections.dart';
import 'package:anicel/src/ui/session/media_file_views.dart';
import 'package:anicel/src/ui/session/project_resume.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';

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

  group('the conte\'s zoom and each panel\'s scroll, each timeline\'s and '
      'each cut\'s (F-267 · H78)', () {
    test('round-trip through the JSON', () {
      const resume = ProjectResume(
        conteZooms: {'timeline-1': 3.5, 'timeline-2': 9},
        frameAxisOffsets: {
          'timeline@c1': 480,
          'timeline@c2': 12,
          'storyboard@timeline-1': 96.5,
        },
        layerAxisOffsets: {'timeline@c1': 120, 'xsheet@c2': 64.5},
      );
      final back = ProjectResume.fromJson(resume.toJson());
      expect(back.conteZooms, {'timeline-1': 3.5, 'timeline-2': 9.0});
      expect(back.frameAxisOffsets, {
        'timeline@c1': 480.0,
        'timeline@c2': 12.0,
        'storyboard@timeline-1': 96.5,
      });
      expect(back.layerAxisOffsets, {'timeline@c1': 120.0, 'xsheet@c2': 64.5});
    });

    test('🚨a part that cannot be read is dropped ALONE', () {
      final back = ProjectResume.fromJson({
        'conteZooms': {'timeline-1': 'wide', 'timeline-2': 0, 'timeline-3': 4},
        'frameAxisOffsets': {
          'timeline': -4,
          'xsheet': double.nan,
          '': 30,
          'storyboard': 12,
        },
        'layerAxisOffsets': {
          'timeline': 'down',
          'xsheet': 0,
          'storyboard': 40,
        },
      });
      expect(back.conteZooms, {'timeline-3': 4.0});
      expect(back.frameAxisOffsets, {'storyboard': 12.0});
      expect(back.layerAxisOffsets, {'storyboard': 40.0});
      expect(
        ProjectResume.fromJson({'conteZooms': 3.5}).conteZooms,
        isEmpty,
        reason: 'not a map: no zoom was saved',
      );
    });
  });

  group('the rulers\' count (F-354 · I-81)', () {
    test('round-trips through the JSON, each of the three', () {
      for (final view in FrameRulerView.values) {
        final back = ProjectResume.fromJson(
          ProjectResume(rulerView: view).toJson(),
        );
        expect(back.rulerView, view);
      }
      expect(
        ProjectResume.none.toJson().containsKey('frameRuler'),
        isFalse,
        reason: 'frames, the count a new project has, is not written',
      );
    });

    test('🚨a count that cannot be read counts frames', () {
      for (final unreadable in ['true', 1, null, 'page']) {
        expect(
          ProjectResume.fromJson({'frameRuler': unreadable}).rulerView,
          FrameRulerView.frames,
          reason: '$unreadable',
        );
      }
    });
  });

  group('the header graphs and the lanes pinned to them (F-360-Q1)', () {
    test('round-trip through the JSON — each graph\'s height, what it '
        'plots, whether it is enlarged, whether its pen is up, whether its '
        'transform box is shown and whether its snap is on', () {
      const graphs = LaneGraphsView(
        open: {
          'a|transform-group': LaneGraph(),
          'b|fx-group:1': LaneGraph(
            extent: 240,
            mode: LaneGraphMode.speed,
            enlarged: true,
            pen: true,
            transformBox: false,
            snap: true,
          ),
        },
        pinned: {'a|x', 'b|fx:1:size'},
      );
      expect(
        ProjectResume.fromJson(
          const ProjectResume(laneGraphs: graphs).toJson(),
        ).laneGraphs,
        graphs,
      );
    });

    test('🚨a part that cannot be read is dropped ALONE', () {
      final back = ProjectResume.fromJson({
        'laneGraphs': {
          'a|t': 'open',
          '': <String, Object?>{},
          'b|t': {
            'extent': -5,
            'mode': 'sideways',
            'enlarged': 'yes',
            'pen': 'yes',
            'transformBox': 'no',
            'snap': 'yes',
          },
          'c|t': {'extent': 120.5},
        },
        'pinnedLanes': ['a|x', 7, '', 'b|y'],
      });
      expect(back.laneGraphs.open, {
        'b|t': const LaneGraph(),
        'c|t': const LaneGraph(extent: 120.5),
      }, reason: 'not a graph, no key: no graph — a field read wrong: that '
          'field as on a graph nobody touched');
      expect(back.laneGraphs.pinned, {'a|x', 'b|y'});
      expect(
        ProjectResume.fromJson({
          'laneGraphs': 'open',
          'pinnedLanes': 'a|x',
        }).laneGraphs,
        LaneGraphsView.none,
        reason: 'not a map, not a list: nothing was saved',
      );
    });
  });

  group('the sections the panels hide (H77)', () {
    test('round-trip through the JSON, each section alone and together', () {
      for (final hidden in [
        for (final section in TimelineSection.values) {section},
        {TimelineSection.se, TimelineSection.camera},
      ]) {
        expect(
          ProjectResume.fromJson(
            ProjectResume(hiddenSections: hidden).toJson(),
          ).hiddenSections,
          hidden,
        );
      }
      expect(
        ProjectResume.none.toJson().containsKey('hiddenSections'),
        isFalse,
        reason: 'every section shown, as a new project shows them, is not '
            'written',
      );
    });

    test('🚨a name that cannot be read is dropped ALONE', () {
      expect(
        ProjectResume.fromJson({
          'hiddenSections': ['se', 7, 'sideways', ''],
        }).hiddenSections,
        {TimelineSection.se},
      );
      expect(
        ProjectResume.fromJson({'hiddenSections': 'se'}).hiddenSections,
        isEmpty,
        reason: 'not a list: nothing was saved',
      );
    });
  });

  group('each file\'s view in the viewers (F-382)', () {
    test('round-trips through the JSON', () {
      final resume = ProjectResume(
        mediaFileViews: {
          'C:/work/conte.pdf': MediaFileView(
            page: 3,
            framings: {
              'media-viewer': CanvasViewport(zoom: 2, panX: -40, panY: 12.5),
            },
          ),
          'C:/work/pose.png': MediaFileView(
            framings: {'media-viewer-sub': CanvasViewport(zoom: 0.5)},
          ),
        },
      );
      expect(
        ProjectResume.fromJson(resume.toJson()).mediaFileViews,
        resume.mediaFileViews,
      );
    });

    test('🚨a part that cannot be read is dropped ALONE', () {
      final back = ProjectResume.fromJson({
        'mediaFileViews': {
          'C:/a.pdf': {
            'page': 'three',
            'framings': {
              'media-viewer': {'zoom': 2},
            },
          },
          'C:/b.pdf': {
            'page': 2,
            'framings': {
              'media-viewer': {'zoom': 'wide'},
              'media-viewer-sub': {'zoom': 0},
              '': {'zoom': 1},
            },
          },
          'C:/c.pdf': {'page': -1},
          'C:/d.pdf': 'nothing',
          '': {'page': 4},
        },
      });
      expect(back.mediaFileViews, {
        'C:/a.pdf': MediaFileView(
          framings: {'media-viewer': CanvasViewport(zoom: 2)},
        ),
        'C:/b.pdf': const MediaFileView(page: 2),
      }, reason: 'a page nobody can read, a framing nobody can read, a file '
          'with nothing left or with no name — each falls alone');
    });

    test('two views are one only where each viewer framed the file alike — '
        'what the two above stand on', () {
      MediaFileView framed(Map<String, double> zooms) => MediaFileView(
        framings: {
          for (final MapEntry(key: viewer, value: zoom) in zooms.entries)
            viewer: CanvasViewport(zoom: zoom),
        },
      );
      final atTwo = framed({'media-viewer': 2});
      expect(atTwo, framed({'media-viewer': 2}));
      expect(atTwo, isNot(framed({'media-viewer': 3})));
      expect(atTwo, isNot(framed({'media-viewer-sub': 2})));
      expect(atTwo, isNot(framed({'media-viewer': 2, 'media-viewer-sub': 2})));
    });
  });
}
