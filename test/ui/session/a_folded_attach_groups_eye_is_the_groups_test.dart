// F-184 (유저 2026-09-26): 「어태치 레이어가 접혀있을때의 기준레이어의 비지블
// 버튼은 내부 어태치레이어 전체에 적용. 즉 비지블on하면 어태치레이어들 다
// on됨. 다시말하지만 어태치 접혀있을때만. 펼치기 상태에선 지금처럼 각각」.
//
// The eye is pressed the way the rails press it — through
// [SessionRowButtonPresses], the one door the press and the column swipe both
// go through.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';

const _a = LayerId('a');
const _b = LayerId('b');
const _below = LayerId('b-below');
const _above = LayerId('b-above');

Layer _drawing(
  LayerId id, {
  LayerId? attachedTo,
  AttachedPlacement placement = AttachedPlacement.below,
}) => Layer(
  id: id,
  name: id.value,
  frames: [Frame(id: FrameId('${id.value}-cel'), duration: 1, strokes: const [])],
  timeline: const {},
  attachedToLayerId: attachedTo,
  attachedPlacement: placement,
);

/// A, then B with one rider below it and one above.
Project _project() => Project(
  id: const ProjectId('folded-eye'),
  name: 'Folded eye',
  createdAt: DateTime.utc(2026, 9, 26),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            _drawing(_a),
            _drawing(_below, attachedTo: _b),
            _drawing(_b),
            _drawing(
              _above,
              attachedTo: _b,
              placement: AttachedPlacement.above,
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: _project());
    addTearDown(s.dispose);
    return s;
  }

  bool eyeOf(EditorSessionManager s, LayerId id) =>
      layerAnywhereOrNull(s.repository.requireProject(), id)!.isVisible;

  Map<LayerId, bool> eyes(EditorSessionManager s) => {
    for (final id in [_a, _b, _below, _above]) id: eyeOf(s, id),
  };

  void fold(EditorSessionManager s) =>
      s.railView.collapsedAttachBaseIds.value = {_b};

  test('folded, the base\'s eye is the group\'s — every rider goes where the '
      'base goes, off and back on, as ONE undo', () {
    final s = session();
    fold(s);
    final presses = SessionRowButtonPresses(s);

    presses.toggleVisibility(_b);

    expect(eyes(s), {_a: true, _b: false, _below: false, _above: false});

    s.undo();
    expect(
      eyes(s),
      {_a: true, _b: true, _below: true, _above: true},
      reason: 'one press, one step',
    );

    presses.toggleVisibility(_b);
    presses.toggleVisibility(_b);
    expect(
      eyes(s),
      {_a: true, _b: true, _below: true, _above: true},
      reason: '「비지블on하면 어태치레이어들 다 on됨」',
    );
  });

  test('a rider that already shows what the base goes to is passed by — the '
      'group ends where the base ends', () {
    final s = session();
    final presses = SessionRowButtonPresses(s);
    // Turned off by itself while the group was open.
    presses.toggleVisibility(_below);
    expect(eyeOf(s, _below), isFalse, reason: '⛔전제');
    fold(s);

    presses.toggleVisibility(_b);
    expect(eyes(s), {_a: true, _b: false, _below: false, _above: false});

    presses.toggleVisibility(_b);
    expect(eyes(s), {_a: true, _b: true, _below: true, _above: true});
  });

  test('open, every row keeps its own eye — 「펼치기 상태에선 지금처럼 '
      '각각」', () {
    final s = session();
    final presses = SessionRowButtonPresses(s);

    presses.toggleVisibility(_b);

    expect(eyes(s), {_a: true, _b: false, _below: true, _above: true});
  });
}
