// THE RAILS PRESS THE SELECTION (row-buttons-act-on-the-selection, 유저
// 2026-09-25: 「선택범위 내부 레이어 조절하면 선택범위 레이어 모두 적용」).
//
// `test/ui/session/row_buttons_act_on_the_selection_test.dart` says what a
// press on a selected row does. These say that every button on both
// hosts' rails IS that press: a hook left pointing at a single-row verb is
// a button that ignores the selection, and nothing else would notice — the
// row it was pressed on still changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

void main() {
  group('the timeline rail', () {
    for (final (key, read) in _switches) {
      testWidgets('its $key button, pressed on a selected row, presses every '
          'selected row', (tester) async {
        final (s, a, b) = await _timelineRail(tester);
        final was = read(s, b);
        expect(read(s, a), was, reason: 'the premise: two rows alike');

        await tester.tap(find.byKey(ValueKey<String>('timeline-layer-$key-$a')));
        await tester.pumpAndSettle();

        expect([read(s, a), read(s, b)], [!was, !was]);
      });
    }

    testWidgets('its colour label, picked on a selected row, labels every '
        'selected row', (tester) async {
      final (s, a, b) = await _timelineRail(tester);

      await tester.tap(find.byKey(ValueKey<String>('timeline-layer-mark-$a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('layer-mark-option-paper')),
      );
      await tester.pumpAndSettle();

      expect(
        [_row(s, a).mark.process, _row(s, b).mark.process],
        [LayerProcess.paper, LayerProcess.paper],
      );
    });

    testWidgets('its take, picked on a selected row, keeps every selected '
        'row\'s own label', (tester) async {
      final (s, a, b) = await _timelineRail(tester);
      s.layerMarks.setLayerMark(
        b,
        const LayerMark(process: LayerProcess.paper),
      );
      await tester.pumpAndSettle();
      final labelOfA = _row(s, a).mark.process;
      expect(labelOfA, isNot(LayerProcess.paper), reason: 'the premise');

      await tester.tap(find.byKey(ValueKey<String>('timeline-layer-take-$a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('layer-take-option-3')),
      );
      await tester.pumpAndSettle();

      expect([_row(s, a).mark.take, _row(s, b).mark.take], [3, 3]);
      expect(
        [_row(s, a).mark.process, _row(s, b).mark.process],
        [labelOfA, LayerProcess.paper],
        reason: 'the chip hands over an EDIT of each row\'s mark',
      );
    });

    testWidgets('its blend, picked on a selected row, blends every selected '
        'row', (tester) async {
      final (s, a, b) = await _timelineRail(tester);

      await tester.tap(find.byKey(ValueKey<String>('timeline-layer-blend-$a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-layer-blend-option-multiply'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        [_row(s, a).blendMode, _row(s, b).blendMode],
        [LayerBlendMode.multiply, LayerBlendMode.multiply],
      );
    });

    testWidgets('its opacity slider, dragged on a selected row, moves every '
        'selected row', (tester) async {
      final (s, a, b) = await _timelineRail(tester);
      final slider = tester.widget<FieldSlider>(
        find.byKey(ValueKey<String>('timeline-layer-opacity-$a')),
      );

      slider.onChanged!(0.3);
      expect(s.opacityVerbs.dragPreview.value?.layerIds, {a, b});
      slider.onChangeEnd!(0.3);

      expect([_row(s, a).opacity, _row(s, b).opacity], [0.3, 0.3]);
    });
  });

  group('the storyboard rail', () {
    for (final (key, read) in _switches.where(
      (entry) => const {'visibility', 'timesheet', 'fx'}.contains(entry.$1),
    )) {
      testWidgets('its $key button, pressed on a selected S row, presses '
          'every selected row', (tester) async {
        final (s, s1, s2) = await _storyboardRail(tester);
        final was = read(s, s2);
        expect(read(s, s1), was, reason: 'the premise: two rows alike');

        await tester.tap(
          find.byKey(ValueKey<String>('storyboard-layer-$key-$s1')).first,
        );
        await tester.pumpAndSettle();

        expect([read(s, s1), read(s, s2)], [!was, !was]);
      });
    }

    testWidgets('its colour label, picked on a selected S row, labels every '
        'selected row', (tester) async {
      final (s, s1, s2) = await _storyboardRail(tester);

      await tester.tap(
        find.byKey(ValueKey<String>('storyboard-layer-mark-$s1')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('layer-mark-option-paper')),
      );
      await tester.pumpAndSettle();

      expect(
        [_row(s, s1).mark.process, _row(s, s2).mark.process],
        [LayerProcess.paper, LayerProcess.paper],
      );
    });

    testWidgets('its opacity slider, dragged on a selected S row, moves every '
        'selected row', (tester) async {
      final (s, s1, s2) = await _storyboardRail(tester);
      final slider = tester.widget<FieldSlider>(
        find.byKey(ValueKey<String>('storyboard-layer-opacity-$s1')).first,
      );

      slider.onChanged!(0.3);
      expect(s.opacityVerbs.dragPreview.value?.layerIds, {s1, s2});
      slider.onChangeEnd!(0.3);

      expect([_row(s, s1).opacity, _row(s, s2).opacity], [0.3, 0.3]);
    });
  });
}

/// The rail's two-state buttons by their key, each read as the button
/// shows it.
final List<(String, bool Function(EditorSessionManager s, LayerId id))>
_switches = [
  ('visibility', (s, id) => _row(s, id).isVisible),
  ('timesheet', (s, id) => _row(s, id).onTimesheet),
  ('fill-reference', (s, id) => _row(s, id).isFillReference),
  ('fx', (s, id) => fxEnabledFromState(s.effectsAndFx.layerFxState(id))),
  ('onion', (s, id) => s.onionSkin.isLayerOnionSkinEnabled(id)),
];

Layer _row(EditorSessionManager s, LayerId id) =>
    requireLayerAnywhere(s.repository.requireProject(), id);

void _select(EditorSessionManager s, List<LayerId> ids) =>
    s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

EditorSessionManager _session() {
  final s = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(s.dispose);
  return s;
}

Future<void> _roomy(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// The timeline tab over two cels, both selected.
Future<(EditorSessionManager, LayerId, LayerId)> _timelineRail(
  WidgetTester tester,
) async {
  await _roomy(tester);
  final s = _session();
  s.layerStack.addLayerOfKind(LayerKind.animation);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => TimelineTabHost(
            session: s,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: 24,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final cels = [
    for (final layer in s.layers)
      if (layer.kind == LayerKind.animation) layer.id,
  ];
  _select(s, cels);
  await tester.pumpAndSettle();
  return (s, cels[0], cels[1]);
}

/// The storyboard tab with the track's two S rows selected.
Future<(EditorSessionManager, LayerId, LayerId)> _storyboardRail(
  WidgetTester tester,
) async {
  await _roomy(tester);
  final s = _session();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => StoryboardTabHost(
            session: s,
            pixelsPerFrame: 12,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            thumbnailFor: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final ses = [
    for (final layer in s.repository.requireProject().tracks.single.seLayers)
      layer.id,
  ];
  _select(s, ses);
  await tester.pumpAndSettle();
  return (s, ses[0], ses[1]);
}
