import 'dart:math' show max;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

import '../../helpers/named_finders.dart';

/// 🚨AN FX SWEEP PAINTS EACH LANE GROUP BY ITS OWN SWITCH, AND ONLY WHERE
/// ONE IS DRAWN (I-89 ①ⓒ).
///
/// The timeline's sweep read ONE live switch for every lane row — the
/// layer's TRANSFORM flag. So an effect header spread the transform's state
/// instead of its own, and a member lane, which wears no fx button, was
/// pressed as if it did: a member's lane id names its effect, so each one
/// crossed flipped that effect once more.
void main() {
  Future<_Rows> aBlurredRowAboveAPlainOne(WidgetTester tester) async {
    // The WHOLE app: lane expansion is HomePage's state.
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final lower = session.activeLayerId!;
    session.layerStack.addLayer();
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    final upper = session.activeLayerId!;
    expect(upper, isNot(lower), reason: 'the new row is the active one');
    final blur = _rowOf(session, upper).effects.single.id;

    // The add shows the row's lanes, its header open (F-396).
    final header = effectGroupLaneId(blur);
    await tester.ensureVisible(
      find.named('timeline-lane-group-toggle-$upper-$header'),
    );
    await tester.pumpAndSettle();
    return (session: session, upper: upper, lower: lower, blur: blur);
  }

  Future<void> sweep(WidgetTester tester, Offset from, double toY) async {
    // 🚨MOUSE: a finger is not a timeline edit device unless one-finger
    // drawing is on, so a touch here measures nothing.
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(
        Offset(from.dx, from.dy + (toY - from.dy) * step / 6),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a sweep begun on an EFFECT header spreads that effect\'s new '
      'state, not the transform switch\'s', (tester) async {
    final f = await aBlurredRowAboveAPlainOne(tester);
    final header = find.named(
      'timeline-lane-group-fx-${f.upper}-${effectGroupLaneId(f.blur)}',
    );
    final lowerFx = find.named('timeline-layer-fx-${f.lower}');
    expect(_blurOn(f), isTrue);
    expect(
      _rowOf(f.session, f.upper).transformEnabled,
      isTrue,
      reason:
          'the transform reads ON — the opposite of what the press sets '
          'the effect to, or the two reads could not be told apart',
    );
    expect(f.session.effectsAndFx.layerFxState(f.lower), LayerFxState.on);

    final from = tester.getCenter(header);
    final to = tester.getCenter(lowerFx);
    expect(
      to.dy,
      greaterThan(from.dy),
      reason: 'the plain row sits below the effect and its members',
    );
    expect((to.dx - from.dx).abs(), lessThan(6), reason: 'one column');
    await sweep(tester, from, to.dy);

    expect(_blurOn(f), isFalse, reason: 'the press bypassed the effect');
    expect(
      f.session.effectsAndFx.layerFxState(f.lower),
      LayerFxState.off,
      reason:
          'and the sweep spreads what the press set — the EFFECT\'s '
          'switch, off. It read the transform\'s, on, and left the row on',
    );
  });

  testWidgets('🚨a sweep presses no MEMBER lane — a member wears no fx', (
    tester,
  ) async {
    final f = await aBlurredRowAboveAPlainOne(tester);
    final header = find.named(
      'timeline-lane-group-fx-${f.upper}-${effectGroupLaneId(f.blur)}',
    );
    final transformHeader = find.named(
      'timeline-lane-group-fx-${f.upper}-transform-group',
    );
    final lowerFx = find.named('timeline-layer-fx-${f.lower}');
    // Everything off, each by its own button.
    for (final button in [transformHeader, header, lowerFx]) {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(_rowOf(f.session, f.upper).transformEnabled, isFalse);
    expect(_blurOn(f), isFalse);
    expect(f.session.effectsAndFx.layerFxState(f.lower), LayerFxState.off);

    // The effect's lanes stand ABOVE the Transform group, as After Effects
    // lays them out — so a sweep up from the plain row crosses the
    // Transform header, a switch, and then the effect's lowest member.
    final lowestMember = [
      for (final parameter in ['blurriness', 'blurDimensions'])
        tester
            .getCenter(
              find.byKey(
                ValueKey<String>(
                  'timeline-lane-label-${f.upper}-'
                  '${effectLaneId(f.blur, parameter)}',
                ),
              ),
            )
            .dy,
    ].reduce(max);
    final from = tester.getCenter(lowerFx);
    expect(
      tester.getCenter(header).dy,
      lessThan(lowestMember),
      reason:
          'the sweep stops on the lowest member, so the header — above '
          'it — is never reached: whatever the effect does is the member\'s',
    );
    expect(
      tester.getCenter(transformHeader).dy,
      inExclusiveRange(lowestMember, from.dy),
      reason: 'measured, not assumed: the Transform header lies between',
    );
    await sweep(tester, from, lowestMember);

    expect(
      f.session.effectsAndFx.layerFxState(f.lower),
      LayerFxState.on,
      reason: 'the press turned the plain row on: the sweep paints ON',
    );
    expect(
      _rowOf(f.session, f.upper).transformEnabled,
      isTrue,
      reason: 'the Transform header wears a switch, and the sweep painted it',
    );
    expect(
      _blurOn(f),
      isFalse,
      reason:
          'then it crossed a member lane, which wears none — nothing there '
          'to press. Read by its effect\'s switch (off), a member is called '
          'unturned and pressed, and its lane id names its effect: the '
          'effect would come on',
    );
  });
}

/// A row carrying a blur, above a plain row.
typedef _Rows = ({
  EditorSessionManager session,
  LayerId upper,
  LayerId lower,
  EffectId blur,
});

/// The row as the project holds it now — what every write lands in.
Layer _rowOf(EditorSessionManager session, LayerId id) =>
    requireLayerAnywhere(session.repository.requireProject(), id);

bool _blurOn(_Rows f) => _rowOf(
  f.session,
  f.upper,
).effects.singleWhere((effect) => effect.id == f.blur).enabled;
