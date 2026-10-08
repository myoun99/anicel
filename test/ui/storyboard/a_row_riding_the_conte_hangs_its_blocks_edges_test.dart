import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../storyboard_conte_row_probe.dart';
import '../timeline/timeline_row_chrome_probe.dart';

/// 🗣️I-73 — the drawn proposal 유저 took on 2026-10-08, of a row riding
/// the conte on the storyboard: 「엣지 — 블록의 양 끝」 · 「끌면 — 콘티
/// 행과 같음」.
///
/// The conte row's edges are the cut's own length and its panels' commas.
/// A row riding the conte hangs its OWN blocks' two edges, on the row under
/// the conte's, and they re-time that block alone — in whichever cut the
/// block is, the session standing where it stood.
const _trackId = TrackId('rider-track');

/// The row's word in its keys: the attach row one above the conte.
const _riderRow = 'rider-track-conte+1';

String _riderGrip(String edge, int ordinal) =>
    'block-edge-grip-$edge-'
    '${trackConteRowId(_trackId, seat: 1).value}-$ordinal';

String _panelGrip(String edge, int ordinal) =>
    'block-edge-grip-$edge-${trackConteRowId(_trackId).value}-$ordinal';

Layer _conte(String cut, Map<int, int> panels) => Layer(
  id: LayerId('$cut-conte'),
  name: 'Conte',
  kind: LayerKind.storyboard,
  frames: [
    for (final start in panels.keys)
      Frame(id: FrameId('$cut-$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final entry in panels.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('$cut-${entry.key}'),
        length: entry.value,
      ),
  },
);

Layer _rider(
  String cut,
  Map<int, int> blocks, {
  AttachedMode mode = AttachedMode.free,
}) => Layer(
  id: LayerId('$cut-over'),
  name: 'Conte+1',
  kind: LayerKind.storyboard,
  attachedToLayerId: LayerId('$cut-conte'),
  attachedPlacement: AttachedPlacement.above,
  attachedMode: mode,
  frames: [
    for (final start in blocks.keys)
      Frame(id: FrameId('$cut-over-$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final entry in blocks.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('$cut-over-${entry.key}'),
        length: entry.value,
      ),
  },
);

Cut _cut(String id, int duration, List<Layer> rows) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
    ...rows,
  ],
);

