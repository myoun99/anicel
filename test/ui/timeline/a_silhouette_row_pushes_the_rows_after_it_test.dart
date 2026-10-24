import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';

/// 🗣️video-place-2d2-Q2 (유저 2026-09-12): 「목업대로 — 실루엣 행을
/// 끼운다」 · 「이거도 버그 생길거같으니 철저하게해서 법 나뉘지않도록」 — a
/// file held over the layer area stands the row it would make in the gap,
/// and the rows after it make way.
///
/// 🚨The rows after it stand one row further on as they are DRAWN — an open
/// graph's room among them — while the gap under the pointer is still
/// counted on the rows as they stood without it ([rowsWithSilhouette]).
/// Uniform rows cannot tell the two lists' edges apart, so the row after
/// the gap here holds an open graph: its room is what a mix-up of the two
/// would move (`silhouette-drawn-edges-untested`, 10-12).
///
/// ↩️Written for the edges, this found the row itself never stood: the
/// grids do not listen to the preview channel, and nothing rebuilt them
/// for it (10-25).
void main() {
  testWidgets('held over the gap above a row whose graph stands open, the '
      'file stands a row there: that row, its graph and every row after '
      'them move one row down, and the rows reach one row further', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester);
    final row = tester.getRect(_railRow('B')).height;
    final before = _drawn(tester, 'timeline');

    final gesture = await _holdAPicture(tester);
    await gesture.moveTo(before.b.topLeft + const Offset(24, 2));
    await tester.pump();

    expect(
      tester.getRect(_railRow('placement-preview')),
      before.b,
      reason: 'the row it would make, in the gap above B',
    );
    expect(
      _drawn(tester, 'timeline'),
      before.shifted(Offset(0, row)),
      reason: 'B, its graph and A one row down; the rows one row longer',
    );
    expect(s.layerRowDragVerbs.inFlight.value, isNotNull);
    await _letGoElsewhere(tester, gesture);
    expect(
      _drawn(tester, 'timeline'),
      before,
      reason: 'and gone with the file',
    );
  });

  testWidgets('with the file standing above that row, the pointer moved '
      'to where the next row stood names the gap above it — and the row '
      'goes there', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester);
    final row = tester.getRect(_railRow('B')).height;
    final before = _drawn(tester, 'timeline');

    final gesture = await _holdAPicture(tester);
    await gesture.moveTo(before.b.topLeft + const Offset(24, 2));
    await tester.pump();
    final aboveB = s.layerRowDragVerbs.inFlight.value!.caretSlot;
    await gesture.moveTo(before.a.topLeft + const Offset(24, 2));
    await tester.pump();

    expect(
      s.layerRowDragVerbs.inFlight.value?.caretSlot,
      aboveB + 1,
      reason: 'the gap above A: counted on the rows without the silhouette, '
          'whose edges the open graph sets apart from the drawn ones',
    );
    expect(tester.getRect(_railRow('placement-preview')), before.a);
    expect(tester.getRect(_railRow('A')), before.a.shift(Offset(0, row)));
    await _letGoElsewhere(tester, gesture);
  });

  testWidgets('on the sheet the file stands a column before the first: '
      'every column after it, the open graph among them, moves one column '
      'right, and the columns reach one further', (tester) async {
    await _pump(tester);
    await _openTheGraph(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final column = tester.getRect(_column('A')).width;
    final before = _drawn(tester, 'xsheet');
    expect(
      before.graph.left,
      before.a.right,
      reason: 'CONTROL: the graph stands right after A, so it is pushed too',
    );

    final gesture = await _holdAPicture(tester);
    await gesture.moveTo(
      Offset(before.a.left + 2, before.strip.center.dy),
    );
    await tester.pump();

    expect(
      tester.getRect(_column('placement-preview')),
      before.a,
      reason: 'the column it would make, before A',
    );
    expect(_drawn(tester, 'xsheet'), before.shifted(Offset(column, 0)));
    await _letGoElsewhere(tester, gesture);
  });
}

const _dragSourceKey = ValueKey<String>('test-media-drag-source');
const _b = LayerId('B');

Finder _railRow(String id) => find.named('timeline-rail-row-$id-row');

