import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAcross, partAlong;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🚨sheet-gap-stands-inside-open-lanes (10-25): a row's UNIT is itself and
/// the lanes it opens — after it on the rail, before it on the sheet (R9
/// #23) — and an fx header's, its parameters. A drop lands between units,
/// so a carry's lines stand at a unit's ends, never between a row and its
/// lanes.
///
/// ↩️Every row drew its two lines at its own edges: on the rail the line
/// after the last row and after a chain's last header stood above their
/// lanes, and on the sheet every line before a column stood between it and
/// the lanes it opens before it.
void main() {
  testWidgets('on the rail, the line after the last row stands past the '
      'lanes it opens after it', (tester) async {
    final session = await _open(tester, TimelineOrientation.horizontal);
    session.layerSwitches.toggleLayerLanes(_a);
    await tester.pumpAndSettle();
    final unit = _unitOf(tester, 'timeline-rail-row-a-');
    expect(
      tester.getRect(find.named('timeline-rail-row-a-row')).bottom,
      lessThan(unit.bottom),
      reason: 'CONTROL: A\'s lanes stand open after it',
    );

    final lines = await _linesOfACarry(
      tester,
      find.named('timeline-layer-name-c'),
      _stops(unit.top, unit.bottom + 12),
      axis: Axis.horizontal,
    );

    expect(lines['timeline-row-caret-after-a'], {unit.bottom});
  });

  testWidgets('on the rail, the line after a chain\'s last header stands '
      'past its parameters', (tester) async {
    final session = await _open(tester, TimelineOrientation.horizontal);
    await _openTheChain(tester, session, 'timeline');
    final second = _unitOf(tester, 'timeline-rail-row-b-fx:${_e2.value}:');
    final header = tester.getRect(
      find.named('timeline-rail-row-b-${effectGroupLaneId(_e2)}'),
    );
    expect(
      header.bottom,
      lessThan(second.bottom),
      reason: 'CONTROL: the last header\'s parameters stand after it',
    );

    final lines = await _linesOfACarry(
      tester,
      find
          .descendant(
            of: find.byKey(
              ValueKey<String>(
                'timeline-lane-label-b-${effectGroupLaneId(_e1)}',
              ),
            ),
            matching: find.byType(Text),
          )
          .first,
      _stops(header.top, second.bottom + 12),
      axis: Axis.horizontal,
    );

    expect(lines['timeline-row-caret-after-${_e2.value}'], {second.bottom});
  });

  testWidgets('on the sheet, the line before a column stands before the '
      'lanes it opens before it', (tester) async {
    final session = await _open(tester, TimelineOrientation.vertical);
    session.layerSwitches.toggleLayerLanes(_b);
    await tester.pumpAndSettle();
    final a = tester.getRect(find.named('xsheet-column-a-cells'));
    final b = _unitOf(tester, 'xsheet-column-b-');
    expect(
      tester.getRect(find.named('xsheet-column-b-cells')).left,
      greaterThan(b.left),
      reason: 'CONTROL: B\'s lanes stand open before it',
    );

    final lines = await _linesOfACarry(
      tester,
      find.named('xsheet-layer-name-c'),
      _stops(a.left, b.right),
      axis: Axis.vertical,
    );

    expect(lines['timeline-row-caret-before-b'], {b.left});
  });

  testWidgets('on the sheet, the line before a chain\'s header stands '
      'before its parameters', (tester) async {
    final session = await _open(tester, TimelineOrientation.vertical);
    await _openTheChain(tester, session, 'xsheet');
    final second = _unitOf(tester, 'xsheet-column-b-fx:${_e2.value}:');
    final first = tester.getRect(
      find.named('xsheet-column-b-${effectGroupLaneId(_e1)}'),
    );
    expect(
      tester
          .getRect(find.named('xsheet-column-b-${effectGroupLaneId(_e2)}'))
          .left,
      greaterThan(second.left),
      reason: 'CONTROL: the header\'s parameters stand before it',
    );

    final lines = await _linesOfACarry(
      tester,
      find.byKey(
        ValueKey<String>('xsheet-lane-label-b-${effectGroupLaneId(_e1)}'),
      ),
      _stops(second.left - 12, first.right),
      axis: Axis.vertical,
    );

    expect(lines['timeline-row-caret-before-${_e2.value}'], {second.left});
  });

  testWidgets('on the sheet, the last rider carried into the lanes the next '
      'column opens before it draws the line it leaves its group by, on the '
      'side it went', (tester) async {
    final session = await _open(
      tester,
      TimelineOrientation.vertical,
      layers: [
        _layer('x'),
        _layer('a').copyWith(attachedToLayerId: const LayerId('x')),
        _layer('b'),
      ],
    );
    session.layerSwitches.toggleLayerLanes(_b);
    await tester.pumpAndSettle();
    final a = tester.getRect(find.named('xsheet-column-a-cells'));
    final b = tester.getRect(find.named('xsheet-column-b-cells'));
    expect(b.left, greaterThan(a.right), reason: 'CONTROL: B\'s lanes open');

    final lines = await _linesOfACarry(
      tester,
      find.named('xsheet-layer-name-a'),
      _stops(a.right + 2, b.left - 2),
      axis: Axis.vertical,
    );

    expect(
      lines,
      {
        'timeline-row-caret-before-b': {a.right},
      },
      reason: 'past A\'s own column the pointer is past A: the gap after '
          'it, out of X\'s group — not the one before it, which keeps A '
          'where it rides and is no landing',
    );
  });
}

