import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_outcomes.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cel_text_tool_harness.dart'
    show textToolCutId, textToolProject;
import '../../helpers/storyboard_host.dart';

/// 🗣️a-failed-plugin-shows-the-cel-silently-Q1 (유저 2026-11-08): 「원래 셀
/// + 머리를 회색으로, 이름 뒤 ⚠ 칸은 늘 잡아 둔다」 — a plugin effect's
/// header keeps a ⚠ after its name whether or not its plugin failed, so
/// the name never narrows and widens with it; at a frame its run failed the
/// mark fills and the name greys, as one of a plugin this device has not
/// greys (I-132-Q28).
void main() {
  final glow = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': <Object?>[],
  })!;
  final effect = LayerEffect.defaults(
    id: const EffectId('fx-glow'),
    kind: EffectKind.plugin,
    plugin: glow,
  );
  const row = LayerId('a');
  void tell(FxPluginOutcomes outcomes, int frame, {required bool failed}) =>
      outcomes.toldFor(
        (owner: row, effect: effect.id, wearer: row),
        sampleLayerEffectAt(effect, frame, worn: null),
        cut: const CutId('c'),
        frame: frame,
      )(failed: failed);

  test('a plugin\'s header reads its runs; an app effect\'s keeps no slot', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    PropertyLaneRow headerOf(LayerEffect of, {FxPluginOutcomes? told}) =>
        effectPropertyLanes(
          [of],
          isExpanded: (_) => false,
          pluginOutcomes: switch (told) {
            final outcomes? => (outcomes: outcomes, owner: row),
            null => null,
          },
        ).single;

    final failures = headerOf(effect, told: outcomes).pluginFailures!;
    tell(outcomes, 3, failed: true);
    expect(failures.failedAt(3), isTrue);
    expect(failures.failedAt(2), isFalse);

    final untold = headerOf(effect).pluginFailures!;
    expect(untold.failedAt(3), isFalse,
        reason: 'a rail not told keeps the slot, never filled');

    final blur = LayerEffect.defaults(
      id: const EffectId('fx-blur'),
      kind: EffectKind.blur,
    );
    expect(headerOf(blur, told: outcomes).pluginFailures, isNull);
  });

  test('the slot of an effect that does not run is never filled — switched '
      'off, or of a plugin this device has not — and a header asks of its '
      'own chain', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    tell(outcomes, 3, failed: true);
    bool failedAt3(
      LayerEffect of, {
      LayerId owner = row,
      bool onDevice = true,
    }) => effectPropertyLanes(
      [of],
      isExpanded: (_) => false,
      hasPlugin: (_) => onDevice,
      pluginOutcomes: (outcomes: outcomes, owner: owner),
    ).single.pluginFailures!.failedAt(3);

    expect(failedAt3(effect), isTrue);
    expect(failedAt3(effect.copyWith(enabled: false)), isFalse,
        reason: 'what it told when on is not the frame\'s now');
    expect(failedAt3(effect, onDevice: false), isFalse,
        reason: 'it greys as not on this device, and runs nothing');
    expect(failedAt3(effect, owner: const LayerId('b')), isFalse,
        reason: 'another row\'s effect of the same id');
  });

  test('a row\'s header asks of the row it heads — another row\'s effect '
      'of the same id is another', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final a = Layer(id: row, name: 'A', frames: const [], effects: [effect]);
    final b = Layer(
      id: const LayerId('b'),
      name: 'B',
      frames: const [],
      effects: [effect],
    );
    bool failedAt3(Layer heading) => propertyLanesForRow(
      layer: heading,
      rows: [a, b],
      expandedGroupKeys: const {},
      valueSourceAt: null,
      poseCentre: null,
      hasPlugin: (_) => true,
      pluginOutcomes: outcomes,
    ).firstWhere((lane) => lane.pluginFailures != null).pluginFailures!
        .failedAt(3);

    tell(outcomes, 3, failed: true);
    expect(failedAt3(a), isTrue);
    expect(failedAt3(b), isFalse);
  });

  testWidgets('the storyboard\'s V row header asks of its track\'s chain', (
    tester,
  ) async {
    final plugins = await installedShiftingFxPlugin(tester);
    final project = textToolProject();
    final track = project.tracks.single;
    final fx = shiftingFxPluginLayerEffect();
    final session = EditorSessionManager(
      initialProject: project.copyWith(
        tracks: [
          track.copyWith(effects: [fx], lanesExpanded: true),
        ],
      ),
      fxPlugins: plugins,
    );
    addTearDown(session.dispose);
    await pumpStoryboardHostOn(tester, session);
    final carrier = trackTransformLaneCarrierId(track.id);
    final mark = find.byKey(
      ValueKey<String>(
        'storyboard-lane-group-plugin-failed-$carrier-'
        '${effectGroupLaneId(fx.id)}',
      ),
    );
    expect(mark, findsOneWidget, reason: '⛔fixture: the V row is open');
    Color? markColour() => tester.widget<Icon>(mark).color;
    expect(markColour(), Colors.transparent);

    plugins.outcomes.toldFor(
      (owner: track.id, effect: fx.id, wearer: track.id),
      sampleLayerEffectAt(fx, 0, worn: null),
      cut: textToolCutId,
      frame: 0,
    )(failed: true);
    await tester.pumpAndSettle();
    expect(markColour(), isNot(Colors.transparent));
  });

  testWidgets('the mark keeps its place; a failure at the frame the row '
      'stands on fills it and greys the name', (tester) async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final cursor = ValueNotifier<int?>(3);
    addTearDown(cursor.dispose);
    final header = effectPropertyLanes(
      [effect],
      isExpanded: (_) => false,
      pluginOutcomes: (outcomes: outcomes, owner: row),
    ).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 40,
            child: TimelineLaneControlsRow(
              layer: Layer(id: row, name: 'A', frames: const []),
              lane: header,
              metrics: TimelineGridMetrics.defaults,
              frameCursor: cursor,
            ),
          ),
        ),
      ),
    );
    final scheme = ThemeData().colorScheme;
    final mark = find.byIcon(Icons.warning_rounded);
    Color? markColour() => tester.widget<Icon>(mark).color;
    Color? nameColour() =>
        tester.widget<Text>(find.text(header.label)).style?.color;

    final kept = tester.getRect(mark);
    final nameRoom = tester.getRect(find.text(header.label));
    expect(markColour(), Colors.transparent);
    expect(nameColour(), scheme.onSurface);

    tell(outcomes, 3, failed: true);
    await tester.pump();
    expect(markColour(), scheme.error);
    expect(nameColour(), scheme.onSurface.withValues(alpha: 0.35));
    expect(tester.getRect(mark), kept, reason: 'the mark stood there already');
    expect(tester.getRect(find.text(header.label)), nameRoom,
        reason: 'the name neither narrows nor moves');

    cursor.value = 4;
    await tester.pump();
    expect(markColour(), Colors.transparent,
        reason: 'it failed at frame 3, not at the frame the row stands on');

    cursor.value = 3;
    tell(outcomes, 3, failed: false);
    await tester.pump();
    expect(markColour(), Colors.transparent, reason: 'drawn again, it clears');
    expect(nameColour(), scheme.onSurface);
  });
}
