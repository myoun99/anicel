import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨결정 14 ③ⓐ (유저 확정 2026-08-22) — **THE CLIP LANDS ON EVERY SWEPT
/// ROW.**
///
/// > 「지우기 눌렀다고해서 현재 행만 지우는게아니라 **선택된 모든게**
/// > 지워지는걸 말하는거임. **복사든 뭐든 마찬가지**」 — and for the paste,
/// > a one-row clip over a multi-row band goes 「**모든 행에 같은 것을**」.
///
/// The clipboard still holds ONE row (그 절반은 ②ⓐ), so a band across three
/// rows receives that row three times.
void main() {
  const source = LayerId('src');
  const other = LayerId('other');
  const third = LayerId('third');

  Layer row(LayerId id, {bool drawn = false}) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.animation,
    frames: drawn
        ? [Frame(id: FrameId('${id.value}-cel'), duration: 2, strokes: const [])]
        : const [],
    timeline: drawn
        ? {0: TimelineExposure.drawing(FrameId('${id.value}-cel'), length: 2)}
        : const {},
  );

  EditorSessionManager rig() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('paste-band'),
        name: 'Paste',
        createdAt: DateTime.utc(2026, 8, 22),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut-1'),
                name: '1',
                duration: 10,
                canvasSize: const CanvasSize(width: 640, height: 360),
                // Only the SOURCE row is drawn: the other two are empty, so
                // anything that appears in them came from the paste.
                layers: [
                  row(source, drawn: true),
                  row(other),
                  row(third),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  List<int> coveredFrames(EditorSessionManager session, LayerId id) {
    final layer = session.layers.firstWhere((l) => l.id == id);
    final covered = <int>[];
    for (final entry in layer.timeline.entries) {
      if (!entry.value.isDrawing) {
        continue;
      }
      for (var i = 0; i < (entry.value.length ?? 1); i += 1) {
        covered.add(entry.key + i);
      }
    }
    return covered..sort();
  }

  Layer layerOf(EditorSessionManager session, LayerId id) =>
      session.layers.firstWhere((l) => l.id == id);

  /// Copies the source row's block onto the clipboard.
  void copyTheBlock(EditorSessionManager session) {
    session.selectLayer(source);
    session.selectFrameIndex(0);
    session.clearFrameRangeSelection();
    session.copyFrameAtCurrentFrame();
  }

  void sweep(
    EditorSessionManager session,
    List<LayerId> ids, {
    required int from,
    required int toExclusive,
  }) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: ids.first,
      startIndex: from,
      endIndexExclusive: toExclusive,
      layerIds: ids,
    );
  }

  test('presence first: only the source row is drawn', () {
    final session = rig();
    expect(coveredFrames(session, source), [0, 1]);
    expect(coveredFrames(session, other), isEmpty);
    expect(coveredFrames(session, third), isEmpty);
  });

  test('an INDEPENDENT paste over a three-row band fills all three', () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    sweep(session, const [source, other, third], from: 4, toExclusive: 6);

    session.pasteIndependentFrameAtCurrentFrame();

    for (final id in const [source, other, third]) {
      expect(
        coveredFrames(session, id),
        contains(4),
        reason: '$id was swept, so the clip landed there — 「모든 행에 같은 '
            '것을」 (결정 14 ③ⓐ)',
      );
    }
  });

  test('each row gets its OWN cel: an independent paste is a copy, not a '
      'link', () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    sweep(session, const [source, other, third], from: 4, toExclusive: 6);
    session.pasteIndependentFrameAtCurrentFrame();

    final pasted = <FrameId>{};
    for (final id in const [source, other, third]) {
      final layer = layerOf(session, id);
      final at = layer.timeline[4];
      expect(at?.frameId, isNotNull, reason: '$id really received a cel');
      pasted.add(at!.frameId!);
      expect(
        layer.frames.any((frame) => frame.id == at.frameId),
        isTrue,
        reason: '⛔$id must OWN the cel it points at — an exposure with no '
            'cel behind it is the 「완전한 버그상태」 this path has hit before',
      );
    }
    expect(
      pasted,
      hasLength(3),
      reason: 'three distinct cels. Sharing one minted id across rows would '
          'be a LINK, which is the other verb',
    );
  });

  test('the cels are minted, not orphaned: no row carries a drawing nothing '
      'points at', () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    sweep(session, const [source, other, third], from: 4, toExclusive: 6);
    session.pasteIndependentFrameAtCurrentFrame();

    for (final id in const [source, other, third]) {
      final layer = layerOf(session, id);
      final referenced = <FrameId>{
        for (final exposure in layer.timeline.values)
          if (exposure.frameId != null) exposure.frameId!,
      };
      expect(
        layer.frames.map((frame) => frame.id).toSet().difference(referenced),
        isEmpty,
        reason: '⛔$id holds a cel nothing exposes. That is what asking the '
            'placement builder TWICE per row would produce — it mints on '
            'each call, and only the second set would be referenced',
      );
    }
  });

  test('one press is ONE undo across every swept row', () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    final before = {
      for (final id in const [source, other, third])
        id: coveredFrames(session, id),
    };
    sweep(session, const [source, other, third], from: 4, toExclusive: 6);
    session.pasteIndependentFrameAtCurrentFrame();
    expect(coveredFrames(session, other), isNotEmpty);

    session.undo();
    for (final id in const [source, other, third]) {
      expect(
        coveredFrames(session, id),
        before[id],
        reason: '$id came back with the others — three undo steps for one '
            'press is the shape this round exists to avoid',
      );
    }
  });

  test('with NO band the paste still lands on the active row alone', () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    session.selectFrameIndex(4);
    session.clearFrameRangeSelection();

    session.pasteIndependentFrameAtCurrentFrame();
    expect(coveredFrames(session, source), contains(4));
    expect(
      coveredFrames(session, other),
      isEmpty,
      reason: 'no band means no other target — the single-row paste is the '
          'same code path, not a branch beside it',
    );
    expect(coveredFrames(session, third), isEmpty);
  });

  test('a LINKED paste reaches every swept row too, sharing the source cel',
      () {
    final session = rig();
    copyTheBlock(session);
    session.selectLayer(source);
    sweep(session, const [source, other, third], from: 4, toExclusive: 6);

    session.pasteLinkedFrameAtCurrentFrame();

    for (final id in const [source, other, third]) {
      final layer = layerOf(session, id);
      final at = layer.timeline[4];
      expect(at?.frameId, FrameId('${source.value}-cel'), reason: '$id links');
      expect(
        layer.frames.any((frame) => frame.id == at!.frameId),
        isTrue,
        reason: '⛔$id must hold the cel it points at, or the row renders a '
            'white block with `?` for a name',
      );
    }
  });
}
