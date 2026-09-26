import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet/sheet_strata.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailTier;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show CutTrimDragPreview;
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// 🚨A SHEET RE-RECORDS ONLY THE STRATUM WHOSE PRINT CHANGED.
///
/// 유저 2026-09-25: 「그림 수정하거나 텍스트 바뀌거나 하는데 용지
/// 리빌드하면 너무 비효율적이잖아」 · 「캔버스베이스패널은 다 통일해줘」.
/// Read as each stratum's bake count (`RenderStaticRaster.captureCount` —
/// the test renderer bakes): a renamed cut re-records the values alone, a
/// stroke the ink alone, a landed picture the strata that print pictures —
/// and a change of the sheet's shape re-records its form.
///
/// Each host is rebuilt on every signal, as the workspace rebuilds it
/// (`workspace_tabs.dart`): a stratum's inputs have to compare equal across
/// a rebuild, not merely go untouched by one.
void main() {
  late EditorSessionManager session;
  late ChangeNotifier thumbnails;
  late ChangeNotifier images;
  late ValueNotifier<bool> brushAllowed;
  late ValueNotifier<BrushToolState> brushTool;

  BrushStrokeCommitData oneDab() => BrushStrokeCommitData(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFF000000,
        size: 4,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );

  // Each sheet's strata, its host with its ink, and a stroke onto one of
  // its surfaces through the session's history.
  final sheets =
      <
        ({
          String sheet,
          Set<SheetStratum> strata,
          (Widget Function(), void Function()) Function() mount,
        })
      >[
        (
          sheet: 'timesheet',
          strata: {SheetStratum.form, SheetStratum.content, SheetStratum.ink},
          mount: () {
            final ink = TimesheetInkController();
            addTearDown(ink.dispose);
            return (
              () => TimesheetTabHost(
                session: session,
                continuous: false,
                onContinuousChanged: (_) {},
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
              ),
              () => ink.commitStroke(
                plane: TimesheetInkPlane.strip,
                key: timesheetInkStripKey(session.requireActiveCut.id, 0),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          sheet: 'conte',
          strata: SheetStratum.values.toSet(),
          mount: () {
            final ink = ConteInkController();
            addTearDown(ink.dispose);
            return (
              () => ConteTabHost(
                session: session,
                thumbnails: (
                  resolve:
                      (cut, frame, {tier = StoryboardThumbnailTier.strip}) =>
                          null,
                  landed: thumbnails,
                ),
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
                imageFor: (_) => null,
                imageRepaint: images,
              ),
              () => ink.commitStroke(
                plane: ConteInkPlane.page,
                key: conteInkPageKey(0),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          sheet: 'envelope',
          strata: {SheetStratum.form, SheetStratum.content, SheetStratum.ink},
          mount: () {
            final ink = CutEnvelopeInkController();
            addTearDown(ink.dispose);
            return (
              () => CutEnvelopeTabHost(
                session: session,
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
                imageFor: (_) => null,
                imageRepaint: images,
              ),
              () => ink.commitStroke(
                plane: null,
                key: envelopeInkBoxKey(session.requireActiveCut.id, 'box'),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
      ];

  for (final sheet in sheets) {
    // Pumps the sheet's host, rebuilt on every signal, and answers how many
    // times each of its strata bakes for a change — and its stroke.
    Future<
      (
        Future<Map<SheetStratum, int>> Function(void Function() change),
        void Function(),
      )
    >
    mount(WidgetTester tester) async {
      session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);
      thumbnails = ChangeNotifier();
      addTearDown(thumbnails.dispose);
      images = ChangeNotifier();
      addTearDown(images.dispose);
      brushAllowed = ValueNotifier<bool>(false);
      addTearDown(brushAllowed.dispose);
      brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brushTool.dispose);
      final (host, stroke) = sheet.mount();
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([
                session,
                thumbnails,
                images,
                session.languageSettings,
                brushAllowed,
              ]),
              builder: (context, _) => host(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Map<SheetStratum, int> bakes() {
        final byLabel = {
          for (final raster in tester.renderObjectList<RenderStaticRaster>(
            find.byType(StaticRaster),
          ))
            raster.debugLabel: raster.captureCount,
        };
        return {
          for (final stratum in sheet.strata)
            stratum: byLabel['${sheet.sheet}-${stratum.name}']!,
        };
      }

      expect(
        bakes().values,
        everyElement(greaterThan(0)),
        reason: 'fixture: every stratum bakes — the instrument reads',
      );
      Future<Map<SheetStratum, int>> rebakes(void Function() change) async {
        final before = bakes();
        change();
        await tester.pumpAndSettle();
        final after = bakes();
        return {
          for (final stratum in sheet.strata)
            stratum: after[stratum]! - before[stratum]!,
        };
      }

      return (rebakes, stroke);
    }

    Map<SheetStratum, int> only(Set<SheetStratum> rebaked) => {
      for (final stratum in sheet.strata)
        stratum: rebaked.contains(stratum) ? 1 : 0,
    };

    testWidgets('${sheet.sheet}: a renamed cut re-records the values '
        'alone', (tester) async {
      final (rebakes, _) = await mount(tester);
      expect(
        await rebakes(() => session.cutVerbs.renameActiveCut('C-39')),
        only({SheetStratum.content}),
      );
    });

    testWidgets('${sheet.sheet}: a stroke, and its undo, re-record the ink '
        'alone', (tester) async {
      final (rebakes, stroke) = await mount(tester);
      expect(await rebakes(stroke), only({SheetStratum.ink}));
      expect(await rebakes(session.undo), only({SheetStratum.ink}));
    });

    testWidgets('${sheet.sheet}: the brush switched on and off re-records '
        'the ink alone', (tester) async {
      final (rebakes, _) = await mount(tester);
      // The windows a live brush shows stand down in the print, and come
      // back to it.
      expect(
        await rebakes(() => brushAllowed.value = true),
        only({SheetStratum.ink}),
      );
      expect(
        await rebakes(() => brushAllowed.value = false),
        only({SheetStratum.ink}),
      );
    });

    testWidgets('${sheet.sheet}: the ink stands down while the pen is down, '
        'and bakes again after', (tester) async {
      await mount(tester);
      brushAllowed.value = true;
      await tester.pumpAndSettle();
      StandDownReason ink() => tester
          .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
          .singleWhere((raster) => raster.debugLabel == '${sheet.sheet}-ink')
          .standDown;
      expect(ink(), StandDownReason.none, reason: 'fixture: baking');

      // The top window's middle, where the pen lands on it.
      final layer = tester.widget<SheetInkLayer>(find.byType(SheetInkLayer));
      final at =
          tester.getTopLeft(find.byType(SheetInkLayer)) +
          layer.windows.last.screenRect(layer.viewport).center;
      final pen = await tester.startGesture(at, pointer: 7);
      await tester.pump();
      await pen.moveTo(at + const Offset(6, 4));
      await tester.pump();
      expect(
        session.brushInputActive.value,
        isTrue,
        reason: 'fixture: the pen is down on the sheet\'s ink',
      );
      expect(ink(), StandDownReason.disabled);

      await pen.up();
      await tester.pumpAndSettle();
      expect(ink(), StandDownReason.none);
    });

    testWidgets('${sheet.sheet}: a drag re-records nothing, and the values '
        'that follow it stand down meanwhile', (tester) async {
      final (rebakes, _) = await mount(tester);
      expect(
        await rebakes(
          () => session.dragPreview.value = CutTrimDragPreview(
            previewDurations: {session.requireActiveCut.id: 8},
          ),
        ),
        only(const {}),
      );
      expect(
        tester
            .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
            .singleWhere((raster) => raster.debugLabel == '${sheet.sheet}-content')
            .standDown,
        // The envelope prints no length a drag moves.
        sheet.sheet == 'envelope'
            ? StandDownReason.none
            : StandDownReason.disabled,
      );
      session.dragPreview.value = null;
      await tester.pumpAndSettle();
    });

    testWidgets('${sheet.sheet}: a landed media image re-records the strata '
        'that print media images', (tester) async {
      final (rebakes, _) = await mount(tester);
      expect(
        await rebakes(images.notifyListeners),
        only(switch (sheet.sheet) {
          // The logo is a value; the cover's picture is a picture.
          'conte' => {SheetStratum.content, SheetStratum.picture},
          // The timesheet prints no media image.
          'timesheet' => const {},
          // The logo and the 도장 are values.
          _ => {SheetStratum.content},
        }),
      );
    });

    // Only the conte prints the film's own pictures.
    if (sheet.sheet == 'conte') {
      testWidgets('conte: a landed thumbnail re-records the pictures alone', (
        tester,
      ) async {
        final (rebakes, _) = await mount(tester);
        expect(
          await rebakes(thumbnails.notifyListeners),
          only({SheetStratum.picture}),
        );
      });
    }

    // The envelope's form prints its preset's words, in no language.
    if (sheet.sheet != 'envelope') {
      testWidgets('${sheet.sheet}: a new notation language re-records the '
          'form', (tester) async {
        final (rebakes, _) = await mount(tester);
        // The app's one setting, not the session's: put back what was there.
        final settings = session.languageSettings;
        final before = settings.value;
        addTearDown(() => settings.value = before);
        final rebaked = await rebakes(
          () => settings.value = before.copyWith(
            notationLanguage: before.notationLanguage == AppLanguage.ko
                ? AppLanguage.ja
                : AppLanguage.ko,
          ),
        );
        expect(rebaked[SheetStratum.form], 1);
        expect(rebaked[SheetStratum.ink], 0);
      });
    }
  }
}

Layer _storyboardLayer(String cutId, Map<int, int> divisions) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
  frames: [
    for (final start in divisions.keys)
      Frame(id: FrameId('$cutId-$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final entry in divisions.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('$cutId-${entry.key}'),
        length: entry.value,
      ),
  },
);

Cut _cut(String id, int duration, Map<int, int> divisions) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [_storyboardLayer(id, divisions)],
);

Project _project() => Project(
  id: const ProjectId('strata-project'),
  name: 'Strata',
  createdAt: DateTime.utc(2026, 9, 26),
  tracks: [
    Track(
      id: const TrackId('strata-track'),
      name: 'Video',
      cuts: [
        _cut('39', 10, {0: 5, 5: 5}),
        _cut('40', 12, {0: 12}),
      ],
    ),
  ],
);
