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

/// 🗣️F-236 (유저 2026-09-29): 「블록 중간에서 프레임 추가버튼누르면 해당위치에
/// 블록 교체? 방식으로 넣는것처럼, 블록 붙여넣기같은것도 통일해서 블록 중간에
/// 붙여넣는거랑 프레임 추가랑 똑같은 법 통일」 — and F-236-Q1: 「선택범위 없이
/// 일반 복사는 블록의 코마수를 가져가지않으니 붙여넣기시 1코마로서 붙여넣으니
/// 같은법으로 문제없고, 선택범위로 코마정보가 있을때만 코마대로 유지해서
/// 붙여넣어서 뒤가 짧으면 당기고 부족하면 밀고」.
///
/// Driven through the verbs a press drives — copy standing or over a
/// selection, then paste standing inside a block — so what the clipboard
/// banks is what the splice is handed.
void main() {
  const row = LayerId('row');

  /// `CAAAAAA..BB`: a one-cell C, a six-cell A, a gap, a two-cell B.
  EditorSessionManager rig() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('paste-inside'),
        name: 'Paste',
        createdAt: DateTime.utc(2026, 9, 29),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: '1',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: row,
                    name: 'row',
                    kind: LayerKind.animation,
                    frames: [
                      for (final (id, length) in [('C', 1), ('A', 6), ('B', 2)])
                        Frame(
                          id: FrameId(id),
                          duration: length,
                          strokes: const [],
                        ),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('C'), length: 1),
                      1: TimelineExposure.drawing(FrameId('A'), length: 6),
                      9: TimelineExposure.drawing(FrameId('B'), length: 2),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectLayer(row);
    return session;
  }

  Map<int, TimelineExposure> timelineOf(EditorSessionManager session) =>
      session.layers.firstWhere((layer) => layer.id == row).timeline;

  ({String? frame, int? length}) at(EditorSessionManager session, int index) {
    final entry = timelineOf(session)[index];
    return (frame: entry?.frameId?.value, length: entry?.length);
  }

  test('a comma copied STANDING takes the rest of the block it lands inside '
      '— the division an added frame makes, nothing behind it moving', () {
    final session = rig();
    session.selectFrameIndex(0);
    session.copyFrameAtCurrentFrame();

    session.selectFrameIndex(3);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(at(session, 1), (frame: 'A', length: 2), reason: 'A up to 3');
    expect(
      at(session, 3),
      (frame: 'C', length: 4),
      reason: '「1코마로서 붙여넣으니 같은법」 — the rest of A, as an added '
          'frame takes it. ↩️It was one cell with A split and pushed on '
          'behind it (`1--C1---`)',
    );
    expect(at(session, 9), (frame: 'B', length: 2), reason: 'B never moved');
  });

  test('an INDEPENDENT paste of a standing copy lands the same way', () {
    final session = rig();
    session.selectFrameIndex(0);
    session.copyFrameAtCurrentFrame();

    session.selectFrameIndex(3);
    session.pasteIndependentFrameAtCurrentFrame();

    final pasted = at(session, 3);
    expect(pasted.frame, isNot(anyOf('A', 'C')), reason: 'a cel of its own');
    expect(pasted.length, 4, reason: 'the rest of A');
    expect(at(session, 9), (frame: 'B', length: 2));
  });

  test('a run copied off a SELECTION keeps its commas, and the tail absorbs '
      'the difference — 「뒤가 짧으면 당기고」', () {
    final session = rig();
    session.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: row,
      startIndex: 0,
      endIndexExclusive: 1,
      layerIds: [row],
    );
    session.copyFrameAtCurrentFrame();
    session.clearFrameRangeSelection();

    session.selectFrameIndex(3);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(at(session, 1), (frame: 'A', length: 2));
    expect(at(session, 3), (frame: 'C', length: 1), reason: 'its one comma');
    expect(
      at(session, 6),
      (frame: 'B', length: 2),
      reason: 'the four cells of A it replaced became one, so what follows '
          'came three cells in',
    );
  });
}
