import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
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

/// 🗣️F-322 (유저 2026-10-09): 「콘티패널 지금 옛날부터 몇번말해도 계속
/// 레이어의 선택범위 작동안하고 바로 드래그방식인데 작동하도록.
/// 타임라인이랑 완벽통일. 선택범위로 선택하고 드래그하는 관련로직」.
///
/// The timeline's rail law, on the storyboard's rail: a drag that starts on
/// a row's name outside the selection SELECTS — from any row, across rows of
/// any kind — and the selection is drawn as the timeline draws it, one band
/// over the run.
///
/// ⚠️Driven from the NAME area with a real pointer: the file that pinned
/// this rail's selection before (`the_storyboard_selects_before_it_moves`)
/// called the hooks by hand, and the rail stayed unable to select across
/// its rows — and drew no band — while it stayed green.
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

Cut _cut(String id, {required bool conte}) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  camera: CutCamera.empty(),
  layers: [
    _drawn('$id-cel', name: 'Cel', kind: LayerKind.animation),
    if (conte) ...[
      _drawn('$id-conte', name: 'Conte'),
      _drawn('$id-over', name: 'Over', ridesOn: '$id-conte'),
    ],
    _drawn('$id-cam', name: 'Camera', kind: LayerKind.camera),
  ],
);

Project _project({required bool conte}) => Project(
  id: const ProjectId('rail-select'),
  name: 'Rail select',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [
    Track(
      id: _trackId,
      name: 'V1',
      cuts: [_cut('a', conte: conte), _cut('b', conte: conte)],
      seLayers: [
        _drawn('s1', name: 'S1', kind: LayerKind.se),
        _drawn('s2', name: 'S2', kind: LayerKind.se),
      ],
    ),
  ],
);

final _conteRow = LayerRowAddress(trackConteRowId(_trackId));
final _overRow = LayerRowAddress(trackConteRowId(_trackId, seat: 1));

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<void> _pump(WidgetTester tester, {bool conte = true}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(conte: conte))),
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

/// A mouse drag from [from]'s name to [to]'s, in the name area — 「레이어
/// 이름영역이나 그 외 버튼 요소가 아닌 부분만」.
Future<void> _dragNames(WidgetTester tester, String from, String to) async {
  final start = tester.getCenter(_name(from));
  final end = tester.getCenter(_name(to));
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(Offset(start.dx, (start.dy + end.dy) / 2));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(Offset(start.dx, end.dy));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse drag from [from]'s name to [to] in four steps, [held] asked
/// before the release.
Future<void> _carry(
  WidgetTester tester,
  String from,
  Offset to, {
  required void Function() held,
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
  held();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('⛔전제 — the rail shows the rows this file drags between', (
    tester,
  ) async {
    await _pump(tester);
    for (final name in ['S1', 'S2', 'Video', 'Conte', 'Over']) {
      expect(_name(name), findsOneWidget, reason: name);
    }
    expect(_sessionOf(tester).rowSelection.value, isEmpty);
  });

  testWidgets('🚨a drag from an S row reaches the V row and the conte rows — '
      'a span is a slice of the rows the rail draws, whatever they are', (
    tester,
  ) async {
    await _pump(tester);

    await _dragNames(tester, 'S1', 'Conte');

    expect(
      _sessionOf(tester).rowSelection.value,
      containsAll(<TimelineRowAddress>[
        const LayerRowAddress(LayerId('s1')),
        const TrackRowAddress(_trackId),
        _overRow,
        _conteRow,
      ]),
    );
  });

  testWidgets('🚨a drag that starts on a conte row selects', (tester) async {
    await _pump(tester);

    await _dragNames(tester, 'Conte', 'Over');

    expect(_sessionOf(tester).rowSelection.value, [_overRow, _conteRow]);
  });

  testWidgets('…and on the conte row before any cut has a conte — it is a '
      'row of the rail, and the selection starts there too', (tester) async {
    await _pump(tester, conte: false);

    // It wears the name a conte is born with (F-322).
    await _dragNames(tester, 'Conte', 'Video');

    expect(
      _sessionOf(tester).rowSelection.value,
      containsAll(<TimelineRowAddress>[
        const TrackRowAddress(_trackId),
        _conteRow,
      ]),
    );
  });

  testWidgets('…and so does one on the V row — with one track there is no '
      'track to move it among, and it selects all the same', (tester) async {
    await _pump(tester);

    await _dragNames(tester, 'Video', 'Conte');

    expect(
      _sessionOf(tester).rowSelection.value,
      containsAll(<TimelineRowAddress>[
        const TrackRowAddress(_trackId),
        _conteRow,
      ]),
    );
  });

  testWidgets('🚨the selection is drawn — one band over the run, as the '
      'timeline\'s rail draws it', (tester) async {
    await _pump(tester);
    final band = find.descendant(
      of: _rail,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-row-selection-band-',
            ),
      ),
    );
    expect(band, findsNothing, reason: '⛔전제: nothing selected yet');

    await _dragNames(tester, 'Conte', 'Over');

    expect(band, findsOneWidget);
    final drawn = tester.getRect(band);
    final over = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-conte+1-label-t1')),
    );
    final conte = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-conte-label-t1')),
    );
    expect(drawn.top, closeTo(over.top, 1));
    expect(drawn.bottom, closeTo(conte.bottom, 1));
  });
  testWidgets('🚨an S row carried raises its caret among the S rows alone — '
      'a conte row\'s drag is another list, its own', (tester) async {
    await _pump(tester);
    // The first drag selects S2 — past the slop along its row, or it is a
    // tap, and a tap clears (the timeline's row, I-89 ①); the next one,
    // inside it, moves it.
    await tester.dragFrom(
      tester.getCenter(_name('S2')),
      const Offset(InstantTapRegion.travelSlop + 2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    await _carry(
      tester,
      'S2',
      tester.getRect(_name('S1')).bottomCenter + const Offset(0, 4),
      held: () {
        final carets = find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'timeline-row-caret-',
              ),
        );
        expect(carets, findsOneWidget);
        expect(
          (tester.widget(carets).key! as ValueKey<String>).value,
          endsWith('s1'),
          reason: 'under S1, the last S row',
        );
      },
    );
  });
}
