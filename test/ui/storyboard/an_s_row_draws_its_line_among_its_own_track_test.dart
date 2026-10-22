import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject, TrackSeRowSubject;
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;

/// 🚨F-336 (유저 2026-10-10): 「콘티패널에서 s행의 제일 밑 레이어를 드래그로
/// s행 제일 위로 이동하려하면 카메라섹션의 가로줄이 생김. 관련문제 여러번
/// 나왔으니, 다양한 각도에서 근본/구조적으로 드래그 가로줄관련 해결.」
///
/// The conte panel lays one list of S rows per track, each counted from 0,
/// and a caret is a gap of ONE list. So the line an S row's drag draws
/// belongs on its own track's S rows and nowhere else: not on the camera
/// and transition rows above them, which stand in no list, and not on
/// another track's S rows, whose gap 0 is another gap.
///
/// Two tracks: V1 with three S rows, V2 with two.
const _v1 = TrackId('t1');
const _v2 = TrackId('t2');

Track _track(TrackId id, List<String> se) => Track(
  id: id,
  name: id.value,
  cuts: [
    Cut(
      id: CutId('${id.value}-cut'),
      name: '${id.value} cut',
      duration: 12,
      canvasSize: const CanvasSize(width: 640, height: 360),
      camera: CutCamera.empty(),
      layers: [
        Layer(
          id: LayerId('${id.value}-conte'),
          name: 'Conte',
          kind: LayerKind.storyboard,
          frames: const [],
        ),
      ],
    ),
  ],
  seLayers: [
    for (final name in se)
      Layer(
        id: LayerId(name),
        name: name,
        kind: LayerKind.se,
        frames: const [],
      ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: Project(
          id: const ProjectId('s-row-line'),
          name: 'S row line',
          createdAt: DateTime.utc(2026, 10, 18),
          tracks: [
            _track(_v1, ['Rain', 'Wind', 'Bell']),
            _track(_v2, ['Door', 'Step']),
          ],
        ),
      ),
    ),
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

/// [names] top to bottom, as the rail draws them.
List<String> _drawn(WidgetTester tester, List<String> names) => [...names]
  ..sort(
    (a, b) =>
        tester.getRect(_name(a)).top.compareTo(tester.getRect(_name(b)).top),
  );

/// Every caret the screen draws, by key.
Set<String> _carets() => {
  for (final element in find
      .byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-row-caret-',
            ),
      )
      .evaluate())
    (element.widget.key! as ValueKey<String>).value,
};

void main() {
  testWidgets('🚨the bottom S row carried to the top draws one line, on its '
      'own track\'s top row — and lands there', (tester) async {
    await _pump(tester);
    final v1 = _drawn(tester, ['Rain', 'Wind', 'Bell']);
    final v2 = _drawn(tester, ['Door', 'Step']);
    final (top, bottom) = (v1.first, v1.last);

    // The first drag selects; a drag inside the selection moves it.
    await tester.dragFrom(
      tester.getCenter(_name(bottom)),
      const Offset(InstantTapRegion.travelSlop + 2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final start = tester.getCenter(_name(bottom));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));

    final own = {
      for (final name in v1) ...[
        'timeline-row-caret-before-$name',
        'timeline-row-caret-after-$name',
      ],
    };
    // Up past V1's top S row and on into the rows above it, where the
    // camera section's line was drawn.
    final end = tester.getRect(_name(top)).top - 40;
    for (var y = start.dy; y >= end; y -= 4) {
      await gesture.moveTo(Offset(start.dx, y));
      await tester.pump();
      expect(_carets().difference(own), isEmpty, reason: 'at y=$y');
    }
    expect(_carets(), {'timeline-row-caret-before-$top'});

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_drawn(tester, v1), [bottom, ...v1.take(v1.length - 1)]);
    expect(_drawn(tester, v2), v2, reason: 'the other track is not touched');
  });

  test('a row of the layer stack draws no line an S row of the conte panel '
      'raised: that line is a gap of the track\'s own S rows', () {
    const layerRow = LayerRowSubject(LayerId('a'));
    expect(
      layerRow.sharesLaneWith(const LayerRowSubject(LayerId('b'))),
      isTrue,
      reason: '⛔premise: the layer rows share their lane',
    );
    expect(
      layerRow.sharesLaneWith(const TrackSeRowSubject(_v1, LayerId('Rain'))),
      isFalse,
    );
  });
}