/// Cut 1 covers [0,10): its rider holds two glued blocks, [0,4) and [4,7).
/// Cut 2 covers [10,20): its rider is SYNCED, and owns no timing. Cut 3
/// covers [20,26): its rider's one block starts two frames in and runs past
/// the cut's end — the strip shows it cut off there.
Project _project() => Project(
  id: const ProjectId('rider-project'),
  name: 'Riders',
  createdAt: DateTime.utc(2026, 10, 8),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        _cut('cut-1', 10, [
          _conte('cut-1', {0: 5, 5: 5}),
          _rider('cut-1', {0: 4, 4: 3}),
        ]),
        _cut('cut-2', 10, [
          _conte('cut-2', {0: 10}),
          _rider('cut-2', const {}, mode: AttachedMode.synced),
        ]),
        _cut('cut-3', 6, [
          _conte('cut-3', {0: 3, 3: 3}),
          _rider('cut-3', {2: 10}),
        ]),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

StoryboardPanel _panel(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

Cut _cutById(WidgetTester tester, String id) => _panel(
  tester,
).project.tracks.single.cuts.firstWhere((cut) => cut.id == CutId(id));

/// A cut's rider's stored blocks, as `start: length` in its own frames.
Map<int, int> _riderBlocks(WidgetTester tester, String cut) => {
  for (final entry
      in _cutById(tester, cut).layers
          .firstWhere((layer) => layer.id == LayerId('$cut-over'))
          .timeline
          .entries)
    if (!entry.value.ghost) entry.key: entry.value.length!,
};

Offset _gripCenter(WidgetTester tester, String id) =>
    timelineRowChromeCenter(tester, _riderRow, id, prefix: 'storyboard');

/// Presses the rider row's grip [id] and moves it [frames] whole frames —
/// in two steps, so the drag clears the slop before the delta lands.
Future<TestGesture> _holdGrip(
  WidgetTester tester,
  String id,
  int frames,
) async {
  final gesture = await tester.startGesture(
    _gripCenter(tester, id),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  final step = frames * _panel(tester).pixelsPerFrame / 2;
  await gesture.moveBy(Offset(step, 0));
  await tester.pump();
  await gesture.moveBy(Offset(step, 0));
  await tester.pump();
  return gesture;
}

Future<void> _dragGrip(WidgetTester tester, String id, int frames) async {
  final gesture = await _holdGrip(tester, id, frames);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('🚨each block of a row riding the conte hangs its two edges on '
      'that row — none where the row owns no timing, and none on an edge '
      'the cut\'s end cuts off', (tester) async {
    await _openStoryboard(tester);

    expect(
      conteRowBlocks(tester, _riderRow),
      // Cut 2's row wears its base's one panel; cut 3's block shows from
      // its start to the cut's end.
      {0: 4, 4: 3, 10: 10, 22: 4},
      reason: 'fixture: the row as the strip draws it',
    );
    expect(
      timelineRowChromeIds(tester, _riderRow, prefix: 'storyboard'),
      [
        _riderGrip('start', 0),
        _riderGrip('end', 0),
        _riderGrip('start', 1),
        _riderGrip('end', 1),
        // Cut 3's block ends past its cut: no edge is drawn there to grip.
        _riderGrip('start', 2),
      ],
    );
    final row = conteRowRect(tester, _riderRow);
    for (final id in [_riderGrip('start', 0), _riderGrip('start', 2)]) {
      expect(
        row.contains(_gripCenter(tester, id)),
        isTrue,
        reason: '$id stands on the rider\'s row',
      );
    }
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: 'storyboard'),
      [
        for (var ordinal = 0; ordinal < 5; ordinal += 1) ...[
          _panelGrip('start', ordinal),
          _panelGrip('end', ordinal),
        ],
      ],
      reason: 'LIVENESS: the conte row\'s own — every panel\'s two',
    );
  });

  testWidgets('🚨a trailing edge is its block\'s comma and a leading edge '
      'trades with the block in front — the cut and its panels stay',
      (tester) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, _riderGrip('end', 0), 2);
    expect(_riderBlocks(tester, 'cut-1'), {0: 6, 6: 3});

    await _dragGrip(tester, _riderGrip('start', 1), -1);
    expect(_riderBlocks(tester, 'cut-1'), {0: 5, 5: 4});

    expect(_cutById(tester, 'cut-1').duration, 10);
    expect(
      conteRowBlocks(tester, _trackId.value),
      {0: 5, 5: 5, 10: 10, 20: 3, 23: 3},
      reason: 'the conte\'s panels are the cut\'s, and nothing moved them',
    );
  });

  testWidgets('🚨a block of a cut the session is not in is gripped where it '
      'is: the hand shows it, the release writes it, and the session stands '
      'where it stood', (tester) async {
    await _openStoryboard(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final standing = (
      cut: session.activeCutOrNull?.id,
      frame: session.currentFrameIndex,
    );
    expect(standing.cut, const CutId('cut-1'), reason: 'fixture');

    final gesture = await _holdGrip(tester, _riderGrip('start', 2), -1);

    expect(
      conteRowBlocks(tester, _riderRow),
      {0: 4, 4: 3, 10: 10, 21: 5},
      reason: 'the strip follows the hand',
    );
    expect(
      _riderBlocks(tester, 'cut-3'),
      {2: 10},
      reason: 'and nothing is written while it is held',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_riderBlocks(tester, 'cut-3'), {1: 11});
    expect(_cutById(tester, 'cut-3').duration, 6);
    expect(
      (cut: session.activeCutOrNull?.id, frame: session.currentFrameIndex),
      standing,
    );
  });
}