const _a = LayerId('a');
const _b = LayerId('b');
const _e1 = EffectId('e1');
const _e2 = EffectId('e2');

/// [layers] — A, B with a chain of two effects and C unless named — and
/// the camera, on [orientation].
Future<EditorSessionManager> _open(
  WidgetTester tester,
  TimelineOrientation orientation, {
  List<Layer>? layers,
}) => pumpTimelineHost(
  tester,
  Project(
    id: const ProjectId('lines-past-the-lanes'),
    name: 'Lines past the lanes',
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
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              ...layers ?? _chainStack(),
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  surface: const Size(1400, 900),
  orientation: orientation,
);

/// A, B with a chain of two effects, and C.
List<Layer> _chainStack() => [
  _layer('a'),
  _layer('b').copyWith(
    effects: [
      for (final id in [_e1, _e2])
        LayerEffect(
          id: id,
          kind: EffectKind.brightnessContrast,
          parameters: {'brightness': EffectParameter(value: 0.4)},
        ),
    ],
  ),
  _layer('c'),
];

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id.toUpperCase(), frames: const []);

/// B's lanes twirled open on [grid], and both its effects' parameters.
Future<void> _openTheChain(
  WidgetTester tester,
  EditorSessionManager session,
  String grid,
) async {
  session.layerSwitches.toggleLayerLanes(_b);
  await tester.pumpAndSettle();
  for (final effect in [_e1, _e2]) {
    await tester.tap(
      find.named('$grid-lane-group-toggle-b-${effectGroupLaneId(effect)}'),
    );
    await tester.pumpAndSettle();
  }
}

/// Where the rows named from [prefix] on stand together.
Rect _unitOf(WidgetTester tester, String prefix) => [
  for (final element in find
      .namedWhere((name) => name.startsWith(prefix))
      .evaluate())
    tester.getRect(find.byElementPredicate((each) => each == element)),
].reduce((all, each) => all.expandToInclude(each));

/// Every 4px from [from] to [to].
List<double> _stops(double from, double to) => [
  for (var at = from; at <= to; at += 4) at,
];

/// Every line a carry of [grip] draws as the pointer goes through [stops]
/// across the grid's frame [axis] — the rows stand across it — by its
/// key: where across it each stood.
///
/// The first drag selects the row; a drag inside the selection carries it.
Future<Map<String, Set<double>>> _linesOfACarry(
  WidgetTester tester,
  Finder grip,
  List<double> stops, {
  required Axis axis,
}) async {
  await tester.ensureVisible(grip);
  await tester.pumpAndSettle();
  await tester.dragFrom(
    tester.getCenter(grip),
    offsetAlong(axis, along: 30, across: 0),
  );
  await tester.pumpAndSettle();
  final start = tester.getCenter(grip);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 16));
  final lines = <String, Set<double>>{};
  for (final stop in stops) {
    await gesture.moveTo(
      offsetAlong(axis, along: partAlong(axis, start), across: stop),
    );
    await tester.pump();
    for (final element in _anyLine.evaluate()) {
      final line = tester.getRect(find.byKey(element.widget.key!)).center;
      (lines[(element.widget.key! as ValueKey<String>).value] ??= {}).add(
        partAcross(axis, line),
      );
    }
  }
  await gesture.moveTo(start);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return lines;
}

final _anyLine = find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(
        'timeline-row-caret-',
      ),
);
