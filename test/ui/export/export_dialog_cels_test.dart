import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/canvas/paper_background.dart'
    show AlphaCheckerboardPainter;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_layer_row.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// The Cels tab, v3 (유저 2026-09-09): one label picked through the
/// timeline's own flyout, a take picker with 「최신」 added, 적용/추가 pills,
/// the 선택 presets beside 「커스텀」, the cut's stack as the timeline draws it
/// with a dot on every row, and the output cels listed beside the preview
/// with a dot of their own.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
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
  /// the sheet) and D · a direction row. CUT2·CUT3 are 겸용 siblings and
  /// CUT4 stands alone — the scope grid's material.
  EditorSessionManager celsSession() {
    return EditorSessionManager(
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
                  drawing('d', 'D', [frame('y1')], folder: 'f'),
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
  }

  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
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

  String bundleCount(WidgetTester tester) =>
      textOf(tester, 'export-cels-bundle-count');

  ExportIncludeDot dot(WidgetTester tester, String key) =>
      tester.widget<ExportIncludeDot>(find.byKey(ValueKey<String>(key)));

  ExportPill pill(WidgetTester tester, String key) =>
      tester.widget<ExportPill>(find.byKey(ValueKey<String>(key)));

  ExportCelsCutDelta? deltaOf(EditorSessionManager session) =>
      session.repository.requireProject().exportOverrides.deltaFor(cut1);

  testWidgets('the list is the cut\'s stack, each row led by its dot — the '
      'rule\'s picks on, the rest dim, paper not the user\'s to tick',
      (tester) async {
    await pumpCels(tester, celsSession());

    for (final id in ['paper', 'a', 'a-color', 'b', 'f', 'c', 'd', 'inst']) {
      expect(
        find.byKey(ValueKey<String>('export-cels-row-$id')),
        findsOneWidget,
        reason: 'row $id',
      );
    }
    expect(dot(tester, 'export-cels-dot-a').value, isTrue);
    expect(dot(tester, 'export-cels-dot-a-color').value, isTrue);
    expect(dot(tester, 'export-cels-dot-b').value, isFalse);
    expect(dot(tester, 'export-cels-dot-inst').value, isFalse);
    expect(dot(tester, 'export-cels-dot-paper').onTap, isNull);
    // The folder's leaves are both in, so the folder reads whole.
    expect(dot(tester, 'export-cels-dot-f').value, isTrue);
    expect(dot(tester, 'export-cels-dot-f').indeterminate, isFalse);

    // A ×2 + C + D; the paper row is applied, not counted.
    expect(bundleCount(tester), AppText.strings.exCelCount(4));
    expect(textOf(tester, 'export-transport-line'), 'A1.png · 1 / 2');
    // The filters' defaults: 기준 and 부속 on, 시트 off; the additions off.
    expect(pill(tester, 'export-cels-select-base').selected, isTrue);
    expect(pill(tester, 'export-cels-select-attach').selected, isTrue);
    expect(pill(tester, 'export-cels-select-sheet').selected, isFalse);
    expect(pill(tester, 'export-cels-add-direction').selected, isFalse);
    expect(pill(tester, 'export-cels-select-custom').selected, isFalse);
    expect(pill(tester, 'export-cels-select-custom').onTap, isNull);
  });

  testWidgets('ticking a row the filters left out forces it in: the plan '
      'grows, 「커스텀」 lights, and a filter pill drops the exception',
      (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-dot-b');
    expect(deltaOf(session)?.layerOverrides[const LayerId('b')], isTrue);
    expect(bundleCount(tester), AppText.strings.exCelCount(5));
    expect(pill(tester, 'export-cels-select-custom').selected, isTrue);

    // 시트 on: C is off the sheet and goes; the hand exception goes with the
    // rule change.
    await tapKey(tester, 'export-cels-select-sheet');
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(pill(tester, 'export-cels-select-custom').selected, isFalse);
    expect(pill(tester, 'export-cels-select-sheet').selected, isTrue);
    expect(bundleCount(tester), AppText.strings.exCelCount(3));
  });

  testWidgets('the 선택 pills are filters that STACK: 기준 off leaves the '
      'riders on the base\'s axis, 부속 off leaves the bases alone, both off '
      'leaves nothing', (tester) async {
    // 유저 2026-09-09: 「기준/부속 고르면 기준레이어+부속레이어까지 묶고, 부속만
    // 되있으면 기준레이어가 아닌 부속레이어만 묶고」.
    final state = await pumpCels(tester, celsSession());

    await tapKey(tester, 'export-cels-select-attach');
    expect(state.debugSpecs.cels.attach, isFalse);
    expect(dot(tester, 'export-cels-dot-a').value, isTrue);
    expect(dot(tester, 'export-cels-dot-a-color').value, isFalse);
    expect(bundleCount(tester), AppText.strings.exCelCount(4));

    await tapKey(tester, 'export-cels-select-base');
    expect(state.debugSpecs.cels.base, isFalse);
    expect(bundleCount(tester), AppText.strings.exCelCount(0));

    // 부속 alone: the colour row rides base A's axis — two cels named by A.
    await tapKey(tester, 'export-cels-select-attach');
    expect(dot(tester, 'export-cels-dot-a').value, isFalse);
    expect(dot(tester, 'export-cels-dot-a-color').value, isTrue);
    expect(bundleCount(tester), AppText.strings.exCelCount(2));
    expect(textOf(tester, 'export-transport-line'), 'A1.png · 1 / 2');
  });

  testWidgets('디렉션 is an ADDITION: its pill adds the direction row\'s events '
      'beside the drawings', (tester) async {
    final state = await pumpCels(tester, celsSession());

    await tapKey(tester, 'export-cels-add-direction');
    expect(state.debugSpecs.cels.addDirection, isTrue);
    expect(pill(tester, 'export-cels-add-direction').selected, isTrue);
    expect(dot(tester, 'export-cels-dot-inst').value, isTrue);
    expect(dot(tester, 'export-cels-dot-a').value, isTrue);
    expect(bundleCount(tester), AppText.strings.exCelCount(5));
    expect(
      find.byKey(const ValueKey<String>('export-cels-bundle-inst')),
      findsOneWidget,
    );
  });

  testWidgets('open alpha reads as the checkerboard under the picture; an '
      'opaque format has none — on every tab\'s preview', (tester) async {
    // 유저 2026-09-09: 「png rgba같은것처럼 배경에 아무것도 없다면 … 투명이라는
    // 의미의 체크무늬 … 이미있으면 있던거 쓰고. 다른 출력항목도 같은거 적용」.
    // The Image tab: its composite resolves even for an ink-less fixture
    // (a cel with no ink renders nothing on the Cels tab), and its default
    // PNG is RGBA.
    final state = await pumpCels(tester, celsSession());
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
    await tester.pump();
    await tester.runAsync(state.debugFlushPreview);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('export-preview-image')),
      findsOneWidget,
    );
    final checker = find.byKey(const ValueKey<String>('export-preview-checker'));
    expect(checker, findsOneWidget);
    expect(
      tester.widget<CustomPaint>(checker).painter,
      isA<AlphaCheckerboardPainter>(),
      reason: 'the canvas\'s own alpha checker, not a second one',
    );

    await tapKey(tester, 'export-format-channels-rgb');
    await tester.runAsync(state.debugFlushPreview);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('export-preview-image')),
      findsOneWidget,
    );
    expect(checker, findsNothing);
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

  testWidgets('the folder dot ticks its leaves together and reads half when '
      'they disagree', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-dot-c');
    expect(deltaOf(session)?.layerOverrides[const LayerId('c')], isFalse);
    expect(dot(tester, 'export-cels-dot-f').indeterminate, isTrue);
    expect(bundleCount(tester), AppText.strings.exCelCount(3));

    // Half → whole: the exception that equals the rule again disappears.
    await tapKey(tester, 'export-cels-dot-f');
    expect(deltaOf(session)?.layerOverrides ?? const {}, isEmpty);
    expect(dot(tester, 'export-cels-dot-f').value, isTrue);

    // Whole → none: both leaves off in one write.
    await tapKey(tester, 'export-cels-dot-f');
    expect(deltaOf(session)?.layerOverrides, {
      const LayerId('c'): false,
      const LayerId('d'): false,
    });
    expect(dot(tester, 'export-cels-dot-f').value, isFalse);
    expect(dot(tester, 'export-cels-dot-f').indeterminate, isFalse);
    expect(bundleCount(tester), AppText.strings.exCelCount(2));
  });

  testWidgets('the cel list: unticking a bundle keeps it listed, drops it '
      'from the count, and Reset restores it', (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);

    await tapKey(tester, 'export-cels-bundle-dot-a');
    expect(deltaOf(session)?.skippedBases, {const LayerId('a')});
    expect(bundleCount(tester), AppText.strings.exCelCount(2));
    expect(
      find.byKey(const ValueKey<String>('export-cels-bundle-a')),
      findsOneWidget,
      reason: 'an unticked cel stays in the list with its dot off',
    );
    expect(dot(tester, 'export-cels-bundle-dot-a').value, isFalse);
    // The row selection is a different question — the rows stay as they were.
    expect(dot(tester, 'export-cels-dot-a').value, isTrue);

    await tester.tap(find.text('Reset').first);
    await tester.pump();
    expect(deltaOf(session), isNull);
    expect(bundleCount(tester), AppText.strings.exCelCount(4));
  });

  testWidgets('choosing a cel in the list drives the preview to its first '
      'sheet, and the nav counts that bundle alone', (tester) async {
    await pumpCels(tester, celsSession());

    await tapKey(tester, 'export-cels-bundle-c');
    expect(textOf(tester, 'export-transport-line'), 'C1.png · 1 / 1');
    await tapKey(tester, 'export-cels-bundle-a');
    expect(textOf(tester, 'export-transport-line'), 'A1.png · 1 / 2');
  });

  testWidgets('the label picker is the timeline\'s flyout: 「라벨 없음」 empties '
      'a KEY cut, a stage picked through its hover child relabels the export',
      (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(
      textOf(tester, 'export-cels-label-text'),
      exportCelLabelText(key),
    );

    await tapKey(tester, 'export-cels-label-picker');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('layer-mark-option-none')));
    await tester.pumpAndSettle();
    expect(state.debugSpecs.cels.label, LayerMark.none);
    expect(
      textOf(tester, 'export-cels-label-text'),
      AppText.strings.tlLayerMarkNone,
    );
    expect(bundleCount(tester), AppText.strings.exCelCount(0));

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
    expect(textOf(tester, 'export-cels-label-text'), exportCelLabelText(layout));
  });

  testWidgets('the take picker is the timeline\'s flyout plus 「최신」',
      (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(textOf(tester, 'export-cels-take-text'), AppText.strings.exTakeLatest);

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
      textOf(tester, 'export-cels-take-text'),
      AppText.strings.tlLayerTakeNumber(2),
    );
    // Nothing in the cut is a second take.
    expect(bundleCount(tester), AppText.strings.exCelCount(0));

    await tapKey(tester, 'export-cels-take-picker');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-take-option-latest')),
    );
    await tester.pumpAndSettle();
    expect(state.debugSpecs.cels.take, isNull);
    expect(bundleCount(tester), AppText.strings.exCelCount(4));
  });

  testWidgets('적용 and 추가 are pills that write the spec', (tester) async {
    final state = await pumpCels(tester, celsSession());
    expect(pill(tester, 'export-cels-apply-paper').selected, isTrue);
    expect(pill(tester, 'export-cels-add-art').selected, isFalse);

    await tapKey(tester, 'export-cels-apply-paper');
    expect(state.debugSpecs.cels.applyPaper, isFalse);
    expect(pill(tester, 'export-cels-apply-paper').selected, isFalse);

    await tapKey(tester, 'export-cels-add-art');
    expect(state.debugSpecs.cels.addArt, isTrue);
    expect(pill(tester, 'export-cels-add-art').selected, isTrue);
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
