import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart'
    show AppStrings, AppText;
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/conte_track_fixture.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️I-132-Q33 c 「머리 이름 뒤에 경고 글자를 늘 둔다」: the header of a
/// plugin's effect standing where no plugin runs greys and says so after its
/// name — on every rail, asked where the rail reads the row's values, at the
/// frame the cursor is on.
void main() {
  final plugin = shiftingFxPluginLayerEffect();
  final pluginHeader = effectGroupLaneId(plugin.id);
  const b = EffectId('b');
  LayerEffect blur(EffectParameter amount) => LayerEffect.defaults(
    id: b,
    kind: EffectKind.blur,
  ).withParameter('blurriness', amount);
  Layer rowOf(
    List<LayerEffect> effects, {
    LayerKind kind = LayerKind.animation,
  }) => Layer(
    id: const LayerId('a'),
    name: 'a',
    kind: kind,
    frames: const [],
    effects: effects,
  );
  final warning = AppText.strings.fxPluginIdleHere;

  group('the lanes', () {
    PropertyLaneRow headerOf(
      Layer row, {
      ({Layer layer, int frame}) Function(int frameIndex)? source,
      String? lane,
    }) => propertyLanesForRow(
      layer: row,
      rows: [row],
      expandedGroupKeys: const {},
      valueSourceAt: source,
      poseCentre: null,
      hasPlugin: null,
    ).singleWhere((header) => header.laneId == (lane ?? pluginHeader));
    ({Layer layer, int frame}) Function(int) itself(Layer row) =>
        (frame) => (layer: row, frame: frame);

    test('a plugin\'s header answers whether it stands idle; an app fx\'s '
        'header and a rail not told where it reads asks nothing', () {
      final blurred = rowOf([blur(EffectParameter(value: 3)), plugin]);
      expect(headerOf(blurred, source: itself(blurred)).pluginIdleAt!(0),
          isTrue);
      final alone = rowOf([plugin]);
      expect(headerOf(alone, source: itself(alone)).pluginIdleAt!(0), isFalse);
      expect(
        headerOf(
          blurred,
          source: itself(blurred),
          lane: effectGroupLaneId(b),
        ).pluginIdleAt,
        isNull,
      );
      expect(headerOf(blurred).pluginIdleAt, isNull);
    });

    test('it is asked of the row and frame the rail reads values off — a '
        'projection\'s chain and kind, at its frame', () {
      // Nothing at frame 0, a blur from frame 1.
      final keyed = rowOf([
        blur(
          EffectParameter(
            track: PropertyTrack<double>().withKey(0, 0).withKey(1, 10),
          ),
        ),
        plugin,
      ]);
      expect(headerOf(keyed, source: itself(keyed)).pluginIdleAt!(0), isFalse);
      expect(headerOf(keyed, source: itself(keyed)).pluginIdleAt!(1), isTrue);
      expect(
        headerOf(keyed, source: (frame) => (layer: keyed, frame: frame + 1))
            .pluginIdleAt!(0),
        isTrue,
        reason: 'the frame the rail frame reads',
      );
      final alone = rowOf([plugin]);
      expect(
        headerOf(alone, source: (frame) => (layer: keyed, frame: 1))
            .pluginIdleAt!(0),
        isTrue,
        reason: 'the chain of the row read',
      );
      expect(
        headerOf(
          alone,
          source: (frame) => (
            layer: rowOf([plugin], kind: LayerKind.image),
            frame: frame,
          ),
        ).pluginIdleAt!(0),
        isTrue,
        reason: 'the kind of the row read',
      );
    });

    test('a folder\'s plugin stands idle', () {
      final folder = rowOf([plugin], kind: LayerKind.folder);
      expect(headerOf(folder, source: itself(folder)).pluginIdleAt!(0), isTrue);
    });

    test('a cut\'s rail asks it', () {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('idle'),
          name: 'idle',
          createdAt: DateTime.utc(2026, 10, 30),
          tracks: [
            Track(
              id: const TrackId('t1'),
              name: 'V1',
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: 'c',
                  duration: 4,
                  canvasSize: const CanvasSize(width: 64, height: 36),
                  layers: [rowOf([blur(EffectParameter(value: 3)), plugin])],
                ),
              ],
            ),
          ],
        ),
      )..selectCut(const CutId('c'));
      addTearDown(session.dispose);
      final lanes = timelineLanesForLayer(
        layer: session.layers.singleWhere(
          (row) => row.id == const LayerId('a'),
        ),
        session: session,
        expandedGroupKeys: const {},
      );
      expect(
        lanes
            .singleWhere((lane) => lane.laneId == pluginHeader)
            .pluginIdleAt!(0),
        isTrue,
      );
    });
  });

  group('the header', () {
    final onSurface = ThemeData().colorScheme.onSurface;
    final error = ThemeData().colorScheme.error;
    Future<ValueNotifier<int?>> pumpHeader(
      WidgetTester tester, {
      String label = 'Shift',
      double along = 600,
      Axis axis = Axis.horizontal,
    }) async {
      final cursor = ValueNotifier<int?>(0);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TimelineLaneControlsRow(
                layer: rowOf([plugin]),
                lane: PropertyLaneRow(
                  laneId: pluginHeader,
                  label: label,
                  keyMarks: const {},
                  isGroupHeader: true,
                  groupEnabled: true,
                  pluginIdleAt: (frame) => frame >= 2,
                ),
                metrics: TimelineGridMetrics.defaults,
                frameCursor: cursor,
                axis: axis,
                width: axis == Axis.horizontal ? along : 40,
                height: axis == Axis.horizontal ? 40 : along,
              ),
            ),
          ),
        ),
      );
      return cursor;
    }

    testWidgets('greys and says so after its name at a frame where it stands '
        'idle — and only there, as the cursor moves', (tester) async {
      final cursor = await pumpHeader(tester);
      Color? colourOf(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      expect(find.text(warning), findsNothing);
      expect(colourOf('Shift'), onSurface);

      cursor.value = 2;
      await tester.pump();
      expect(find.text(warning), findsOneWidget);
      expect(colourOf('Shift'), onSurface.withValues(alpha: 0.35));
      expect(colourOf(warning), error);
      expect(
        tester.getTopLeft(find.text(warning)).dx -
            tester.getTopRight(find.text('Shift')).dx,
        4,
        reason: 'after its name',
      );

      cursor.value = 1;
      await tester.pump();
      expect(find.text(warning), findsNothing);
      expect(colourOf('Shift'), onSurface);
    });

    testWidgets('in a narrow header the name is cut and the warning is not '
        '(「머리 폭이 좁으면 이름이 그만큼 잘린다」), and neither runs past it', (
      tester,
    ) async {
      final cursor = await pumpHeader(
        tester,
        label: 'A plugin with a long, long name',
        along: 330,
      );
      cursor.value = 2;
      await tester.pump();
      expect(tester.takeException(), isNull);
      bool cut(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .didExceedMaxLines;
      expect(cut('A plugin with a long, long name'), isTrue);
      expect(cut(warning), isFalse);
    });

    testWidgets('narrower than its warning, the warning is cut too — and '
        'nothing runs past the header, on either axis', (tester) async {
      // 250 leaves the name's room ~120 on either axis (the rest is the
      // header's controls), under the ~195 the warning takes.
      for (final axis in [Axis.vertical, Axis.horizontal]) {
        final cursor = await pumpHeader(tester, axis: axis, along: 250);
        cursor.value = 2;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$axis');
      }
      expect(
        tester.renderObject<RenderParagraph>(find.text(warning))
            .didExceedMaxLines,
        isTrue,
      );
    });

    testWidgets('stood up on the sheet, the warning stands under the name', (
      tester,
    ) async {
      final cursor = await pumpHeader(tester, axis: Axis.vertical);
      cursor.value = 2;
      await tester.pump();
      Finder written(String text) => find.byWidgetPredicate(
        (widget) => widget is VerticalWritingText && widget.text == text,
      );
      expect(written(warning), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(written(warning)).dy -
            tester.getBottomLeft(written('Shift')).dy,
        4,
      );
    });
  });

  test('it says so in the words the answer gave (🗣️I-132-Q33 c)', () {
    expect(
      AppStrings.of(AppLanguage.ko).fxPluginIdleHere,
      '⚠ 이 자리에서는 돌지 않음',
    );
  });

  testWidgets('a plugin on a track\'s chain stands idle on the storyboard', (
    tester,
  ) async {
    final project = conteTrackProject();
    final session = EditorSessionManager(
      initialProject: project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(lanesExpanded: true, effects: [plugin]),
        ],
      ),
    );
    addTearDown(session.dispose);
    await pumpStoryboardHostOn(tester, session);
    expect(find.text(warning), findsOneWidget);
  });
}
