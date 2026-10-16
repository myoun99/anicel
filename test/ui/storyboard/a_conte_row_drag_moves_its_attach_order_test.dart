import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;

/// 🗣️F-322 (유저 2026-10-09): 「선택범위 드래그로 어태치 조정」 — and
/// 10-10: 「드래그로 어태치 순서이동이라던가 피드백했을텐데 다 되도록 하는거
/// 잊지말고」.
///
/// The conte panel's conte rows take the timeline's row grammar: the first
/// drag selects, and a drag that starts inside the selection moves it — the
/// conte group re-ordered as the timeline's drag of that seat's row would,
/// in every cut, the selection and the stand following the rows moved.
///
/// Cuts a and b: a conte with two rows riding over it and one under it.
const _trackId = TrackId('t1');

Layer _drawn(
  String id, {
  required String name,
  LayerKind kind = LayerKind.storyboard,
  String? ridesOn,
  AttachedPlacement placement = AttachedPlacement.above,
}) => Layer(
  id: LayerId(id),
  name: name,
  kind: kind,
  attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
  attachedPlacement: placement,
  attachedMode: AttachedMode.free,
  frames: const [],
);

Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  camera: CutCamera.empty(),
  layers: [
    _drawn('$id-cel', name: 'Cel', kind: LayerKind.animation),
    _drawn(
      '$id-under',
      name: 'Under',
      ridesOn: '$id-conte',
      placement: AttachedPlacement.below,
    ),
    _drawn('$id-conte', name: 'Conte'),
    _drawn('$id-over', name: 'Over', ridesOn: '$id-conte'),
    _drawn('$id-high', name: 'High', ridesOn: '$id-conte'),
  ],
);

Project _project() => Project(
  id: const ProjectId('conte-drag'),
  name: 'Conte drag',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [
    Track(id: _trackId, name: 'V1', cuts: [_cut('a'), _cut('b')]),
  ],
);

LayerRowAddress _seat(int seat) =>
    LayerRowAddress(trackConteRowId(_trackId, seat: seat));

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -700),
  );
  await tester.pumpAndSettle();
}

final _rail = find.byKey(const ValueKey<String>('storyboard-track-label-rail'));

Finder _name(String text) =>
    find.descendant(of: _rail, matching: find.text(text)).first;

/// A mouse drag from [from]'s name to [to] — a point on the rail — in
/// steps, the way a hand moves.
Future<void> _drag(
  WidgetTester tester,
  String from,
  Offset to, {
  void Function()? held,
}) async {
  final start = tester.getCenter(_name(from));
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  for (var step = 1; step <= 4; step += 1) {
    await gesture.moveTo(
      Offset.lerp(start, Offset(start.dx, to.dy), step / 4)!,
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  held?.call();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A press on [name] that travels past [InstantTapRegion.travelSlop] along
/// its row and lets go — the first drag: it selects the row.
///
/// ↩️It wandered three pixels, and the rail's own label kept what that
/// selected. The row is the timeline's now (I-89 ①): a press that travels
/// less is a TAP, and a tap clears (T10's second half) — the timeline's
/// rail tests travel past the slop for the same reason.
Future<void> _select(WidgetTester tester, String name) async {
  await tester.dragFrom(
    tester.getCenter(_name(name)),
    const Offset(InstantTapRegion.travelSlop + 2, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

/// Every cut's conte group, top seat first, by name and side.
List<String> _groups(EditorSessionManager session) => [
  for (final cut in session.repository.requireProject().tracks.single.cuts)
    [
      for (final entry in conteGroupOf(cut))
        '${entry.seat}:${entry.row.name}'
            '${entry.seat == 0 ? '' : '/${entry.row.attachedPlacement.name}'}',
    ].join(' '),
];

void main() {
  testWidgets('⛔전제 — every cut holds the same four rows', (tester) async {
    await _pump(tester);
    expect(_groups(_sessionOf(tester)), [
      '2:High/above 1:Over/above 0:Conte -1:Under/below',
      '2:High/above 1:Over/above 0:Conte -1:Under/below',
    ]);
  });

  testWidgets('🚨the first drag selects — the rows stay where they are', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    final before = _groups(session);

    // From Under's name up to High's: a drag outside any selection.
    await _drag(tester, 'Under', tester.getCenter(_name('High')));

    expect(session.rowSelection.value, [
      _seat(2),
      _seat(1),
      _seat(0),
      _seat(-1),
    ]);
    expect(_groups(session), before, reason: 'nothing moved');
  });

  testWidgets('🚨a drag inside the selection moves it — the attach order of '
      'every cut, as the timeline\'s drag would', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    await _select(tester, 'Under');
    expect(session.rowSelection.value, [_seat(-1)], reason: '⛔전제');

    // Under, carried above High: it rides over the conte now, outermost.
    await _drag(
      tester,
      'Under',
      tester.getRect(_name('High')).topCenter - const Offset(0, 2),
    );

    expect(_groups(session), [
      '3:Under/above 2:High/above 1:Over/above 0:Conte',
      '3:Under/above 2:High/above 1:Over/above 0:Conte',
    ]);
    expect(
      session.rowSelection.value,
      [_seat(3)],
      reason: 'the selection follows the row it held to its new seat',
    );
  });

  testWidgets('…and while it is carried the rail draws the drag: the row '
      'lifts, and the caret stands where it would land', (tester) async {
    await _pump(tester);
    await _select(tester, 'Under');

    await _drag(
      tester,
      'Under',
      tester.getRect(_name('High')).topCenter - const Offset(0, 2),
      held: () {
        final carets = find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'timeline-row-caret-',
              ),
        );
        expect(carets, findsOneWidget);
        final high = tester.getRect(
          find.byKey(const ValueKey<String>('storyboard-conte+2-label-t1')),
        );
        expect(tester.getRect(carets).center.dy, closeTo(high.top, 2));
        expect(
          find.ancestor(
            of: find.byKey(
              const ValueKey<String>('storyboard-conte-1-label-t1'),
            ),
            matching: find.byWidgetPredicate(
              (widget) => widget is Opacity && widget.opacity < 1,
            ),
          ),
          findsOneWidget,
          reason: 'the held row lifts',
        );
      },
    );
  });

  testWidgets('…and the selection is carried whole: two rows move as one', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    await _drag(tester, 'High', tester.getCenter(_name('Over')));
    expect(session.rowSelection.value, [_seat(2), _seat(1)], reason: '⛔전제');

    // High and Over, carried under Under: below the conte, in their order.
    await _drag(
      tester,
      'High',
      tester.getRect(_name('Under')).bottomCenter + const Offset(0, 2),
    );

    expect(_groups(session), [
      '0:Conte -1:Under/below -2:High/below -3:Over/below',
      '0:Conte -1:Under/below -2:High/below -3:Over/below',
    ]);
    expect(session.rowSelection.value, [_seat(-2), _seat(-3)]);
  });
}
