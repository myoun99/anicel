import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/canvas/viewport_pages_painter.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_preview_panel.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerMarkPlates, layerMarkColor;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerTypeButton;
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/export_preview_probe.dart';

/// The Cels tab (F-289): the rules that pick the rows — the kinds, one
/// label picked through the timeline's own flyout, a take picker with
/// 「최신」 added, the 레이어 filters, the paper applied — and beside them,
/// under the preview, the cut's rows as the timeline draws them: a switch on
/// every row, a block for every drawing.
void main() {
  setUp(() => AppExport.settings.value = exportSettingsWritingCelsAlone());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const key = LayerMark(process: LayerProcess.key);
  const cut1 = CutId('cut');

  // Cels are numbered by their frame NAME, so the fixture ids' digits double
  // as the cel numbers: 'f1' is cel 1.
  Frame frame(String id, {String? name}) => Frame(
    id: FrameId(id),
    duration: 1,
    strokes: const [],
    name: name ?? id.replaceAll(RegExp('[^0-9]'), ''),
  );

  Layer drawing(
    String id,
    String name,
    List<Frame> frames, {
    LayerMark mark = key,
    bool isVisible = true,
    bool onTimesheet = true,
    String? folder,
    String? attachedTo,
    Map<FrameId, FrameId> links = const {},
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: frames,
    mark: mark,
    isVisible: isVisible,
    onTimesheet: onTimesheet,
    folderId: folder == null ? null : LayerId(folder),
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: AttachedMode.synced,
    baseFrameLinks: links,
  );

  Cut plainCut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 2,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      drawing('$id-a', 'A', [frame('$id-f1', name: '1')]),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  /// CUT1: a paper row · base A (2 cels) with a synced colour row · a base B
  /// wearing LO (so the 원화 label leaves it out) · folder F holding C (off
  /// the sheet) and D — and, given [unplaced], a drawing of D's no block
  /// shows · a direction row. CUT2·CUT3 are 겸용 siblings and CUT4 stands
  /// alone — the scope grid's material. Given [camera], CUT1's camera
  /// moves as it says; given [guides], they are CUT1's.
  EditorSessionManager celsSession({
    Frame? unplaced,
    CutCamera? camera,
    CutGuides? guides,
  }) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cut1,
                name: 'CUT1',
                duration: 4,
                canvasSize: const CanvasSize(width: 8, height: 8),
                camera: camera,
                guides: guides,
                layers: [
                  drawing('paper', 'Paper', [
                    frame('p1'),
                  ], mark: const LayerMark(process: LayerProcess.paper)),
                  drawing('a', 'A', [frame('f1'), frame('f2')]),
                  drawing(
                    'a-color',
                    'A색',
                    [frame('c1'), frame('c2')],
                    attachedTo: 'a',
                    links: {
                      const FrameId('f1'): const FrameId('c1'),
                      const FrameId('f2'): const FrameId('c2'),
                    },
                  ),
                  drawing('b', 'B', [
                    frame('b1'),
                  ], mark: const LayerMark(process: LayerProcess.layout)),
                  createFolderLayer(id: const LayerId('f'), name: 'F'),
                  drawing('c', 'C', [frame('x1')], folder: 'f', onTimesheet: false),
                  if (unplaced == null)
                    drawing('d', 'D', [frame('y1')], folder: 'f')
                  else
                    Layer(
                      id: const LayerId('d'),
                      name: 'D',
                      frames: [frame('y1'), unplaced],
                      mark: key,
                      folderId: const LayerId('f'),
                      timeline: const {
                        0: TimelineExposure.drawing(FrameId('y1'), length: 1),
                      },
                    ),
                  Layer(
                    id: const LayerId('inst'),
                    name: 'Camera',
                    frames: const [],
                    kind: LayerKind.instruction,
                    instructions: {
                      0: const InstructionEvent(
                        instructionId: 'pan',
                        length: 4,
                        text: 'PAN',
                      ),
                    },
                  ),
                  createCameraLayer(cutId: cut1),
                ],
              ),
              plainCut('c2', 'CUT2'),
              plainCut('c3', 'CUT3'),
              plainCut('c4', 'CUT4'),
            ],
          ),
        ],
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'group-1',
              members: const [
                LayerLinkMember(
                  trackId: TrackId('track'),
                  cutId: CutId('c2'),
                  layerId: LayerId('c2-a'),
                ),
                LayerLinkMember(
                  trackId: TrackId('track'),
                  cutId: CutId('c3'),
                  layerId: LayerId('c3-a'),
                ),
              ],
            ),
          ],
        ),
        createdAt: DateTime.utc(2026),
      ),
    );
    return inkEveryCel(session);
  }

  /// A perspective guide on CUT1's paper — hidden where [visible] is false.
  DrawingGuide aPerspectiveGuide({bool visible = true}) => DrawingGuide(
    id: const GuideId('perspective'),
    name: 'Perspective',
    visible: visible,
    shape: PerspectiveShape(
      vanishingPoints: [VanishingPointAt(CanvasPoint(x: 6, y: 2))],
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 0, y: 2), angleDegrees: 0),
    ),
  );

  /// A symmetry guide on CUT1's paper, shown.
  DrawingGuide aSymmetryGuide() => DrawingGuide(
    id: const GuideId('symmetry'),
    name: 'Symmetry',
    shape: SymmetryShape(
      axis: GuideAxis(origin: CanvasPoint(x: 4, y: 4), angleDegrees: 90),
    ),
  );

  /// A camera that moves across CUT1: the canvas draws it a path.
  CutCamera aCameraThatMoves() => CutCamera(
    keyframes: {
      0: CameraPose(center: CanvasPoint(x: 2, y: 4)),
      3: CameraPose(center: CanvasPoint(x: 6, y: 4)),
    },
  );

  /// The window on the Cels tab.
  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    // Room for the window's least in the TEST font, whose words run wide:
    // the Cels list's rules stand as wide as their words (F-486).
    await tester.binding.setSurfaceSize(const Size(1400, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

  /// The word a list button shows — the one [Text] it draws.
  String shown(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// How many files the export writes, as the band says it.
  String celCount(WidgetTester tester) => textOf(tester, 'export-cels-count');

  Pill pill(WidgetTester tester, String key) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>(key)));

  ExportCelsCutDelta? deltaOf(EditorSessionManager session) =>
      session.repository.requireProject().exportOverrides.deltaFor(cut1);

  ExportCelRef ref(String row, String cel) =>
      (row: LayerId(row), cel: FrameId(cel));

  Future<void> standOn(WidgetTester tester, String row) =>
      tapKey(tester, 'export-cels-stand-$row');

  Future<void> pressBlock(WidgetTester tester, String row, String cel) =>
      tapKey(tester, 'export-cels-block-$row-$cel');

  testWidgets('the list is the cut\'s STACKS as the timeline draws them, each '
      'led by its switch over its files; the paper, the attach rows, the '
      'folders and the rows of a kind that is off are not in it', (
    tester,
  ) async {
    final session = celsSession();
    await pumpCels(tester, session);

    final cut = session.cutById(cut1)!;
    expect(
      tester.celsBoardRowIds,
      [
        for (final layer in horizontalLayerDisplayOrder(cut.layers))
          if (const {'a', 'b', 'c', 'd'}.contains(layer.id.value))
            layer.id.value,
      ],
      reason: 'the paper is applied, the colour row is in A\'s files, a '
          'folder is no file, and the direction kind is off',
    );
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    // B wears LO: the 원화 label leaves its stack nothing to hold — a row all
    // the same, off (유저 2026-10-09: 「블록 없어도 그냥 행 보이게」).
    expect(tester.celsBoardSwitchState('b'), BooleanMix.off);

    // One block a drawing: A's two, bright — and none on B.
    expect(tester.celsBoardBlocksOf('a'), [('1', true), ('2', true)]);
    expect(tester.celsBoardBlocksOf('b'), isEmpty);
    expect(tester.celsBoardBlocksOf('c'), [('1', true)]);

    // A ×2 + C + D; the paper row is applied, not counted.
    expect(celCount(tester), AppText.strings.exWrittenCount(4));
    // The kinds' defaults: 셀 and 미술. The filters': 기준 and 부속 on, 시트
    // off. And the label reads its own name — nothing has left its rule.
    expect(pill(tester, 'export-cels-kind-cel').selected, isTrue);
    expect(pill(tester, 'export-cels-kind-art').selected, isTrue);
    expect(pill(tester, 'export-cels-kind-conte').selected, isFalse);
    expect(pill(tester, 'export-cels-kind-direction').selected, isFalse);
    expect(pill(tester, 'export-cels-select-base').selected, isTrue);
    expect(pill(tester, 'export-cels-select-attach').selected, isTrue);
    expect(pill(tester, 'export-cels-select-sheet').selected, isFalse);
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
    expect(
      find.byKey(const ValueKey<String>('export-cels-select-custom')),
      findsNothing,
      reason: '🪦the 커스텀 pill — the label says it now',
    );
  });

  testWidgets('🪦the two lists it was are gone: no bundle list beside the '
      'preview, no 「셀」 module in the settings column', (tester) async {
    await pumpCels(tester, celsSession());
    for (final key in [
      'export-cels-bundle-a',
      'export-cels-bundle-dot-a',
      'export-cels-bundle-count',
      'export-cels-dot-a',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExportAccordion && widget.title == AppText.strings.exCels,
      ),
      findsNothing,
    );
    // The board stands under the preview.
    expect(
      tester.getTopLeft(find.byType(ExportCelsBoard)).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ExportPreviewPanel)).dy,
      ),
    );
  });

  testWidgets('switching on a row the filters left nothing to hold puts its '
      'base back in: the plan grows, the label reads 「커스텀」, and a filter '
      'pill drops the exception', (tester) async {
    // 유저 2026-10-06: 「색라벨 필터 LO일때에서 작감용지 레이어 추가하면
    // 색라벨필터 LO인채인데, 그게아니라 커스텀인상태로 필터 바꾸고싶어」 ·
    // export-four-tabs ⓑ (2026-10-09): 「가」 — the base line, switched on.
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-switch-b');
    expect(deltaOf(session)?.layerOverrides[const LayerId('b')], isTrue);
    expect(celCount(tester), AppText.strings.exWrittenCount(5));
    expect(tester.celsBoardBlocksOf('b'), [('1', true)]);
    expect(
      shown(tester, 'export-cels-label-picker'),
      AppText.strings.exSelCustom,
    );

    // 시트 on: C is off the sheet and goes; the hand exception goes with the
    // rule change.
    await tapKey(tester, 'export-cels-select-sheet');
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
    expect(pill(tester, 'export-cels-select-sheet').selected, isTrue);
    expect(celCount(tester), AppText.strings.exWrittenCount(3));
    expect(
      tester.celsBoardRowIds,
      contains('c'),
      reason: 'a row a FILTER turns off stays in the list, off (유저: '
          '「필터로 off되도 사라진다거나 하지않음」)',
    );
    expect(tester.celsBoardSwitchState('c'), BooleanMix.off);
  });

  testWidgets('🗣️picking a label — the very one it left — puts the rows back '
      'on that label\'s rule; a take does too; the drawings the hand turned '
      'off stay off (F-298, 유저 2026-10-05: 「색 라벨 선택하면 사실상 초기화나 '
      '마찬가지인데 커스텀 설정한게 안풀림」)', (tester) async {
    final session = celsSession();
    final state = await pumpCels(tester, session);

    Future<void> pickTheKeyLabelAgain() async {
      await tapKey(tester, 'export-cels-label-picker');
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey<String>('layer-mark-stage-key')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('layer-mark-option-key')),
      );
      await tester.pumpAndSettle();
      await mouse.removePointer();
    }

    await tapKey(tester, 'export-cels-switch-b');
    await pressBlock(tester, 'd', 'y1');
    expect(
      shown(tester, 'export-cels-label-picker'),
      AppText.strings.exSelCustom,
    );
    expect(deltaOf(session)?.skippedCels, {ref('d', 'y1')});

    await pickTheKeyLabelAgain();
    expect(state.debugSpecs.cels.label, key);
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
    final label = find.byKey(
      const ValueKey<String>('export-cels-label-picker'),
    );
    expect(
      tester
          .widget<Text>(find.descendant(of: label, matching: find.byType(Text)))
          .style
          ?.color,
      timelineTextOnColor(layerMarkColor(state.debugSpecs.cels.label)),
      reason: 'the word on its colour',
    );
    expect(
      deltaOf(session)?.skippedCels,
      {ref('d', 'y1')},
      reason: 'a drawing turned off is not a row that left the rule',
    );

    await tapKey(tester, 'export-cels-switch-b');
    expect(
      shown(tester, 'export-cels-label-picker'),
      AppText.strings.exSelCustom,
    );
    await tapKey(tester, 'export-cels-take-picker');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-take-option-latest')),
    );
    await tester.pumpAndSettle();
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
  });

  testWidgets('a drawing turned off alone does not make the label read '
      '「커스텀」 — that is a row leaving its rule', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    await pressBlock(tester, 'd', 'y1');
    expect(deltaOf(session)?.skippedCels, {ref('d', 'y1')});
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
  });

  testWidgets('a kind turned off and on again keeps what the hand did to its '
      'rows', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-switch-b');
    await tapKey(tester, 'export-cels-kind-cel');
    expect(
      tester.celsBoardRowIds,
      isEmpty,
      reason: 'the cel rows left the list with their kind',
    );
    expect(celCount(tester), AppText.strings.exWrittenCount(0));
    expect(deltaOf(session)?.layerOverrides[const LayerId('b')], isTrue);

    await tapKey(tester, 'export-cels-kind-cel');
    expect(tester.celsBoardSwitchState('b'), BooleanMix.on);
    expect(celCount(tester), AppText.strings.exWrittenCount(5));
  });

  testWidgets('the 레이어 pills are filters that STACK: 기준 off leaves the '
      'riders on the base\'s axis, 부속 off leaves the bases alone, both off '
      'leaves nothing', (tester) async {
    // 유저 2026-09-09: 「기준/부속 고르면 기준레이어+부속레이어까지 묶고, 부속만
    // 되있으면 기준레이어가 아닌 부속레이어만 묶고」.
    // 🚨Each press is answered AT ONCE — the list, the attach column and the
    // count after the one frame the press draws (유저 2026-10-09: 「필터나
    // 이런거 바꾸면 바로 적용안되있고 리빌드하는 행동하면 적용되있다거나
    // 하는문제 매번있으니까 잘 확인하고」): [tapKey] pumps once.
    final state = await pumpCels(tester, celsSession());
    await standOn(tester, 'a');
    expect(tester.celsStackLines, [('a-color', true), ('a', true)]);

    // 부속 off: the filter leaves the colour row out — so the attach column
    // does not offer it (export-four-tabs ⓐ 「필터전부」).
    await tapKey(tester, 'export-cels-select-attach');
    expect(state.debugSpecs.cels.attach, isFalse);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(tester.celsStackLines, [('a', true)]);
    expect(celCount(tester), AppText.strings.exWrittenCount(4));

    await tapKey(tester, 'export-cels-select-base');
    expect(state.debugSpecs.cels.base, isFalse);
    expect(celCount(tester), AppText.strings.exWrittenCount(0));
    expect(tester.celsBoardSwitchState('a'), BooleanMix.off);
    expect(
      tester.celsStackLines,
      [('a', false)],
      reason: 'the base is offered whatever the filters say',
    );

    // 부속 alone: the colour row rides base A's axis — two files named by
    // A, standing on A's row, which says its files: on.
    await tapKey(tester, 'export-cels-select-attach');
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(tester.celsStackLines, [('a-color', true), ('a', false)]);
    expect(celCount(tester), AppText.strings.exWrittenCount(2));
    expect(tester.celsBoardBlocksOf('a'), [('1', true), ('2', true)]);
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
  });

  testWidgets('디렉션 is a KIND: off, its row is not in the list at all; its '
      'pill puts the row there, on, with a block for the drawing under its '
      'block', (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(tester.celsBoardRowIds, isNot(contains('inst')));

    await tapKey(tester, 'export-cels-kind-direction');
    expect(state.debugSpecs.cels.kinds, contains(ExportCelKind.direction));
    expect(pill(tester, 'export-cels-kind-direction').selected, isTrue);
    expect(tester.celsBoardRowIds, contains('inst'));
    expect(tester.celsBoardSwitchState('inst'), BooleanMix.on);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(celCount(tester), AppText.strings.exWrittenCount(5));
    expect(
      tester.celsBoardBlocksOf('inst'),
      [('PAN', true)],
      reason: 'named by what its block says',
    );
  });

  testWidgets('open alpha reads as the checkerboard under the picture; an '
      'opaque format has none — on every tab\'s preview', (tester) async {
    // 유저 2026-09-09: 「png rgba같은것처럼 배경에 아무것도 없다면 … 투명이라는
    // 의미의 체크무늬 … 이미있으면 있던거 쓰고. 다른 출력항목도 같은거 적용」.
    // The Image tab: its composite resolves even for an ink-less fixture
    // (a cel with no ink renders nothing on the Cels tab), and its default
    // PNG is RGBA.
    await pumpCels(tester, celsSession());
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
    await tester.pump();
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);
    ViewportPageGround ground() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(
                        const ValueKey<String>('export-preview-page'),
                      ),
                    )
                    .painter!
                as ViewportPagesPainter)
            .ground;
    expect(
      ground(),
      ViewportPageGround.checker,
      reason: 'the canvas\'s own alpha checker, not a second one',
    );

    await tapKey(tester, 'export-format-channels-rgb');
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);
    expect(ground(), ViewportPageGround.none);
  });

  test('the preset rail reads the filters that are on', () {
    final strings = AppText.strings;
    expect(
      exportCelFilterSummary(const CelsExportSpec()),
      '${strings.exSelBase} · ${strings.exSelAttach}',
    );
    expect(
      exportCelFilterSummary(const CelsExportSpec(base: false, sheetOnly: true)),
      '${strings.exSelAttach} · ${strings.exSelSheet}',
    );
    expect(
      exportCelFilterSummary(const CelsExportSpec(base: false, attach: false)),
      '—',
    );
  });

  // export-four-tabs ③ (유저 2026-10-09): a row's switch is its FILES — 「한
  // 장만 있을때 그 블록 빈블록만들면 해당 행 체크해제랑 동일한 로직」. ↩️It
  // was a row exception, and a folder's switched the rows under it.
  testWidgets('🚨a row\'s switch turns every file of its row: off, the row '
      'dims and stays — stood on, the preview turns through its files; on, '
      'they are all back — and no label leaves its rule', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-switch-a');
    expect(deltaOf(session)?.skippedCels, {ref('a', 'f1'), ref('a', 'f2')});
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.off);
    expect(tester.celsBoardBlocksOf('a'), [('1', false), ('2', false)]);
    expect(celCount(tester), AppText.strings.exWrittenCount(2));
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));
    await standOn(tester, 'a');
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');

    // One file back: mixed — and a press on a mixed switch turns all on.
    await pressBlock(tester, 'a', 'f1');
    expect(tester.celsBoardSwitchState('a'), BooleanMix.mixed);
    await tapKey(tester, 'export-cels-switch-a');
    expect(deltaOf(session), isNull);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(celCount(tester), AppText.strings.exWrittenCount(4));

    // A row with one file: its block emptied IS the row switched off.
    await pressBlock(tester, 'c', 'x1');
    expect(tester.celsBoardSwitchState('c'), BooleanMix.off);
  });

  // export-four-tabs ④ (유저 2026-10-09): the attach column — 「그 파일에
  // 무엇이 담기나」.
  testWidgets('🚨the attach column is the stood row\'s stack, each line '
      'switched as the rules and the hand say; a line switched by hand is a '
      'row exception, and the list, the count and the preview follow AT '
      'ONCE', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    await standOn(tester, 'a');
    expect(tester.celsStackLines, [('a-color', true), ('a', true)]);
    // 🗣️F-395: the column says what it is, and every line is led as the
    // timeline leads the row — its label, take and kind — after a slot of
    // its own that marks the base.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('export-cels-stack-head')),
        matching: find.text(AppText.strings.exCelsLayersOut),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('export-cels-stack-base-a')),
        matching: find.text(AppText.strings.exSelBase),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-stack-base-a-color')),
      findsNothing,
    );
    for (final id in ['a-color', 'a']) {
      final line = find.byKey(ValueKey<String>('export-cels-stack-line-$id'));
      expect(
        find.descendant(of: line, matching: find.byType(LayerMarkPlates)),
        findsOneWidget,
        reason: '$id: its label and take',
      );
      expect(
        find.descendant(of: line, matching: find.byType(LayerTypeButton)),
        findsOneWidget,
        reason: '$id: its kind',
      );
    }
    final before = tester.exportPreviewDocument!.look;
    await tester.settleExportPreview();
    final pictureBefore = tester.exportPreviewImage;
    expect(pictureBefore, isNotNull, reason: '⛔전제: a picture is up');

    await tester.pressCelsStackSwitch('a-color');
    expect(deltaOf(session)?.layerOverrides, {const LayerId('a-color'): false});
    expect(tester.celsStackLines, [('a-color', false), ('a', true)]);
    expect(
      shown(tester, 'export-cels-label-picker'),
      AppText.strings.exSelCustom,
    );
    expect(celCount(tester), AppText.strings.exWrittenCount(4));
    expect(
      tester.exportPreviewDocument!.look,
      isNot(before),
      reason: 'the file A1 holds no colour now: the preview draws it again',
    );
    // 🚨…with no other press: the picture lands for the look the press made
    // (유저 2026-10-09: 「리빌드하는 행동하면 적용되있다거나 하는문제」).
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);
    expect(tester.exportPreviewImage, isNot(same(pictureBefore)));
  });

  testWidgets('🚨「어태치만」: the base switched off in the column, its colour '
      'row on — the row keeps its files, numbered by the base and holding '
      'the colour alone', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    await standOn(tester, 'a');

    await tester.pressCelsStackSwitch('a');
    expect(deltaOf(session)?.layerOverrides, {const LayerId('a'): false});
    expect(tester.celsStackLines, [('a-color', true), ('a', false)]);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(tester.celsBoardBlocksOf('a'), [('1', true), ('2', true)]);
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
  });

  testWidgets('🚨every line switched off: the row stays, off with no file, '
      'and is still stood on — its switch puts the base back', (
    tester,
  ) async {
    // 유저 2026-10-09: 「마지막 어태치줄 체크해제못하는게 신경쓰이고 그냥
    // 말없이 출력행에서 안보이면 별로라. 보이더라도 다른거처럼 이름 흐리게」.
    final session = celsSession();
    await pumpCels(tester, session);
    await standOn(tester, 'a');

    await tester.pressCelsStackSwitch('a-color');
    await tester.pressCelsStackSwitch('a');
    expect(tester.celsStackLines, [('a-color', false), ('a', false)]);
    expect(tester.celsBoardRowIds, contains('a'));
    expect(tester.celsBoardSwitchState('a'), BooleanMix.off);
    expect(tester.celsBoardBlocksOf('a'), isEmpty);
    expect('${tester.celsBoard.standing}', 'a');
    expect(celCount(tester), AppText.strings.exWrittenCount(2));

    await tapKey(tester, 'export-cels-switch-a');
    expect(deltaOf(session)?.layerOverrides, {const LayerId('a-color'): false});
    expect(tester.celsStackLines, [('a-color', false), ('a', true)]);
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(celCount(tester), AppText.strings.exWrittenCount(4));
  });

  testWidgets('🗣️a block is the drawing\'s switch: turned off it stays in '
      'the list, hollow, and out of the count — and 초기화 puts the cut back '
      'on its rules', (tester) async {
    // 유저 2026-10-06: 「셀의 프레임버튼 누르면 내보내기 적용/미적용」.
    final session = celsSession();
    await pumpCels(tester, session);

    await pressBlock(tester, 'a', 'f1');
    expect(deltaOf(session)?.skippedCels, {ref('a', 'f1')});
    expect(celCount(tester), AppText.strings.exWrittenCount(3));
    expect(tester.celsBoardBlocksOf('a'), [('1', false), ('2', true)]);
    // The row says its files: some are off (export-four-tabs ③).
    expect(tester.celsBoardSwitchState('a'), BooleanMix.mixed);

    await pressBlock(tester, 'a', 'f1');
    expect(deltaOf(session), isNull);
    expect(tester.celsBoardBlocksOf('a'), [('1', true), ('2', true)]);

    await pressBlock(tester, 'a', 'f2');
    await tapKey(tester, 'export-cels-switch-b');
    await tapKey(tester, 'export-cels-reset');
    expect(deltaOf(session), isNull);
    expect(celCount(tester), AppText.strings.exWrittenCount(4));
    expect(tester.celsBoardSwitchState('b'), BooleanMix.off);
  });

  testWidgets('🗣️a drawing that cannot go out says why when it is pressed, '
      'and stays as it was (유저 2026-10-06: 「나갈 수 없는 그림은 '
      '작동하려하면 이유 띄우자」)', (tester) async {
    // D's second drawing is on no block of the timeline: no cut places it.
    final session = celsSession(
      unplaced: Frame(
        id: const FrameId('y2'),
        duration: 1,
        strokes: const [],
        name: '2',
      ),
    );
    await pumpCels(tester, session);

    await pressBlock(tester, 'd', 'y2');
    expect(find.text(AppText.strings.noticeExportNotPlaced), findsOneWidget);
    expect(deltaOf(session), isNull, reason: 'a refusal writes nothing');
    expect(tester.celsBoardBlocksOf('d'), [('1', true), ('2', false)]);

    // The notice goes by itself.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(AppText.strings.noticeExportNotPlaced), findsNothing);
  });

  testWidgets('the row stood on is what the preview turns through — the '
      'name stands on it, ◀ ▶ step its drawings', (tester) async {
    await pumpCels(tester, celsSession());

    await standOn(tester, 'c');
    expect(tester.exportPreviewLine, 'C1.png · 1 / 1');
    await standOn(tester, 'a');
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
    expect(tester.celsBoardBlockOf('a', 'f1').shown, isTrue);

    await tapKey(tester, 'export-cels-next');
    expect(tester.exportPreviewLine, 'A2.png · 2 / 2');
    expect(tester.celsBoardBlockOf('a', 'f2').shown, isTrue);
    await tapKey(tester, 'export-cels-next');
    expect(
      tester.exportPreviewLine,
      'A2.png · 2 / 2',
      reason: 'there is nowhere further to step',
    );
    await tapKey(tester, 'export-cels-prev');
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
  });

  testWidgets('the drawing shown is turned off: the nearest one left is '
      'shown — and on a row that holds no file, nothing is', (tester) async {
    await pumpCels(tester, celsSession());

    await standOn(tester, 'a');
    await pressBlock(tester, 'a', 'f1');
    expect(tester.exportPreviewLine, 'A2.png · 1 / 1');

    // B's stack holds no picture: stood on, the preview has nothing to show
    // — its attach column is where a picture is put back.
    await standOn(tester, 'b');
    expect('${tester.celsBoard.standing}', 'b');
    expect(tester.exportPreviewDocument, isNull);
    expect(tester.celsStackLines, [('b', false)]);
  });

  testWidgets('🗣️「이 그림에 디렉션 적용」: a pill a direction drawing lays '
      'it over the drawing shown — whether or not the direction kind is '
      'written — and the block wears a D', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    final direction = session
        .cutById(cut1)!
        .layers
        .singleWhere((layer) => layer.kind == LayerKind.instruction);
    final drawn = direction.frames.single.id.value;
    final pillKey = 'export-cels-direction-inst-$drawn';

    expect(
      pill(tester, 'export-cels-kind-direction').selected,
      isFalse,
      reason: '유저: 「디렉션 on이든 off든 관계없이 떠있도록」',
    );
    expect(pill(tester, pillKey).label, 'PAN');
    expect(pill(tester, pillKey).selected, isFalse);

    await standOn(tester, 'a');
    await tapKey(tester, pillKey);
    expect(deltaOf(session)?.directionOver, {
      (cel: ref('a', 'f1'), direction: ref('inst', drawn)),
    });
    expect(pill(tester, pillKey).selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('export-cels-block-d-a-f1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-block-d-a-f2')),
      findsNothing,
      reason: 'laid over ONE drawing, not its row',
    );
    expect(shown(tester, 'export-cels-label-picker'), exportCelLabelText(key));

    // The other drawing: the pill reads that drawing's own answer.
    await tapKey(tester, 'export-cels-next');
    expect(pill(tester, pillKey).selected, isFalse);

    // 초기화 is of the rules: what is laid over a drawing stays.
    await tapKey(tester, 'export-cels-switch-b');
    await tapKey(tester, 'export-cels-reset');
    expect(deltaOf(session)?.directionOver, hasLength(1));

    await tapKey(tester, 'export-cels-prev');
    await tapKey(tester, pillKey);
    expect(deltaOf(session), isNull);
  });

  testWidgets('CAM lays the camera\'s work over the drawing shown, a drawing '
      'at a time, and 초기화 leaves it — I-89-Q18', (tester) async {
    final session = celsSession(camera: aCameraThatMoves());
    await pumpCels(tester, session);
    const cam = 'export-cels-cam';

    await standOn(tester, 'a');
    expect(pill(tester, cam).selected, isFalse);
    await tapKey(tester, cam);
    expect(deltaOf(session)?.cameraOver, {ref('a', 'f1')});
    expect(pill(tester, cam).selected, isTrue);

    // The other drawing reads its own answer.
    await tapKey(tester, 'export-cels-next');
    expect(pill(tester, cam).selected, isFalse);

    // 초기화 is of the rules: what is laid over a drawing stays.
    await tapKey(tester, 'export-cels-switch-b');
    await tapKey(tester, 'export-cels-reset');
    expect(deltaOf(session)?.cameraOver, {ref('a', 'f1')});

    await tapKey(tester, 'export-cels-prev');
    await tapKey(tester, cam);
    expect(deltaOf(session), isNull);
  });

  testWidgets('CAM has nothing to lay where the camera moves nothing — the '
      'canvas draws it no path — and keeps its place', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    await standOn(tester, 'a');
    expect(pill(tester, 'export-cels-cam').onTap, isNull);
    await tapKey(tester, 'export-cels-cam');
    expect(deltaOf(session), isNull);
  });

  testWidgets('「가이드」 lays the cut\'s guides over the drawing shown, a '
      'drawing at a time, and 초기화 leaves it — I-105', (tester) async {
    final session = celsSession(
      guides: CutGuides(guides: [aPerspectiveGuide()]),
    );
    await pumpCels(tester, session);
    const guides = 'export-cels-guides';

    await standOn(tester, 'a');
    expect(pill(tester, guides).selected, isFalse);
    await tapKey(tester, guides);
    expect(deltaOf(session)?.guidesOver, {ref('a', 'f1')});
    expect(pill(tester, guides).selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('export-cels-block-g-a-f1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-block-g-a-f2')),
      findsNothing,
      reason: 'laid over ONE drawing, not its row',
    );

    // The other drawing reads its own answer.
    await tapKey(tester, 'export-cels-next');
    expect(pill(tester, guides).selected, isFalse);

    // 초기화 is of the rules: what is laid over a drawing stays.
    await tapKey(tester, 'export-cels-switch-b');
    await tapKey(tester, 'export-cels-reset');
    expect(deltaOf(session)?.guidesOver, {ref('a', 'f1')});

    await tapKey(tester, 'export-cels-prev');
    await tapKey(tester, guides);
    expect(deltaOf(session), isNull);
  });

  testWidgets('「가이드」 has nothing to lay where the cut shows no '
      'perspective guide — a hidden one, a symmetry one — and keeps its '
      'place (I-105-Q1)', (tester) async {
    final session = celsSession(
      guides: CutGuides(
        guides: [aPerspectiveGuide(visible: false), aSymmetryGuide()],
      ),
    );
    await pumpCels(tester, session);
    await standOn(tester, 'a');
    expect(pill(tester, 'export-cels-guides').onTap, isNull);
    await tapKey(tester, 'export-cels-guides');
    expect(deltaOf(session), isNull);
  });

  testWidgets('nothing is laid over a direction row\'s OWN drawing: stood '
      'on it the pills keep their place and take no press', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    final direction = session
        .cutById(cut1)!
        .layers
        .singleWhere((layer) => layer.kind == LayerKind.instruction);
    final pillKey =
        'export-cels-direction-inst-${direction.frames.single.id.value}';

    await tapKey(tester, 'export-cels-kind-direction');
    await standOn(tester, 'inst');
    expect('${tester.celsBoard.standing}', contains('inst'));
    expect(pill(tester, pillKey).onTap, isNull);
    await tapKey(tester, pillKey);
    expect(deltaOf(session), isNull);

    // On a drawing of another row the same pill is live.
    await standOn(tester, 'a');
    expect(pill(tester, pillKey).onTap, isNotNull);
  });

  testWidgets('초기화 is dead while the cut is on its rules, and live once a '
      'row or a drawing has left them', (tester) async {
    await pumpCels(tester, celsSession());
    bool live() => tester
        .widget<ExportResetChip>(
          find.byKey(const ValueKey<String>('export-cels-reset')),
        )
        .enabled;
    expect(live(), isFalse);

    await pressBlock(tester, 'a', 'f1');
    expect(live(), isTrue, reason: 'a drawing was turned off');
    await tapKey(tester, 'export-cels-reset');
    expect(live(), isFalse);

    await tapKey(tester, 'export-cels-switch-b');
    expect(live(), isTrue, reason: 'a row answers by hand');
    await tapKey(tester, 'export-cels-reset');
    expect(live(), isFalse);
  });

  testWidgets('a drawing turned off hands the preview to the nearest one '
      'left — and that one is STOOD ON: turned back on, the first does not '
      'take the preview back (유저 2026-10-06: 「서있는 상태나 마찬가지지」)', (
    tester,
  ) async {
    await pumpCels(tester, celsSession());
    await standOn(tester, 'a');
    String shown() => '${tester.celsBoard.shown}';
    expect(shown(), contains('f1'));

    await pressBlock(tester, 'a', 'f1');
    expect(shown(), contains('f2'));

    await pressBlock(tester, 'a', 'f1');
    expect(
      shown(),
      contains('f2'),
      reason: 'the list stood on the second drawing when the first went',
    );
  });

  testWidgets('the first file the window names is the first one WRITTEN — a '
      'drawing turned off is not it', (tester) async {
    await pumpCels(tester, celsSession());
    expect(tester.exportFirstFileName, 'A1.png');

    await pressBlock(tester, 'a', 'f1');
    expect(tester.exportFirstFileName, 'A2.png');

    await pressBlock(tester, 'a', 'f2');
    await pressBlock(tester, 'c', 'x1');
    await pressBlock(tester, 'd', 'y1');
    expect(tester.exportFirstFileName, AppText.strings.exNoCels);
  });

  testWidgets('레이어: 기준 and 어태치 share a strip, and 시트만 stands in a '
      'strip of its own', (tester) async {
    await pumpCels(tester, celsSession());
    Finder pillOf(String key) =>
        find.byKey(ValueKey<String>('export-cels-select-$key'));
    PillStrip stripOf(String key) => tester.widget<PillStrip>(
      find.ancestor(of: pillOf(key), matching: find.byType(PillStrip)),
    );
    List<String> keysOf(PillStrip strip) => [
      for (final item in strip.items) item.keyValue,
    ];
    expect(keysOf(stripOf('base')), [
      'export-cels-select-base',
      'export-cels-select-attach',
    ]);
    expect(keysOf(stripOf('sheet')), ['export-cels-select-sheet']);
  });

  testWidgets('each kind\'s pill, and its prefix field, reads that kind\'s '
      'name', (tester) async {
    await pumpCels(tester, celsSession());
    final strings = AppText.strings;
    final names = {
      ExportCelKind.cel: strings.exCels,
      // The conte ROW's word (콘티) — not the sheet panel's (콘티 용지).
      ExportCelKind.conte: strings.tlKindStoryboard,
      ExportCelKind.art: strings.exArtLabel,
      ExportCelKind.direction: strings.exSelDirection,
      // A document wears its panel's name.
      ExportCelKind.timesheet: strings.panelTimesheet,
      ExportCelKind.envelope: strings.panelEnvelope,
    };
    expect(names.keys, ExportCelKind.values, reason: 'every kind is named');
    expect(names.values.toSet(), hasLength(names.length));
    for (final MapEntry(key: kind, value: name) in names.entries) {
      expect(
        pill(tester, 'export-cels-kind-${kind.jsonValue}').label,
        name,
        reason: '$kind',
      );
      expect(exportCelKindLabel(kind), name, reason: '$kind');
    }
  });

  testWidgets('the label picker is the timeline\'s flyout: 「라벨 없음」 empties '
      'a KEY cut, a stage picked through its hover child relabels the export',
      (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(
      shown(tester, 'export-cels-label-picker'),
      exportCelLabelText(key),
    );

    await tapKey(tester, 'export-cels-label-picker');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('layer-mark-option-none')));
    await tester.pumpAndSettle();
    expect(state.debugSpecs.cels.label, LayerMark.none);
    expect(
      shown(tester, 'export-cels-label-picker'),
      AppText.strings.tlLayerMarkNone,
    );
    expect(celCount(tester), AppText.strings.exWrittenCount(0));

    await tapKey(tester, 'export-cels-label-picker');
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('layer-mark-stage-layout')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-mark-option-layout')),
    );
    await tester.pumpAndSettle();
    const layout = LayerMark(process: LayerProcess.layout);
    expect(state.debugSpecs.cels.label, layout);
    expect(
      shown(tester, 'export-cels-label-picker'),
      exportCelLabelText(layout),
    );
  });

  testWidgets('the take picker is the timeline\'s flyout plus 「최신」',
      (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(
      shown(tester, 'export-cels-take-picker'),
      AppText.strings.exTakeLatest,
    );

    await tapKey(tester, 'export-cels-take-picker');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('layer-take-option-latest')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('layer-take-option-2')));
    await tester.pumpAndSettle();
    expect(state.debugSpecs.cels.take, 2);
    expect(
      shown(tester, 'export-cels-take-picker'),
      AppText.strings.tlLayerTakeNumber(2),
    );
    // Nothing in the cut is a second take.
    expect(celCount(tester), AppText.strings.exWrittenCount(0));

    await tapKey(tester, 'export-cels-take-picker');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-take-option-latest')),
    );
    await tester.pumpAndSettle();
    expect(state.debugSpecs.cels.take, isNull);
    expect(celCount(tester), AppText.strings.exWrittenCount(4));
  });

  testWidgets('🚨the label and take pickers ARE the app\'s list button — no '
      '▼ (law-패널, 유저 2026-10-18), the word in even padding, the label '
      'on its colour', (tester) async {
    final state = await pumpCels(tester, celsSession());
    for (final key in const [
      'export-cels-label-picker',
      'export-cels-take-picker',
    ]) {
      final picker = find.byKey(ValueKey<String>(key));
      expect(tester.widget(picker), isA<PanelFlyoutButton>(), reason: key);
      expect(
        find.descendant(of: picker, matching: find.byType(Icon)),
        findsNothing,
        reason: key,
      );
      final chip = tester.getRect(picker);
      final word = tester.getRect(
        find.descendant(of: picker, matching: find.byType(Text)),
      );
      expect(word.left - chip.left, chip.right - word.right, reason: key);
    }
    expect(
      tester
          .widget<PanelFlyoutButton>(
            find.byKey(const ValueKey<String>('export-cels-label-picker')),
          )
          .fill,
      layerMarkColor(state.debugSpecs.cels.label),
    );
  });

  testWidgets('내보낼 종류 and 적용 are pills that write the spec', (
    tester,
  ) async {
    final state = await pumpCels(tester, celsSession());
    expect(pill(tester, 'export-cels-apply-paper').selected, isTrue);

    await tapKey(tester, 'export-cels-apply-paper');
    expect(state.debugSpecs.cels.applyPaper, isFalse);
    expect(pill(tester, 'export-cels-apply-paper').selected, isFalse);

    await tapKey(tester, 'export-cels-kind-art');
    expect(state.debugSpecs.cels.kinds, {ExportCelKind.cel});
    expect(pill(tester, 'export-cels-kind-art').selected, isFalse);
  });

  testWidgets('🗣️접두사: a text field a kind in the naming module — what is '
      'typed leads that kind\'s files, an empty field is none, and the '
      'module\'s reset puts each kind\'s own back', (tester) async {
    // 유저 2026-10-06: 「접두사는 각각 _로하거나 커스텀으로 텍스트 지정가능 …
    // 기본값은 셀:없음, 미술:_, 디렉션:_」 · 「콘티레이어는 다만 기본값
    // 없음으로」.
    final state = await pumpCels(tester, celsSession());
    await standOn(tester, 'a');
    final naming = find.byWidgetPredicate(
      (widget) =>
          widget is ExportAccordion && widget.title == AppText.strings.exNaming,
    );
    await tester.ensureVisible(naming);
    await tester.tap(
      find.descendant(of: naming, matching: find.byType(InkWell)).first,
    );
    await tester.pump();

    Finder field(ExportCelKind kind) =>
        find.byKey(ValueKey<String>('export-cel-prefix-${kind.jsonValue}'));
    String typedIn(ExportCelKind kind) =>
        tester.widget<TextField>(field(kind)).controller!.text;
    expect(
      {for (final kind in ExportCelKind.values) kind: typedIn(kind)},
      {
        ExportCelKind.cel: '',
        ExportCelKind.conte: '',
        ExportCelKind.art: '_',
        ExportCelKind.direction: '_',
        ExportCelKind.timesheet: '_',
        ExportCelKind.envelope: '_',
      },
    );

    await tester.enterText(field(ExportCelKind.cel), 'k_');
    await tester.pump();
    expect(state.debugSpecs.cels.naming.prefixOf(ExportCelKind.cel), 'k_');
    expect(tester.exportPreviewLine, 'k_A1.png · 1 / 2');

    await tester.enterText(field(ExportCelKind.art), '');
    await tester.pump();
    expect(state.debugSpecs.cels.naming.prefixOf(ExportCelKind.art), '');

    // The field typed in last pulled the column to itself.
    final reset = find.descendant(
      of: naming,
      matching: find.text(AppText.strings.commonReset),
    );
    await tester.ensureVisible(reset);
    await tester.pump();
    await tester.tap(reset);
    await tester.pump();
    expect(state.debugSpecs.cels.naming, const ExportCelNaming());
    expect(typedIn(ExportCelKind.cel), '');
    expect(typedIn(ExportCelKind.art), '_');
    expect(tester.exportPreviewLine, 'A1.png · 1 / 2');
  });

  testWidgets('the project-scope grid shows a 겸용 pair as ONE cell and '
      'excludes both cuts at once', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    // The Scope accordion sits collapsed by default — open it.
    await tester.ensureVisible(find.textContaining(AppText.strings.exScope));
    await tester.tap(find.textContaining(AppText.strings.exScope));
    await tester.pump();
    await tapKey(tester, 'export-scope-project');

    expect(find.text('CUT2-CUT3'), findsOneWidget);
    expect(find.text('3 / 3 cuts'), findsOneWidget);
    await tapKey(tester, 'export-cut-cell-2');
    final overrides = session.repository.requireProject().exportOverrides;
    expect(overrides.cutIncluded(const CutId('c2')), isFalse);
    expect(overrides.cutIncluded(const CutId('c3')), isFalse);
    expect(overrides.cutIncluded(const CutId('c4')), isTrue);
    expect(find.text('2 / 3 cuts'), findsOneWidget);
  });
}
