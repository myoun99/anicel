import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart'
    show debugOperatingSystemOverride;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_job.dart';
import 'package:anicel/src/ui/export/export_queue_column.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/export/png_sequence_export_service.dart'
    show ExportWriteSummary;
import 'package:anicel/src/ui/export/video_export_service.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/sheet/paper_editing.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_format_pick.dart';
import '../../helpers/paper_editing_kit.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/temp_dir.dart';

/// A movie run that writes one byte where the movie goes, at once — so a
/// movie is handed over as every tab's files are, and held there as they
/// are.
class _AMovieOfOneByte extends VideoExportService {
  @override
  Future<ExportWriteSummary> exportVideo({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    File(outputFilePath).writeAsBytesSync(const [0]);
    return (written: count, processed: count);
  }
}

/// Something in the window that takes a press: the element holding it, the
/// name the nearest key gives it, the name found looking the other way —
/// under it where the first looked over it — and what it says to a screen
/// reader.
typedef _Taker = ({Element holder, String key, String also, String said});

/// The export window under test: its state, how many times it has handed
/// its files over, the answer that lets the hand-over held go, what it
/// edits the papers with, the editor's actions its keys reached and the
/// keys the editor's held keys were asked about.
typedef _Window = ({
  ExportDialogState state,
  int Function() handedOver,
  void Function() release,
  PaperEditing editing,
  List<String> invoked,
  List<KeyEvent> held,
});

/// 🚨WHILE AN EXPORT IS UNDER WAY, THE WINDOW TAKES NO PRESS BUT ONE THAT
/// MOVES IT ABOUT — a module or a drawer folded open or shut, the preview
/// framed (fit, 1:1, the zoom), a scrollbar — and Cancel.
///
/// A run in flight owns the spec (`_pill`), and the preview shows what it
/// is writing ([ExportPreviewPanel.enabled]): a press that changed either
/// would change the files under way, or hide them. Each control of the
/// window kept that law by a guard of its own and nothing saw them all —
/// two of its three Resets and the Cels list's rows had none (board
/// `nothing-pins-the-export-dialog-shut-while-exporting`).
///
/// So each tab is held mid-run with all it can offer on offer — every
/// module open, a Reset lit wherever one stands, its drawers open with a
/// job queued — and everything that would take a press is read off it:
/// each node a screen reader could press, and each control that claims a
/// press of its own ([ControlPressClaim]) and tells the reader nothing, as
/// the switch rows do.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-under-way');
    deleteTempQuietly(Directory(SessionScratch.outboxFolder()));
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    debugOperatingSystemOverride = null;
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugFilesExporter = null;
    deleteTempQuietly(Directory(SessionScratch.outboxFolder()));
    deleteTempQuietly(temp);
  });

  const key = LayerMark(process: LayerProcess.key);

  // Cels are numbered by their frame NAME: 'f1' is cel 1.
  Frame frame(String id) => Frame(
    id: FrameId(id),
    duration: 1,
    strokes: const [],
    name: id.replaceAll(RegExp('[^0-9]'), ''),
  );

  /// CUT1: A's two drawings with a colour row synced to them, B, a
  /// storyboard drawing, a direction row, a camera that moves and a
  /// perspective guide — so every tab has something to offer, the Cels
  /// tab's band, stack and laying pills too — and CUT2 beside it, so the
  /// Cels list has a cut to pick.
  EditorSessionManager session() => inkEveryCel(EditorSessionManager(
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
              id: const CutId('cut1'),
              name: 'CUT1',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              camera: CutCamera(
                keyframes: {
                  0: CameraPose(center: CanvasPoint(x: 2, y: 4)),
                  3: CameraPose(center: CanvasPoint(x: 6, y: 4)),
                },
              ),
              guides: CutGuides(
                guides: [
                  DrawingGuide(
                    id: const GuideId('perspective'),
                    name: 'Perspective',
                    shape: PerspectiveShape(
                      vanishingPoints: [
                        VanishingPointAt(CanvasPoint(x: 6, y: 2)),
                      ],
                      eyeLevel: GuideAxis(
                        origin: CanvasPoint(x: 0, y: 2),
                        angleDegrees: 0,
                      ),
                    ),
                  ),
                ],
              ),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  mark: key,
                  frames: [frame('f1'), frame('f2')],
                ),
                Layer(
                  id: const LayerId('a-color'),
                  name: 'A2',
                  mark: key,
                  frames: [frame('c1'), frame('c2')],
                  attachedToLayerId: const LayerId('a'),
                  attachedMode: AttachedMode.synced,
                  baseFrameLinks: {
                    const FrameId('f1'): const FrameId('c1'),
                    const FrameId('f2'): const FrameId('c2'),
                  },
                ),
                Layer(
                  id: const LayerId('b'),
                  name: 'B',
                  mark: key,
                  frames: [frame('b1')],
                ),
                Layer(
                  id: const LayerId('sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [frame('s1')],
                  timeline: {
                    0: const TimelineExposure.drawing(
                      FrameId('s1'),
                      length: 4,
                      memo: ExposureMemo(inkId: 'ink-s1'),
                    ),
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
                createCameraLayer(cutId: const CutId('cut1')),
              ],
            ),
            Cut(
              id: const CutId('cut2'),
              name: 'CUT2',
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('cut2-a'),
                  name: 'A',
                  mark: key,
                  frames: [frame('g1')],
                ),
                createCameraLayer(cutId: const CutId('cut2')),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  ));

  Finder keyed(String key) => find.byKey(ValueKey<String>(key));

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(keyed(key));
    await tester.pump();
  }

  /// Opens every module of the tab shown.
  Future<void> unfoldEverything(WidgetTester tester) async {
    for (var pass = 0; pass < 3; pass++) {
      final shut = [
        for (final accordion in tester.widgetList<ExportAccordion>(
          find.byType(ExportAccordion),
        ))
          if (!accordion.expanded) accordion,
      ];
      for (final accordion in shut) {
        accordion.onToggle();
      }
      await tester.pump();
    }
  }

  /// Each tab with all it can offer on offer, and the keys of what it then
  /// offers that would change the run: every module open, a Reset lit
  /// wherever one stands — and on the Cels tab its list stood on a drawing
  /// with another to step to, a row switched off by hand and the project's
  /// cuts to pick from.
  final tabs =
      <
        String,
        ({Future<void> Function(WidgetTester) setUp, List<String> offers})
      >{
        'the Sequence tab writing stills': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-sequence');
            await pickExportStill(tester, ExportStillFormat.png);
            await unfoldEverything(tester);
            await tester.enterText(keyed('export-naming-base-field'), 'shot');
            await tester.pump();
          },
          offers: [
            'export-tab-image',
            'export-format-kind',
            'export-format-file',
            'export-naming-base-field',
            'export-scope-project',
            'export-apply-fx-basic',
            'export-transport-play',
            'export-transport-in-step-up',
          ],
        ),
        'the Sequence tab writing a movie': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-sequence');
            await pickExportContainer(tester, ExportVideoContainer.mov);
            await unfoldEverything(tester);
          },
          offers: [
            'export-file-name-field',
            'export-format-kind',
            'export-format-file',
            'export-format-codec',
            'export-audio-toggle-ring',
          ],
        ),
        'the Image tab': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-image');
            await unfoldEverything(tester);
          },
          offers: [
            'export-file-name-field',
            'export-format-file',
            'export-image-fx-off',
            'export-transport-play',
          ],
        ),
        'the Cels tab': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-cels');
            await unfoldEverything(tester);
            await tapKey(tester, 'export-scope-project');
            await tapKey(tester, 'export-cels-stand-a');
            await tapKey(tester, 'export-cels-switch-b');
            await tester.enterText(keyed('export-cel-suffix-field'), '_x');
            await tester.pump();
          },
          offers: [
            'export-cels-reset',
            'export-cels-stand-a',
            'export-cels-switch-a',
            'export-cels-cut-picker',
            'export-cut-grid',
            'export-cut-cell-2',
            'export-cels-stack-switch-a-ring',
            'export-cels-next',
            'export-cels-cam',
            'export-cels-direction-inst-inst-span-0',
            'export-cels-guides',
            'export-cels-kind-direction',
            'export-cels-select-base',
            'export-cels-label-picker',
            'export-cels-take-picker',
            'export-cel-suffix-field',
            'export-tsformat-file',
            'export-envelope-paper-sheet',
            'export-cels-apply-fx-basic',
          ],
        ),
        // I-127: the page the list stands on is its panel's paper — its
        // boxes typed in place, its brush switch.
        'the Cels tab standing on its timesheet': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-cels');
            await unfoldEverything(tester);
            await tapKey(tester, 'export-cels-stand-document-timesheet');
          },
          offers: [
            'timesheet-name-edit-p0',
            'export-timesheet-brush-toggle-button',
          ],
        ),
        'the Conte Sheet tab': (
          setUp: (tester) async {
            await tapKey(tester, 'export-tab-conte');
            await unfoldEverything(tester);
          },
          offers: [
            'export-file-name-field',
            'export-conteformat-file',
            'export-preview-next-page-button',
          ],
        ),
      };

  /// [element] and every element it stands in, itself first.
  List<Element> standingIn(Element element) {
    final chain = [element];
    element.visitAncestorElements((ancestor) {
      chain.add(ancestor);
      return true;
    });
    return chain;
  }

  /// The name the nearest key gives [element]: its own, or the first one
  /// over it — or, looking [down], the first one under it.
  String nameOf(Element element, {bool down = false}) {
    if (!down) {
      for (final standing in standingIn(element)) {
        if (standing.widget.key case ValueKey<String>(:final value)) {
          return value;
        }
      }
      return '';
    }
    final queue = [element];
    while (queue.isNotEmpty) {
      final next = queue.removeAt(0);
      if (next.widget.key case ValueKey<String>(:final value)) {
        return value;
      }
      next.visitChildren(queue.add);
    }
    return '';
  }

  /// Everything in the window that takes a press now: every node a screen
  /// reader could press, as the element that made it, and every control
  /// that claims a press of its own and says nothing to the reader.
  List<_Taker> takersOfAPress(WidgetTester tester) {
    final owners = <int, RenderObject>{};
    void own(RenderObject object) {
      final node = object.debugSemantics;
      if (node != null) {
        owners.putIfAbsent(node.id, () => object);
      }
      object.visitChildren(own);
    }

    tester.binding.renderViews.forEach(own);
    final voiced = <_Taker>[
      for (final node in find.semantics
          .byPredicate((node) => node.getSemanticsData().actions != 0)
          .evaluate())
        if (owners[node.id]!.debugCreator case DebugCreator(:final element))
          (
            holder: element,
            key: nameOf(element),
            also: nameOf(element, down: true),
            said: [
              node.getSemanticsData().label,
              node.getSemanticsData().tooltip,
            ].where((word) => word.isNotEmpty).join(' · '),
          ),
    ];
    final spoken = {
      for (final taker in voiced)
        for (final standing in standingIn(taker.holder))
          if (standing.widget is ControlPressClaim) standing,
    };
    bool blocked(Element element) => standingIn(element).any(
      (standing) => switch (standing.widget) {
        AbsorbPointer(:final absorbing) => absorbing,
        IgnorePointer(:final ignoring) => ignoring,
        _ => false,
      },
    );
    return [
      ...voiced,
      for (final element in find.byType(ControlPressClaim).evaluate())
        if ((element.widget as ControlPressClaim).onPressed != null &&
            !spoken.contains(element) &&
            !blocked(element))
          (
            holder: element,
            key: nameOf(element, down: true),
            also: nameOf(element),
            said: '',
          ),
    ];
  }

  /// Whether [widgets] — what takes a press, and what it stands in — are a
  /// module's head: in an [ExportAccordion], and neither in its Reset nor in
  /// the module it opens.
  bool foldsAModule(List<Widget> widgets) {
    final at = widgets.indexWhere((widget) => widget is ExportAccordion);
    if (at < 0) {
      return false;
    }
    final accordion = widgets[at] as ExportAccordion;
    return !widgets
        .take(at)
        .any(
          (widget) =>
              widget is ExportResetChip || identical(widget, accordion.child),
        );
  }

  /// Whether [taker] only moves the window about: folds a module or a
  /// drawer open or shut, frames the preview — fit, 1:1, the zoom; not its
  /// transport or its page turner, which turn the picture — or scrolls; or
  /// is Cancel.
  bool movesTheWindowAbout(_Taker taker) {
    final widgets = [
      for (final standing in standingIn(taker.holder)) standing.widget,
    ];
    return foldsAModule(widgets) ||
        widgets.any(
          (widget) =>
              widget is ExportDrawerStrip ||
              widget is AppScrollbar ||
              widget is AppControllerScrollbar,
        ) ||
        taker.key.startsWith('canvas-viewport-') ||
        const {
          'export-presets-collapse',
          'export-queue-collapse',
          'export-cancel-button',
        }.contains(taker.key);
  }

  /// What takes a press now that does more than move the window about.
  List<_Taker> pressesThatChangeTheRun(WidgetTester tester) => [
    for (final taker in takersOfAPress(tester))
      if (!movesTheWindowAbout(taker)) taker,
  ];

  /// The window over a fresh session on a surface it opens its drawers
  /// in, its runs handed over as iOS hands them: a run stays under way
  /// until the window's release answers the hand-over. It edits the
  /// sheets' papers as the editor's does, under the editor's keys (I-127).
  Future<_Window> openWindow(WidgetTester tester) async {
    debugOperatingSystemOverride = 'ios';
    FolderPicker.debugOperatingSystem = 'ios';
    final held = Completer<FolderGrant>();
    var handedOver = 0;
    FolderPicker.debugFilesExporter = (paths) {
      handedOver += 1;
      return held.future;
    };
    final s = session();
    addTearDown(s.dispose);
    final editing = paperEditingKit(s);
    final (:road, :invoked, held: keysHeld) = recordingKeyRoad(s);
    await tester.binding.setSurfaceSize(const Size(2000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: s,
            formatAvailability: ExportFormatAvailability.permissive(),
            videoExportService: _AMovieOfOneByte(),
            keys: road,
            paperEditing: editing,
          ),
        ),
      ),
    );
    await tester.pump();
    return (
      state: tester.state<ExportDialogState>(find.byType(ExportDialog)),
      handedOver: () => handedOver,
      release: () => held.complete(FolderGrant.granted(path: temp.path)),
      editing: editing,
      invoked: invoked,
      held: keysHeld,
    );
  }

  /// Runs what [start] starts in [window], holds it at its hand-over and
  /// reads the window then: nothing in it takes a press that would change
  /// the run, and Cancel and the bar stand in its footer — and once the
  /// run is let go, they leave it again.
  Future<void> holdTheRun(
    WidgetTester tester,
    _Window window,
    Future<void> Function() start,
  ) async {
    expect(keyed('export-cancel-button'), findsNothing);
    expect(keyed('export-progress'), findsNothing);

    late Future<void> whole;
    await tester.runAsync(() async {
      whole = start();
      expect(await pollUntil(() => window.handedOver() == 1), isTrue);
    });
    await tester.pump();
    await tester.pump();

    expect(
      [
        for (final taker in pressesThatChangeTheRun(tester))
          '${taker.key} "${taker.said}"',
      ],
      isEmpty,
      reason:
          'a run in flight owns the spec, and the preview shows what it '
          'writes',
    );
    expect(keyed('export-cancel-button'), findsOneWidget);
    expect(keyed('export-progress'), findsOneWidget);

    await tester.runAsync(() async {
      window.release();
      await whole;
    });
    await tester.pump();
    expect(keyed('export-cancel-button'), findsNothing);
    expect(keyed('export-progress'), findsNothing);
  }

  for (final MapEntry(key: tab, value: (:setUp, :offers)) in tabs.entries) {
    testWidgets('while $tab is writing, nothing in the window takes a press '
        'that would change what it writes or what its preview shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final window = await openWindow(tester);
      await setUp(tester);
      expect(keyed('export-presets-collapse'), findsOneWidget);
      expect(keyed('export-queue-collapse'), findsOneWidget);
      await tapKey(tester, 'export-queue-add-button');

      // The premise: resting, the window takes every press the tab offers.
      final resting = pressesThatChangeTheRun(tester);
      expect(
        resting.expand((taker) => [taker.key, taker.also]),
        containsAll([
          ...offers,
          'export-run-button',
          'export-queue-add-button',
          'export-queue-render-all',
          'export-queue-remove-1',
          'export-preset-save-current',
          'app-window-close',
        ]),
      );

      await holdTheRun(tester, window, window.state.export);
      semantics.dispose();
    });
  }

  testWidgets('while the queue is writing, nothing in the window takes a '
      'press that would change what it writes', (tester) async {
    final semantics = tester.ensureSemantics();
    final window = await openWindow(tester);
    await tabs['the Sequence tab writing stills']!.setUp(tester);
    await tapKey(tester, 'export-queue-add-button');
    await holdTheRun(tester, window, window.state.runQueue);
    semantics.dispose();
  });

  testWidgets('premise: a Reset lit takes a press of its own, apart from '
      'its module\'s head — the Sequence tab lights two', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWindow(tester);
    await tabs['the Sequence tab writing stills']!.setUp(tester);
    expect(
      [
        for (final taker in pressesThatChangeTheRun(tester))
          if (taker.said == AppText.strings.commonReset) taker,
      ],
      hasLength(2),
    );
    expect(
      takersOfAPress(tester).where(movesTheWindowAbout).map((t) => t.key),
      containsAll(['canvas-viewport-fit', 'export-presets-collapse']),
    );
    semantics.dispose();
  });

  testWidgets('a run in flight refuses another: Export again, the queue run, '
      'and a queued job taken back into the window', (tester) async {
    final window = await openWindow(tester);
    await tabs['the Sequence tab writing stills']!.setUp(tester);
    await tapKey(tester, 'export-queue-add-button');
    final column = tester.widget<ExportQueueColumn>(
      find.byType(ExportQueueColumn),
    );
    final job = column.queue.jobs.single;

    // Each refused at once: one that ran would wait on the hand-over held.
    late Future<void> whole;
    await tester.runAsync(() async {
      whole = window.state.export();
      expect(await pollUntil(() => window.handedOver() == 1), isTrue);
      await patiently(window.state.export());
      await patiently(window.state.runQueue());
    });
    column.onRestore!(job);
    await tester.pump();

    expect(window.handedOver(), 1);
    expect(column.queue.jobs.single.status, ExportJobStatus.queued);

    await tester.runAsync(() async {
      window.release();
      await whole;
    });
    await tester.pump();
    expect(window.handedOver(), 1);
  });

  // I-127: the window takes the editor's tool keys and its undo — which
  // change the film a run is writing.
  testWidgets('🚨while the Cels tab writes, its paper takes no stroke and '
      'the editor\'s keys reach nothing — both come back when it ends', (
    tester,
  ) async {
    final window = await openWindow(tester);
    await tabs['the Cels tab standing on its timesheet']!.setUp(tester);
    window.editing.timesheetBrushAllowed.value = true;
    await tester.pump();
    expect(find.byType(TimesheetInkLayer), findsOneWidget, reason: 'premise');

    Future<void> pressKeys() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    late Future<void> whole;
    await tester.runAsync(() async {
      whole = window.state.export();
      expect(await pollUntil(() => window.handedOver() == 1), isTrue);
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(TimesheetInkLayer), findsNothing);
    await pressKeys();
    expect(window.invoked, isEmpty);
    expect(window.held, isEmpty, reason: 'no key is held to a tool either');

    await tester.runAsync(() async {
      window.release();
      await whole;
    });
    await tester.pump();
    expect(find.byType(TimesheetInkLayer), findsOneWidget);
    await pressKeys();
    expect(window.invoked, [EditorActionIds.toolEraser, EditorActionIds.undo]);
    expect(window.held, isNotEmpty);
  });
}
