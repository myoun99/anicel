import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️F-322 (유저 2026-10-09): 「더블클릭으로 레이어 이름바꾸는거나 …
/// 통일」.
///
/// A conte row is ONE row over the track's cuts, and its label is its head:
/// the seat's row in the first cut that holds one. Its double click renames
/// the SEAT — every cut's row there wears the name — whichever cut the
/// session stands in, and inside a selection every row selected. ↩️It
/// pressed the head's layer, which was one cut's, and the rename looked for
/// it among the active cut's rows: standing in any other cut — or in a gap —
/// it opened nothing.
///
/// Cuts a [0, 12) and b [12, 24) each with a conte and a row riding over it;
/// four frames of gap; then c [28, 40), with no conte.
const _trackId = TrackId('t1');

Layer _drawn(
  String id, {
  required String name,
  LayerKind kind = LayerKind.storyboard,
  String? ridesOn,
}) => Layer(
  id: LayerId(id),
  name: name,
  kind: kind,
  attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
  attachedPlacement: AttachedPlacement.above,
  attachedMode: AttachedMode.free,
  frames: const [],
);

Cut _cut(String id, {bool conte = true, int gap = 0}) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  leadingGapFrames: gap,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    _drawn('$id-cel', name: 'Cel', kind: LayerKind.animation),
    if (conte) ...[
      _drawn('$id-conte', name: 'Conte'),
      _drawn('$id-over', name: 'Over', ridesOn: '$id-conte'),
    ],
  ],
);

Project _project() => Project(
  id: const ProjectId('conte-rename'),
  name: 'Conte rename',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [
    Track(
      id: _trackId,
      name: 'V1',
      cuts: [_cut('a'), _cut('b'), _cut('c', conte: false, gap: 4)],
      seLayers: [_drawn('s1', name: 'S1', kind: LayerKind.se)],
    ),
  ],
);

/// The conte as its tab hosts it ([pumpStoryboardHost]), the whole height
/// its own.
Future<EditorSessionManager> _pump(WidgetTester tester) {
  TimelineDoubleTapGate.reset();
  return pumpStoryboardHost(
    tester,
    _project(),
    surface: const Size(1400, 1300),
  );
}

final _rail = find.byKey(const ValueKey<String>('storyboard-track-label-rail'));

Finder _name(String text) =>
    find.descendant(of: _rail, matching: find.text(text)).first;

Future<void> _doubleClick(WidgetTester tester, Finder target) async {
  final at = tester.getCenter(target);
  await tester.tapAt(at, kind: PointerDeviceKind.stylus);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at, kind: PointerDeviceKind.stylus);
  await tester.pumpAndSettle();
}

const _dialog = ValueKey<String>('rename-layer-dialog');
const _field = ValueKey<String>('rename-layer-text-field');

Future<void> _rename(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(_field), name);
  await tester.tap(
    find.byKey(const ValueKey<String>('rename-layer-ok-button')),
  );
  await tester.pumpAndSettle();
}

/// Every cut's conte group, top seat first, by name.
List<String> _names(EditorSessionManager session) => [
  for (final cut in session.repository.requireProject().tracks.single.cuts)
    [for (final entry in conteGroupOf(cut)) entry.row.name].join(' '),
];

void main() {
  testWidgets('🚨standing in the second cut, the conte row\'s double click '
      'renames the seat in every cut', (tester) async {
    final session = await _pump(tester);
    session.selectCut(const CutId('b'));
    await tester.pumpAndSettle();
    expect(session.activeCutId, const CutId('b'), reason: '⛔전제');

    await _doubleClick(tester, _name('Conte'));
    expect(find.byKey(_dialog), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller?.text,
      'Conte',
      reason: 'one row: its own name seeds the field',
    );
    await _rename(tester, 'Board');

    expect(_names(session), ['Over Board', 'Over Board', '']);
  });

  testWidgets('…and inside a selection, every row selected', (tester) async {
    final session = await _pump(tester);
    final start = tester.getCenter(_name('Conte'));
    final end = tester.getCenter(_name('Over'));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(Offset(start.dx, end.dy));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.rowSelection.value, hasLength(2), reason: '⛔전제');

    await _doubleClick(tester, _name('Conte'));
    expect(find.byKey(_dialog), findsOneWidget);
    await _rename(tester, 'Pass');

    expect(_names(session), ['Pass Pass', 'Pass Pass', '']);
  });

  testWidgets('🚨in a gap the conte row renames its seat all the same — its '
      'head stands in a cut', (tester) async {
    final session = await _pump(tester);
    session.standOnRow(
      const TrackRowAddress(_trackId),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 26,
    );
    await tester.pumpAndSettle();
    expect(session.activeCutOrNull, isNull, reason: '⛔전제: a gap');

    await _doubleClick(tester, _name('Conte'));
    expect(find.byKey(_dialog), findsOneWidget);
    await _rename(tester, 'Board');

    expect(_names(session), ['Over Board', 'Over Board', '']);
  });

  testWidgets('…while an S row there opens nothing — the rename opens only '
      'where it can land, and a track\'s own row writes in the cut the '
      'session stands in, as every row verb does', (tester) async {
    final session = await _pump(tester);
    session.standOnRow(
      const TrackRowAddress(_trackId),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 26,
    );
    await tester.pumpAndSettle();
    expect(session.activeCutOrNull, isNull, reason: '⛔전제: a gap');

    await _doubleClick(tester, _name('S1'));

    expect(find.byKey(_dialog), findsNothing);
  });
}
