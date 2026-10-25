// F-180 (유저 2026-09-25): 「타임라인패널에서 트랜지션레이어에 서있을떄
// +버튼이 활성화안되서 생성안됨. 스토리보드만 됨. 그러니 구조가 그렇게
// 되있는거같은데 타임라인패널(로컬)에서도 가능하도록」 — and I-9 had asked
// it of the double tap on 08-29 (「타임라인의 se행이랑 트랜지션행 …
// 새로만들자」).
//
// The cut view writes the GLOBAL row, through the verb the storyboard's ＋
// presses. What it adds is one refusal of its own: the cut's row is a
// PROJECTION, so a crossing span's mark can stand over frames the global row
// has free, and the ＋ must not stack a span under a mark the user sees.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_command_actions.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/timeline_host.dart';

void main() {
  test('standing on the transition row, the ＋ makes a span at the playhead '
      '— on the global row', () {
    final s = _standingOnTheTransitionRow(frame: 3);
    expect(
      s.cellInstances.canCreateInstance,
      isTrue,
      reason: 'F-180: it was dark here',
    );

    createActiveInstance(s);

    final spans = s.activeTrack.transitionLayer.instructions;
    expect(spans.keys, [s.activeCutGlobalStartFrame + 3]);
    expect(spans.values.single.length, 1);
    expect(
      s.transitions.transitionShownInCutAt(3),
      isTrue,
      reason: 'a first term is a fade, which applies inside its own cut — '
          'so the cut row shows what the ＋ made, where it made it',
    );
  });

  test('the ＋ stays dark where the cut\'s row shows a mark the global row '
      'has free — a crossing span\'s projection', () {
    final s = _session();
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.single;
    final boundary = track.cuts.first.duration;
    // A fade IN that opens three frames before its cut does and runs five
    // into it: it crosses its own cut's start, so it applies nowhere (D26)
    // and owes no のりしろ, and the cut draws it from its frame 0 at its
    // full length of eight — over three frames the global row has free.
    //
    // ↩️An O.L stood here, while a cut's frames were counted from its
    // place on the track: its mark is drawn where it is now — the cut's
    // own frames begin with its のりしろ (I-73-ol-index-space) — and only
    // a span from further back than the cut is drawn for is pulled.
    s.transitions.updateTransitionInstructions({
      boundary - 3: const InstructionEvent(instructionId: 'fi', length: 8),
    });
    s.selectCut(track.cuts[1].id);
    s.standOnRow(LayerRowAddress(track.transitionLayer.id));
    s.selectFrameIndex(6);
    expect(s.editingGlobalFrame, boundary + 6, reason: 'the premise');
    expect(
      s.transitions.transitionSpanAt(s.editingGlobalFrame),
      isNull,
      reason: 'the premise: the GLOBAL row is free here',
    );
    expect(
      s.transitions.transitionShownInCutAt(6),
      isTrue,
      reason: 'the premise: the cut row draws the fade over this frame',
    );

    expect(s.cellInstances.canCreateInstance, isFalse);
    expect(
      s.cellInstances.activeCellHoldsAnInstance,
      isTrue,
      reason: 'a double tap on a mark it can see is not a creation',
    );
  });

  test('a range over the transition row makes a span as long as the range — '
      'one undo with the rows beside it (#17)', () {
    final s = _inTheSecondCut();
    final transition = s.activeTrack.transitionLayer.id;
    final direction = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.instruction)
        .id;
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: direction,
      startIndex: 2,
      endIndexExclusive: 5,
      layerIds: [direction, transition],
    );

    createActiveInstance(s);

    final spans = s.activeTrack.transitionLayer.instructions;
    expect(spans.keys, [s.activeCutGlobalStartFrame + 2]);
    expect(spans.values.single.length, 3);
    expect(
      s.layers.firstWhere((layer) => layer.id == direction).instructions,
      isNotEmpty,
      reason: 'the premise: the direction row filled too',
    );
    s.undo();
    expect(s.activeTrack.transitionLayer.instructions, isEmpty);
    expect(
      s.layers.firstWhere((layer) => layer.id == direction).instructions,
      isEmpty,
      reason: 'ONE undo for the whole range, as every row\'s fill is',
    );
  });

  testWidgets('a double tap on an EMPTY cell of the row creates (I-9)', (
    tester,
  ) async {
    final s = _standingOnTheTransitionRow(frame: 6);
    final context = await _contextFrom(tester);

    await activateCellOnDoubleTap(
      context,
      s,
      layerId: s.activeTrack.transitionLayer.id,
      frameIndex: 6,
    );
    await tester.pumpAndSettle();

    expect(
      s.activeTrack.transitionLayer.instructions.keys,
      [s.activeCutGlobalStartFrame + 6],
    );
  });

  testWidgets('the timeline\'s own ＋ button is lit there and makes the span', (
    tester,
  ) async {
    final s = _standingOnTheTransitionRow(frame: 2);
    await pumpTimelineHostOn(
      tester,
      s,
      surface: const Size(1400, 900),
      pixelsPerFrame: 24,
    );

    await tester.tap(find.byKey(const ValueKey<String>('new-frame-button')));
    await tester.pumpAndSettle();

    expect(
      s.activeTrack.transitionLayer.instructions.keys,
      [s.activeCutGlobalStartFrame + 2],
    );
  });

  // 🗣️F-338 (유저 2026-10-11): 「프레임 추가버튼 활성화된채로 트랜지션레이어
  // 가면 추가버튼 다른 블록있는 OL있는곳가던 뭐하던 활성화된채」.
  testWidgets('the bar\'s ＋ goes dark where the playhead steps onto an '
      'O.L\'s mark — and lights again off it', (tester) async {
    final s = _session();
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.single;
    final boundary = track.cuts.first.duration;
    // An O.L of 12 on the boundary: the second cut's own frames open with
    // its 6 frames of のりしろ, and the mark covers its first 12.
    s.transitions.updateTransitionInstructions({
      boundary - 6: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectCut(track.cuts[1].id);
    s.standOnRow(LayerRowAddress(track.transitionLayer.id));
    s.selectFrameIndex(14);
    await pumpTimelineHostOn(
      tester,
      s,
      surface: const Size(1400, 900),
      pixelsPerFrame: 24,
    );
    bool lit() => tester
            .appIconButton(
              find.byKey(const ValueKey<String>('new-frame-button')),
            )
            .onPressed !=
        null;
    expect(lit(), isTrue, reason: '⛔전제: a free cell past the mark');

    s.selectFrameIndex(5);
    await tester.pumpAndSettle();
    expect(s.transitions.transitionShownInCutAt(5), isTrue, reason: '⛔전제');
    expect(lit(), isFalse, reason: 'its press makes nothing on the mark');

    s.selectFrameIndex(14);
    await tester.pumpAndSettle();
    expect(lit(), isTrue);
  });
}

EditorSessionManager _session() {
  final s = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(s.dispose);
  return s;
}

EditorSessionManager _inTheSecondCut() {
  final s = _session();
  s.cutVerbs.createCut();
  s.selectCut(s.repository.requireProject().tracks.single.cuts[1].id);
  expect(
    s.activeCutGlobalStartFrame,
    greaterThan(0),
    reason: 'the premise: a cut whose frames are not the track\'s',
  );
  return s;
}

/// The SECOND of two cuts — one that does not start at the track's frame
/// 0, so a local index read as a global frame lands somewhere else — with
/// the timeline standing on its transition row at [frame].
EditorSessionManager _standingOnTheTransitionRow({required int frame}) {
  final s = _inTheSecondCut();
  s.standOnRow(LayerRowAddress(s.activeTrack.transitionLayer.id));
  s.selectFrameIndex(frame);
  expect(
    s.activeLayer?.kind,
    LayerKind.transition,
    reason: 'the premise: the timeline stands on the transition row',
  );
  expect(s.activeTrack.transitionLayer.instructions, isEmpty);
  return s;
}

Future<BuildContext> _contextFrom(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}