Finder _column(String id) => find.named('xsheet-column-$id-cells');

/// Where the rows stand on [grid]: A and B (B's graph open), the graph,
/// and the layer area's strip — how far the rows reach.
_Drawn _drawn(WidgetTester tester, String grid) {
  Rect named(String id) => tester.getRect(
    grid == 'timeline' ? _railRow(id) : _column(id),
  );
  return _Drawn(
    a: named('A'),
    b: named('B'),
    graph: tester.getRect(
      find.byKey(
        ValueKey<String>(
          '$grid-lane-graph-'
          '${laneGroupKey(_b, transformGroupHeaderLane.laneId)}',
        ),
      ),
    ),
    strip: tester.getRect(
      find.byKey(ValueKey<String>('$grid-layer-placement-entrance')),
    ),
  );
}

class _Drawn {
  const _Drawn({
    required this.a,
    required this.b,
    required this.graph,
    required this.strip,
  });

  final Rect a;
  final Rect b;
  final Rect graph;
  final Rect strip;

  /// A, B and the graph moved by [by], and the strip grown by it — what a
  /// row standing before all three makes of them.
  _Drawn shifted(Offset by) => _Drawn(
    a: a.shift(by),
    b: b.shift(by),
    graph: graph.shift(by),
    strip: Rect.fromLTRB(
      strip.left,
      strip.top,
      strip.right + by.dx,
      strip.bottom + by.dy,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is _Drawn &&
      other.a == a &&
      other.b == b &&
      other.graph == graph &&
      other.strip == strip;

  @override
  int get hashCode => Object.hash(a, b, graph, strip);

  @override
  String toString() => '_Drawn(a: $a, b: $b, graph: $graph, strip: $strip)';
}

/// A picture lifted from a source above the app — the pool row's own drag
/// data, anchored at the pointer as the pool row's is.
Future<TestGesture> _holdAPicture(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_dragSourceKey)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return gesture;
}

/// Back to where it was lifted and let go there: nothing lands.
Future<void> _letGoElsewhere(WidgetTester tester, TestGesture gesture) async {
  await gesture.moveTo(tester.getCenter(find.byKey(_dragSourceKey)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// B's lanes twirled open and its Transform graph with them.
Future<void> _openTheGraph(WidgetTester tester) async {
  final transform = transformGroupHeaderLane.laneId;
  await _tap(tester, 'timeline-lane-toggle-$_b');
  await _tap(tester, 'timeline-lane-group-toggle-$_b-$transform');
  await _tap(tester, 'timeline-lane-group-graph-$_b-$transform');
}

Future<void> _tap(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The app under a picture's drag source, the dock pulled up so B's open
/// graph and the row after it fit the timeline.
Future<EditorSessionManager> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Column(
        children: [
          SizedBox(
            height: 40,
            child: Draggable<MediaAssetDragData>(
              data: const MediaAssetDragData(
                path: r'C:\art\bg.png',
                name: 'bg.png',
              ),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: const SizedBox(width: 8, height: 8),
              child: Container(
                key: _dragSourceKey,
                width: 40,
                height: 40,
                color: const Color(0xFF888888),
              ),
            ),
          ),
          Expanded(child: HomePage(initialProject: _project())),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Layer _empty(String id) => Layer(id: LayerId(id), name: id, frames: const []);

/// A, then B with a Position key pair (so its Transform group has lanes to
/// graph), then C — the list runs bottom up, so the rail reads C, B, A.
Project _project() => Project(
  id: const ProjectId('silhouette-edges'),
  name: 'Silhouette Edges',
  createdAt: DateTime.utc(2026, 10, 25),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          camera: CutCamera.empty(),
          layers: [
            _empty('A'),
            Layer(
              id: _b,
              name: 'B',
              frames: const [],
              transformTrack: TransformTrack.empty().copyWith(
                position: PropertyTrack<CanvasPoint>()
                    .withKey(0, CanvasPoint(x: 100, y: 50))
                    .withKey(8, CanvasPoint(x: 180, y: 10)),
              ),
            ),
            _empty('C'),
          ],
        ),
      ],
    ),
  ],
);
