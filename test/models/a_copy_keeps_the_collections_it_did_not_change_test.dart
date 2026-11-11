import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): a copy of a
/// model hands back, as themselves, the collections it did not change —
/// and freezes the ones it did, so changing what it was handed changes
/// nothing. A track that took one stroke in one cut came back with a new
/// `seLayers`, `effects` and `expandedLaneGroups` each, and the conte read
/// every lane list it keeps by them again.
///
/// Every model freezes through `frozenList` · `frozenSet` · `frozenMap`
/// (the scan `a_model_freezes_through_one_helper_test.dart` holds that);
/// these pin the copies that read through it — and the constructors that
/// BUILD a collection from the one they are given, which keep it only by
/// asking whether what they built is what they were given.
void main() {
  Stroke stroke() => Stroke(
    id: const StrokeId('stroke'),
    points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
    brushSettings: BrushSettings(),
  );
  Frame frame() =>
      Frame(id: const FrameId('frame'), duration: 1, strokes: [stroke()]);
  LayerEffect effect() =>
      LayerEffect(id: const EffectId('blur'), kind: EffectKind.blur);
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [frame()],
    effects: [effect()],
    expandedLaneGroups: const {'transform'},
  );
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    layers: [layer('$id-a')],
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
  );
  Track track() => Track(
    id: const TrackId('track'),
    name: 'Track',
    cuts: [cut('cut')],
    seLayers: [layer('s1'), layer('s2')],
    effects: [effect()],
    expandedLaneGroups: const {'fx'},
  );

  group('🚨a track', () {
    test('copied, hands back every collection it did not change', () {
      final before = track();
      final after = before.copyWith(cuts: [cut('another')]);
      expect(after.seLayers, same(before.seLayers));
      expect(after.effects, same(before.effects));
      expect(after.expandedLaneGroups, same(before.expandedLaneGroups));
      expect(before.copyWith(name: 'again').cuts, same(before.cuts));
    });

    test('copied, freezes the one it changed — the hand that gave it '
        'changes nothing', () {
      final before = track();
      final given = [cut('another')];
      final after = before.copyWith(cuts: given);
      expect(after.cuts, isNot(same(given)));
      expect(after.cuts, isNot(same(before.cuts)));
      given.add(cut('third'));
      expect([for (final cut in after.cuts) cut.id], [const CutId('another')]);
      expect(() => after.cuts.add(cut('fourth')), throwsUnsupportedError);
    });

    test('made, freezes what it is given — the hand that gave it changes '
        'nothing', () {
      final cuts = [cut('cut')];
      final groups = {'fx'};
      final made = Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: cuts,
        expandedLaneGroups: groups,
      );
      cuts.add(cut('another'));
      groups.add('twirled');
      expect(made.cuts, hasLength(1));
      expect(made.expandedLaneGroups, {'fx'});
    });
  });

  test('a cut, a layer, a frame and a stroke hand back what they did not '
      'change', () {
    final cut0 = cut('cut');
    expect(cut0.copyWith(name: 'again').layers, same(cut0.layers));

    final layer0 = layer('layer');
    final layer1 = layer0.copyWith(name: 'again');
    expect(layer1.frames, same(layer0.frames));
    expect(layer1.audioClips, same(layer0.audioClips));
    expect(layer1.effects, same(layer0.effects));
    expect(layer1.expandedLaneGroups, same(layer0.expandedLaneGroups));
    expect(layer1.baseFrameLinks, same(layer0.baseFrameLinks));

    final frame0 = frame();
    expect(frame0.copyWith(duration: 2).strokes, same(frame0.strokes));

    final stroke0 = stroke();
    expect(
      stroke0.copyWith(id: const StrokeId('again')).points,
      same(stroke0.points),
    );
  });

  test('a project and its timeline hand back what they did not change', () {
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      createdAt: DateTime.utc(2026, 11, 11),
      tracks: [track()],
    );
    final renamed = project.copyWith(name: 'again');
    expect(renamed.timelines, same(project.timelines));
    expect(renamed.fonts, same(project.fonts));
    expect(renamed.mediaViewerBookmarks, same(project.mediaViewerBookmarks));
    expect(renamed.mediaAssets, same(project.mediaAssets));
    expect(
      project.copyWith(tracks: [track()]).fonts,
      same(project.fonts),
      reason: 'a copy that changed the tracks changed no font',
    );

    final timeline = ProjectTimeline(
      id: const TimelineId('timeline'),
      number: 1,
      tracks: [track()],
    );
    expect(timeline.copyWith(trailingFrames: 4).tracks, same(timeline.tracks));
  });

  test('a picture hands back its tiles, texts and photos', () {
    final picture = BitmapSurface(
      canvasSize: const CanvasSize(width: 64, height: 64),
    );
    final copy = picture.copyWith();
    expect(copy.tiles, same(picture.tiles));
    expect(copy.texts, same(picture.texts));
    expect(copy.photos, same(picture.photos));
  });

  group('a collection BUILT from the one given is that one when it holds '
      'the same', () {
    test('an effect\'s parameters, colours, points and rows', () {
      final before = effect();
      final after = before.copyWith(enabled: false);
      expect(after.parameters, same(before.parameters));
      expect(after.colors, same(before.colors));
      expect(after.points, same(before.points));
      expect(after.layers, same(before.layers));
    });

    test('a text\'s runs and paragraphs', () {
      final content = CelTextContent(
        spans: const [
          CelTextSpan(text: 'a', style: TextLetterStyle()),
          CelTextSpan(text: 'b', style: TextLetterStyle(bold: true)),
        ],
        anchor: CanvasPoint(x: 0, y: 0),
      );
      final turned = content.copyWith(rotationDegrees: 5);
      expect(turned.spans, same(content.spans));
      expect(turned.paragraphs, same(content.paragraphs));
    });

    test('a text\'s runs are settled anew when settling changes them', () {
      final content = CelTextContent(
        spans: const [
          CelTextSpan(text: 'a', style: TextLetterStyle()),
          CelTextSpan(text: 'b', style: TextLetterStyle()),
        ],
        anchor: CanvasPoint(x: 0, y: 0),
      );
      expect([for (final span in content.spans) span.text], ['ab']);
    });

    test('a block\'s breakdown marks', () {
      final block = const TimelineExposure.drawing(
        FrameId('frame'),
        length: 4,
      ).copyWith(breakdownMarks: {1: InbetweenMark.one});
      final moved = block.copyWith(frameId: const FrameId('another'));
      expect(moved.breakdownMarks, same(block.breakdownMarks));
      expect(
        block.copyWith(length: 1).breakdownMarks,
        isEmpty,
        reason: 'a mark past the end is still dropped',
      );
    });

    test('an SE line\'s types by cut', () {
      final types = SeLineTypes(byCut: {const CutId('cut'): SeLineType.off});
      expect(types.withCut(null, types.own).byCut, same(types.byCut));
    });

    test('an export\'s cut deltas', () {
      final overrides = ExportProjectOverrides(
        celsCutDeltas: {
          const CutId('cut'): ExportCelsCutDelta(
            layerOverrides: {const LayerId('layer'): true},
          ),
        },
      );
      expect(
        overrides.withCutIncluded(const CutId('cut'), false).celsCutDeltas,
        same(overrides.celsCutDeltas),
      );
    });
  });
}
