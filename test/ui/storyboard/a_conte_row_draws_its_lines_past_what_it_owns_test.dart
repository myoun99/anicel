import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show EffectRowSubject, LaneRowSubject, LayerRowDragTarget;
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🚨sheet-gap-stands-inside-open-lanes (10-25), the timeline's law on the
/// conte's rail (「타임라인 패널에만 있는 것은 콘티 패널에도」): a row's
/// UNIT is itself and the lanes it opens after it — an S row's, a conte
/// row's, an fx header's parameters — and a V row's is its whole track
/// group, which its drag carries. A carry's lines stand at a unit's ends.
///
/// ↩️Every row drew its two lines at its own label's edges: under the last
/// S row, the last conte row and a chain's last header while their lanes
/// followed, and at the V row inside a group whose drop lands past the
/// rows above and below it.
void main() {
  testWidgets('the line after the last S row stands past its lanes, at the '
      'end of the S rows', (tester) async {
    final session = await _open(tester, [_track('t', se: ['S1', 'S2'])]);
    session.layerSwitches.toggleLayerLanes(const LayerId('S1'));
    await tester.pumpAndSettle();
    final rows = _zone(tester, 't-se');
    expect(
      tester.getRect(find.named('storyboard-layer-row-S1')).bottom,
      lessThan(rows.bottom),
      reason: 'CONTROL: S1 is the last S row, its lanes open after it',
    );

    final lines = await _linesOfACarry(
      tester,
      'S2',
      _stops(rows.top, rows.bottom + 12),
    );

    expect(lines['timeline-row-caret-after-S1'], {rows.bottom});
  });

  testWidgets('the line after a chain\'s last header on an S row stands '
      'past its parameters', (tester) async {
    final session = await _open(tester, [
      _track('t', se: ['S1'], chainOn: 'S1'),
    ]);
    session.layerSwitches.toggleLayerLanes(const LayerId('S1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.named(
        'storyboard-lane-group-toggle-S1-${effectGroupLaneId(_e2)}',
      ),
    );
    await tester.pumpAndSettle();
    final header = _labelOf(tester, (subject) => subject == _header(_e2));
    final parameters = _labelOf(
      tester,
      (subject) =>
          subject is LaneRowSubject &&
          subject.laneId.startsWith(effectLaneId(_e2, '')),
    );
    expect(
      header.bottom,
      lessThan(parameters.bottom),
      reason: 'CONTROL: the last header\'s parameters stand after it',
    );

    final lines = await _linesOfACarry(
      tester,
      find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is LayerRowDragTarget &&
                  widget.subject == _header(_e1),
            ),
            matching: find.byType(Text),
          )
          .first,
      _stops(header.top, parameters.bottom + 12),
    );

    expect(
      lines['timeline-row-caret-after-${_e2.value}'],
      {parameters.bottom},
    );
  });

  testWidgets('the line after the last conte row stands past its lanes, at '
      'the end of the conte rows', (tester) async {
    await _open(tester, [
      _track('t', conte: ['CA', 'CB']),
    ]);
    await tester.tap(find.named('storyboard-lane-toggle-CA'));
    await tester.pumpAndSettle();
    final rows = _zone(tester, 't-conte');
    expect(
      tester.getRect(find.named('storyboard-layer-row-CA')).bottom,
      lessThan(rows.bottom),
      reason: 'CONTROL: CA is the last conte row, its lanes open after it',
    );

    final lines = await _linesOfACarry(
      tester,
      'CB',
      _stops(rows.top, rows.bottom + 12),
    );

    expect(lines['timeline-row-caret-after-conte-row:t'], {rows.bottom});
  });

  testWidgets('a V row\'s lines stand at its track group\'s ends, not its '
      'own', (tester) async {
    await _open(tester, [
      _track('t', se: ['S1']),
      _track('u', se: ['S3']),
    ]);
    final (t, u) = (_group(tester, 't'), _group(tester, 'u'));
    expect(
      t.bottom,
      u.top,
      reason: 'CONTROL: the two groups meet, and every row is in one',
    );

    final lines = await _linesOfACarry(
      tester,
      'Video 2',
      // A group's pitch is the group: past the last one takes a group's
      // travel more.
      _stops(t.top - 8, u.bottom + u.height),
    );

    expect(lines, {
      'timeline-row-caret-before-t': {t.top},
      'timeline-row-caret-before-u': {u.top},
      'timeline-row-caret-after-u': {u.bottom},
    });
  });
}

