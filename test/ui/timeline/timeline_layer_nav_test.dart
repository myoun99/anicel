import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_nav.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

Layer _layer(
  String id, {
  LayerKind kind = LayerKind.animation,
  LayerMark mark = LayerMark.none,
}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    mark: mark,
    frames: const [],
    timeline: const {},
  );
}

/// UI-R20 #14: ↑/↓ walk the timeline's DISPLAYED layer rows — the walk
/// sees exactly what the grid shows (filter and folded sections skip),
/// TVP-style. The visual stack is the HORIZONTAL display order: this
/// model list [a, b, c, s1, cam] renders top-to-bottom as
/// [cam, s1, c, b, a] (camera section on top, drawing at the bottom).
void main() {
  final stack = [
    _layer('a'),
    _layer('b', mark: LayerMark.red),
    _layer('c'),
    _layer('s1', kind: LayerKind.se),
    _layer('cam', kind: LayerKind.camera),
  ];

  LayerId? step(
    String? active,
    int direction, {
    Set<TimelineSection> hidden = const {},
    TimelineRowFilter filter = TimelineRowFilter.none,
    List<Layer>? layers,
  }) => adjacentDisplayedLayerId(
    layers: layers ?? stack,
    activeLayerId: active == null ? null : LayerId(active),
    direction: direction,
    hiddenSections: hidden,
    rowFilter: filter,
  );

  test('steps one VISUAL row (camera on top, drawing at the bottom) and '
      'clamps at both ends', () {
    expect(step('b', 1), const LayerId('a'), reason: '↓ moves screen-down');
    expect(step('b', -1), const LayerId('c'), reason: '↑ moves screen-up');
    expect(step('cam', -1), isNull, reason: 'top row clamps');
    expect(step('a', 1), isNull, reason: 'bottom row clamps');
    // The walk crosses section boundaries like the visual rows do.
    expect(step('c', -1), const LayerId('s1'));
    expect(step('s1', -1), const LayerId('cam'));
  });

  test('rows the filter hides are skipped', () {
    const redOnly = TimelineRowFilter(markColors: {LayerMark.red});
    // Only b passes; a is active (exempt) → displayed [b, a].
    expect(step('a', -1, filter: redOnly), const LayerId('b'));
    expect(step('a', 1, filter: redOnly), isNull, reason: 'a is bottom');
    expect(
      step('b', -1, filter: redOnly),
      isNull,
      reason:
          'once active, b '
          'is the only passing row — a lost its exemption and vanished',
    );
  });

  test('folded sections contribute no rows to the walk', () {
    expect(
      step('c', -1, hidden: {TimelineSection.se}),
      const LayerId('cam'),
      reason: 'SE row skipped',
    );
    expect(
      step('c', -1, hidden: {TimelineSection.se, TimelineSection.camera}),
      isNull,
      reason: 'nothing displayed above c',
    );
  });

  test('an active layer whose section is folded enters the visible rows '
      'from the matching end', () {
    // cam active but the camera section is folded → its row is gone.
    expect(
      step('cam', 1, hidden: {TimelineSection.camera}),
      const LayerId('s1'),
      reason: '↓ enters at the top displayed row',
    );
    expect(
      step('cam', -1, hidden: {TimelineSection.camera}),
      const LayerId('a'),
      reason: '↑ enters at the bottom displayed row',
    );
  });

  test('folded attach groups drop out of the walk; open groups walk '
      '(UI-R20 #9/#14)', () {
    final attachStack = [
      _layer('base'),
      Layer(
        id: const LayerId('up1'),
        name: '+1',
        frames: const [],
        timeline: const {},
        attachedToLayerId: const LayerId('base'),
      ),
      _layer('other'),
    ];
    // Visual top-to-bottom: [other, up1, base]. Open: base ↑ → up1.
    expect(step('base', -1, layers: attachStack), const LayerId('up1'));
    // Folded: the attach row skips — base ↑ lands on other.
    expect(
      adjacentDisplayedLayerId(
        layers: attachStack,
        activeLayerId: const LayerId('base'),
        direction: -1,
        collapsedAttachBaseIds: {const LayerId('base')},
      ),
      const LayerId('other'),
    );
  });

  test('degenerate inputs are no-ops', () {
    expect(step('a', 0), isNull);
    expect(step('a', 1, layers: const []), isNull);
    expect(
      step(null, 1, layers: [_layer('only')]),
      const LayerId('only'),
      reason: 'no active → the step still lands somewhere useful',
    );
    expect(
      step('only', 1, layers: [_layer('only')]),
      isNull,
      reason: 'single row: nowhere to go',
    );
  });

  test('the command channel forwards to the bound handler and no-ops '
      'unbound', () {
    final nav = TimelineLayerNavCommands();
    nav.step(1); // Unbound: must not throw.
    final calls = <int>[];
    nav.bind(calls.add);
    nav.step(-1);
    nav.step(1);
    expect(calls, [-1, 1]);
    nav.unbind();
    nav.step(1);
    expect(calls, [-1, 1]);
  });
}