const _e1 = EffectId('e1');
const _e2 = EffectId('e2');

EffectRowSubject _header(EffectId effect) =>
    EffectRowSubject(const LayerId('S1'), effect);

/// A track [id] of one cut with the conte rows [conte] (one of its own when
/// none is named) — the first the
/// base, the rest riding it — and the S rows [se], the one [chainOn] names
/// carrying a chain of two effects.
Track _track(
  String id, {
  List<String>? conte,
  List<String> se = const [],
  String? chainOn,
}) => Track(
  id: TrackId(id),
  name: id,
  cuts: [
    Cut(
      id: CutId('$id-cut'),
      name: '$id cut',
      duration: 12,
      canvasSize: const CanvasSize(width: 1280, height: 720),
      camera: CutCamera.empty(),
      layers: [
        for (final (index, name) in (conte ?? ['$id-conte']).indexed)
          Layer(
            id: LayerId(name),
            name: name,
            kind: LayerKind.storyboard,
            frames: const [],
            attachedToLayerId: index == 0 ? null : LayerId(conte!.first),
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
        effects: [
          if (name == chainOn)
            for (final effect in [_e1, _e2])
              LayerEffect(
                id: effect,
                kind: EffectKind.brightnessContrast,
                parameters: {'brightness': EffectParameter(value: 0.4)},
              ),
        ],
      ),
  ],
);

Future<EditorSessionManager> _open(
  WidgetTester tester,
  List<Track> tracks,
) => pumpStoryboardHost(
  tester,
  Project(
    id: const ProjectId('conte-lines'),
    name: 'Conte lines',
    createdAt: DateTime.utc(2026, 10, 25),
    tracks: tracks,
  ),
  surface: const Size(1400, 1100),
);

final _rail = find.byKey(
  const ValueKey<String>('storyboard-track-label-rail'),
);

/// Where the rail's section zone [name] stands.
Rect _zone(WidgetTester tester, String name) => tester.getRect(
  find.byKey(ValueKey<String>('storyboard-section-zone-$name')),
);

/// Where track [id]'s group stands: its camera section to its conte rows.
Rect _group(WidgetTester tester, String id) =>
    _zone(tester, '$id-camera').expandToInclude(_zone(tester, '$id-conte'));

/// Where the rail labels whose subject [owned] says stand together.
Rect _labelOf(WidgetTester tester, bool Function(Object subject) owned) => [
  for (final element in find
      .byWidgetPredicate(
        (widget) => widget is LayerRowDragTarget && owned(widget.subject),
      )
      .evaluate())
    tester.getRect(find.byElementPredicate((each) => each == element)),
].reduce((all, each) => all.expandToInclude(each));

/// Every 4px from [from] to [to].
List<double> _stops(double from, double to) => [
  for (var at = from; at <= to; at += 4) at,
];

/// Every line a carry of [grip] — a rail label, or the label of the row
/// named so — draws as the pointer goes through [stops] down the rail, by
/// its key: where down it each stood.
///
/// The first drag selects the row; a drag inside the selection carries it.
Future<Map<String, Set<double>>> _linesOfACarry(
  WidgetTester tester,
  Object grip,
  List<double> stops,
) async {
  final at = grip is Finder
      ? grip
      : find.descendant(of: _rail, matching: find.text(grip as String)).first;
  await tester.dragFrom(
    tester.getCenter(at),
    const Offset(InstantTapRegion.travelSlop + 2, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  final start = tester.getCenter(at);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  final lines = <String, Set<double>>{};
  for (final stop in stops) {
    await gesture.moveTo(Offset(start.dx, stop));
    await tester.pump();
    for (final element in _anyLine.evaluate()) {
      (lines[(element.widget.key! as ValueKey<String>).value] ??= {}).add(
        tester.getRect(find.byKey(element.widget.key!)).center.dy,
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
