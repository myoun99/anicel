import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/argb_channels.dart';
import '../../core/path_names.dart';
import '../../models/kept_span.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import '../../native/qa_image_encoder.dart';
import '../../services/audio/audio_mixer_reference.dart' show AudioMixSource;
import '../../services/brush_frame_store.dart' show CelRead;
import '../../services/export/xdts_builder.dart';
import '../../services/persistence/app_export_settings.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../../services/persistence/session_scratch.dart';
import '../editor_session_manager.dart';
import '../../models/export_overrides.dart';
import '../../models/layer.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/app_language.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_windows.dart';
import '../../models/conte/conte_words.dart';
import '../../models/conte/conte_page_marks.dart'
    show contePictureOf, contePictureRenderWidth;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/sheet_marks.dart' show SheetPictureKey;
import '../../models/conte/conte_sheet_source.dart';
import '../envelope/cut_envelope_ink.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_presets.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/tiled_surface_compose.dart';
import '../conte/conte_picture_ink.dart' show contePicturesOverInkIn;
import '../conte/conte_sheet_builder.dart';
import '../conte/conte_words_in.dart';
import '../envelope/cut_envelope_builder.dart';
import 'export_envelope_render.dart';
import 'conte_pdf_writer.dart';
import 'export_audio_mix.dart';
import 'export_cel_group_plan.dart';
import 'export_cels_board.dart';
import 'export_cels_standing.dart';
import 'export_conte_render.dart';
import 'export_cels_selection.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../services/commands/link_mirror.dart' show linkedCutSiblings;
import '../timeline/layer_label_controls.dart';
import '../timeline/timeline_cell_style.dart' show timelineTextOnColor;
import '../widgets/panel_flyout.dart';
import '../widgets/settings_rows.dart';
import 'export_cut_grid.dart';
import 'export_format_availability.dart';
import 'export_frame_renderer.dart';
import 'export_job.dart';
import 'export_plan.dart';
import 'export_preset_rail.dart';
import 'export_preview_document.dart';
import 'export_preview_panel.dart';
import 'export_queue_column.dart';
import 'export_settings_modules.dart';
import 'export_timesheet_render.dart';
import 'png_sequence_export_service.dart';
import 'video_export_service.dart';
import '../../models/cut_id.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_words.dart';
import '../timesheet/timesheet_document_painter.dart'
    show TimesheetDocumentLayout;
import '../timesheet/cut_sheet_document.dart';
import '../timesheet/timesheet_ink_layer.dart' show timesheetInkWindows;
import '../timesheet/timesheet_words_in.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/app_window.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../text/app_face.dart';
import '../text/app_strings.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;
import '../widgets/cursor_notice.dart';
import '../widgets/pill_strip.dart';
import '../widgets/transport_bar.dart' show TransportRange;

/// A test's stand-in for the system window that asks where outputs go: the
/// folder a person picks there; `null` when they back out.
typedef ExportDirectoryPicker = Future<String?> Function();

/// The v10 export window: presets | preview | settings | queue over a
/// footer, four tabs. Where the outputs go is asked when Export is pressed
/// (F-221) — there is no location to choose ahead.
///
/// EX2 ships the shell with today's capabilities behind the new grammar
/// (MP4·H.264 / PNG / XDTS); the format lineup, the live preview and the
/// queue runner widen it in later rounds.
class ExportDialog extends StatefulWidget {
  const ExportDialog({
    super.key,
    required this.session,
    this.exportDirectoryPicker,
    this.videoExportService = const VideoExportService(),
    this.settingsStore,
    this.formatAvailability,
  });

  final EditorSessionManager session;

  /// Injectable for tests: stands in for whichever system window the door
  /// opens — the folder window, or the save window of a lone file.
  final ExportDirectoryPicker? exportDirectoryPicker;

  /// Injectable for tests; the real one prefers the OS encoder and falls
  /// back to ffmpeg.
  final VideoExportService videoExportService;

  /// Persists presets/last-used state. Null (the test default) keeps the
  /// state in memory only — no test may write the user's real settings.
  final AppExportSettingsStore? settingsStore;

  /// What this machine can write; null builds the real probe. Tests
  /// inject [ExportFormatAvailability.permissive] so the fake ffmpeg can
  /// carry any pair.
  final ExportFormatAvailability? formatAvailability;

  @override
  State<ExportDialog> createState() => ExportDialogState();
}

class ExportDialogState extends State<ExportDialog> {
  static const _exportService = PngSequenceExportService();

  ExportTab _tab = ExportTab.sequence;
  late ExportTabSpecs _specs;

  /// Where the outputs of the run under way go — asked when Export is
  /// pressed ([_askWhere]), and of a queued job when it was queued; null
  /// until then. A run asked a folder writes into it ([_location]); a lone
  /// file asked a place of its own is written at it ([_placedFile]). A run
  /// asked its place afterwards (drive-folder-windows-Q1) writes into an
  /// outbox of its own ([_runOutbox]) and [handOverFilesForUser] takes it
  /// from there.
  ///
  /// ⚠️ONE value on purpose: which kind of place it is, and the place, were
  /// fields kept together by hand — a path, the token beside it, and
  /// 「끝나면 고르기」 as a third to keep apart from them. As one value, no
  /// code can leave half of a destination behind.
  ExportDestination? _destination;

  /// The folder the run under way writes into — the one it was asked, or
  /// the one its lone file was asked a place in; null while its outputs are
  /// handed over afterwards.
  String? get _location => switch (_destination) {
    ExportPlace(:final folderPath) => folderPath,
    _ => null,
  };

  /// The file the run under way was asked a place for — its ONE file, at
  /// the path the save window answered ([ExportToFile]); null for every
  /// other run.
  ///
  /// ⛔READ ONLY WHERE A RUN WRITES ([_joinLocation], [_runImageExport],
  /// [_exportCurrentFrame]). [_destination] stays after its run ends, so a
  /// name field or a preview plate that read this would go on showing the
  /// last run's name — they say what the form names ([_singleFileName]).
  String? get _placedFile => switch (_destination) {
    ExportToFile(:final path) => path,
    _ => null,
  };

  /// The name [_placedFile] gives the run's lone file — the one the window
  /// answered with, which a person may have changed there.
  String? get _placedName => switch (_placedFile) {
    final file? => fileNameOfPath(file),
    null => null,
  };

  bool _presetsOpen = true;
  bool _queueOpen = true;

  /// Where the run under way writes when it hands over — its own folder in
  /// this run's room ([SessionScratch.outboxFolder]); null otherwise.
  String? _runOutbox;

  /// Where the run under way writes: its outbox when it hands over, the
  /// chosen folder otherwise.
  String get _outputDirectory => _runOutbox ?? _location!;

  final Map<String, bool> _expanded = {};
  final ExportQueueModel _queue = ExportQueueModel();

  late final TextEditingController _sequenceFileController;
  late final TextEditingController _imageFileController;
  late final TextEditingController _conteFileController =
      TextEditingController(text: 'conte');
  late final TextEditingController _namingBaseController;
  late final TextEditingController _celSuffixController;

  /// The naming module's prefix fields, one a kind.
  late final Map<ExportCelKind, TextEditingController> _celPrefixControllers = {
    for (final kind in ExportCelKind.values) kind: TextEditingController(),
  };

  bool _isExporting = false;
  bool _cancelRequested = false;
  String? _statusMessage;

  /// Where the end of the footer's bar stands for the run under way, in the
  /// bar's own pixels ([_barPixels]) — null when no run is. The bar is all
  /// that hears it ([_footerBetween]).
  ///
  /// 🚨IN PIXELS, SO THAT A FRAME WHICH DOES NOT MOVE THE BAR IS NOT HEARD.
  /// A notifier says nothing when its value is the one it had, and a film
  /// of two thousand frames moves a bar of three hundred pixels three
  /// hundred times. ↩️Counted in frames, every frame that went out asked
  /// the window to draw itself again, to move the bar by less than can be
  /// seen.
  ///
  /// ↩️Before that it was the window's own state, and every frame of a run
  /// rebuilt the whole window — and wrote a sentence counting the frames
  /// into the status line, which a run keeps out of sight.
  ///
  /// Measured 2026-10-07 in the app's own binding, over the user's film of
  /// 1,857 frames (F-289): the window's frames took 7.3 s of the UI thread
  /// rebuilt whole, 2.1 s with the bar alone hearing every frame, and 1.6 s
  /// hearing the frames that move it — 738, 749 and 546 frames drawn.
  /// ⚠️Not under the test binding: it draws a frame after every frame it is
  /// not pumping for, and a count of window frames taken there is the
  /// binding's own.
  final ValueNotifier<({int end, int of})?> _progress = ValueNotifier(null);

  /// How many device pixels long the footer's bar was last laid out — none
  /// until it has been.
  int _barPixels = 0;

  // The preview's renderers key on (FX, ground): both change what a frame
  // looks like (EX4).
  final Map<(bool, int), ExportFrameRenderer> _previewRenderers = {};
  late ExportFormatAvailability _availability;
  bool _ownsAvailability = false;
  int _sequencePosition = 0;
  late int _imageFrame;
  /// The cut the Cels list shows — the picker's pick; null shows the cut
  /// the window opened on ([_celCutShown]).
  CutId? _celListCut;

  /// Where the Cels list stands ([ExportCelsStanding]).
  ExportCelsStanding _celStanding = const ExportCelsStanding();

  /// The rows of the Cels list whose twirl is shut.
  final Set<LayerId> _celShut = {};

  /// Why a press in this window did nothing, said at the pointer — the
  /// window's own channel: the editor's overlay lies under this window's
  /// barrier, where a notice would be said to nobody.
  final CursorNoticeController _notices = CursorNoticeController();
  int _contePosition = 0;
  // Sheet documents are chunky to derive; the modal dialog memoizes per
  // cut IDENTITY (the film cannot change under an open dialog).
  final Map<CutId, (Cut, TimesheetDocument, TimesheetDocumentLayout)>
  _sheetDocs = {};
  // The conte sheet reads the WHOLE project — memoized on its identity
  // (the film cannot change under an open dialog).
  (Object, ConteSheetSource, List<ContePageLayout>)? _conteSheetCache;

  EditorSessionManager get _session => widget.session;

  /// R27 #31: the cut this window is built around, resolved ONCE (the film
  /// cannot change under a modal dialog). Null = the project has no cuts
  /// at all, and the window degrades to an empty state instead of taking
  /// the app down with a `requireActiveCut` throw.
  Cut? _anchorCut;

  @override
  void initState() {
    super.initState();
    _anchorCut = _session.activeCutSpan.exportAnchorCutOrNull;
    final restored = AppExport.settings.value;
    _specs = restored.lastSpecs;
    _presetsOpen = restored.presetsDrawerOpen;
    _queueOpen = restored.queueDrawerOpen;
    final projectName = sanitizeExportFileComponent(
      _session.repository.requireProject().name,
    );
    _sequenceFileController = TextEditingController(text: projectName);
    _imageFileController = TextEditingController(text: projectName);
    _namingBaseController = TextEditingController(
      text: _specs.sequence.naming.baseName,
    );
    _celSuffixController = TextEditingController(
      text: _specs.cels.naming.suffix,
    );
    _availability = widget.formatAvailability ?? ExportFormatAvailability();
    _ownsAvailability = widget.formatAvailability == null;
    // Grayed pairs re-enable when the async ffmpeg answer lands.
    _availability.addListener(_onAvailabilityChanged);
    _imageFrame = _session.editingFrameCursor.value.clamp(
      0,
      math.max(1, _anchorCut?.duration ?? 1) - 1,
    );
    if (_session.activeCutSpan.exportAnchorIsFallback) {
      // Standing in a gap: "active cut" would name a cut the user is not
      // on, so the window opens project-scoped.
      _specs = _specs
          .withSpec(_specs.sequence.copyWith(scope: ExportScopeKind.project))
          .withSpec(_specs.cels.copyWith(scope: ExportScopeKind.project));
    }
    _syncControllersFromSpecs();
    unawaited(_restoreFromStore());
  }

  Future<void> _restoreFromStore() async {
    final store = widget.settingsStore;
    if (store == null) {
      return;
    }
    final loaded = await store.load();
    if (loaded == null || !mounted) {
      return;
    }
    AppExport.settings.value = loaded;
    setState(() {
      _specs = loaded.lastSpecs;
      _presetsOpen = loaded.presetsDrawerOpen;
      _queueOpen = loaded.queueDrawerOpen;
      _syncControllersFromSpecs();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _sequenceFileController.dispose();
    _imageFileController.dispose();
    _conteFileController.dispose();
    _namingBaseController.dispose();
    _celSuffixController.dispose();
    for (final controller in _celPrefixControllers.values) {
      controller.dispose();
    }
    _queue.dispose();
    _notices.dispose();
    _availability.removeListener(_onAvailabilityChanged);
    if (_ownsAvailability) {
      _availability.dispose();
    }
    super.dispose();
  }

  void _onAvailabilityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  ExportFrameRenderer _previewRendererFor({
    required bool applyLayerFx,
    required ExportFormatSelection format,
  }) {
    final bgKey = _groundKeyOf(format);
    return _previewRenderers.putIfAbsent(
      (applyLayerFx, bgKey),
      () => ExportFrameRenderer(
        session: _session,
        applyLayerFx: applyLayerFx,
        background: bgKey == -1 ? const ui.Color(0x00000000) : ui.Color(bgKey),
      ),
    );
  }

  /// What stands under a picture written in [format], as one number: its
  /// background, or -1 for one whose alpha stays open (RGBA outputs).
  static int _groundKeyOf(ExportFormatSelection format) =>
      format.wantsAlpha ? -1 : format.backgroundArgb;

  // --- state plumbing -------------------------------------------------------

  void _persist() {
    final next = AppExport.settings.value.copyWith(
      lastSpecs: _specs,
      presetsDrawerOpen: _presetsOpen,
      queueDrawerOpen: _queueOpen,
    );
    AppExport.settings.value = next;
    final store = widget.settingsStore;
    if (store != null) {
      unawaited(store.save(next));
    }
  }

  void _updateSpec(ExportTabSpec spec) {
    setState(() => _specs = _specs.withSpec(spec));
    _persist();
    _settleStanding();
  }

  void _syncControllersFromSpecs() {
    _namingBaseController.text = _specs.sequence.naming.baseName;
    _celSuffixController.text = _specs.cels.naming.suffix;
    _syncCelPrefixFields();
  }

  /// The prefix fields read what the spec says — a restore, a preset, a
  /// reset. ⛔Not on every spec write: the field being typed in would have
  /// its caret thrown to the end.
  void _syncCelPrefixFields() {
    for (final MapEntry(key: kind, value: controller)
        in _celPrefixControllers.entries) {
      controller.text = _specs.cels.naming.prefixOf(kind);
    }
  }

  bool _expandedFor(String id, {bool fallback = false}) =>
      _expanded['${_tab.jsonValue}:$id'] ?? fallback;

  void _toggleExpanded(String id, {bool fallback = false}) {
    setState(() {
      _expanded['${_tab.jsonValue}:$id'] = !_expandedFor(
        id,
        fallback: fallback,
      );
    });
  }

  /// One panel's expansion, read and toggled from ONE key. Twenty-four
  /// accordions wrote the key twice — once each way — which is two chances
  /// to disagree about which panel is being opened.
  ({bool expanded, VoidCallback onToggle}) _expansion(
    String stateKey, {
    bool open = false,
  }) => (
    expanded: _expandedFor(stateKey, fallback: open),
    onToggle: () => _toggleExpanded(stateKey, fallback: open),
  );

  /// A format/scale chip that is DEAD while an export runs. Thirteen sites
  /// wrote that guard out; it is the same law each time — a run in flight
  /// owns the spec — so one place says it.
  /// One segment of a module's pill strip; the strip is the window's one
  /// grouped-choice control ([PillStrip]).
  PillItem _pill({
    required String keyValue,
    required String label,
    required bool selected,
    required VoidCallback onPick,
  }) => PillItem(
    keyValue: keyValue,
    label: label,
    selected: selected,
    onTap: _isExporting ? null : onPick,
  );

  /// The Cels list as it stands now: the plan, the cut the list shows, its
  /// rows, and where the list stands on them — settled, so a row that left
  /// the list or a drawing that was turned off is not what is stood on.
  ///
  /// ONE reading for the board, the preview and the line under it: each
  /// working the standing out for itself is three places to disagree about
  /// which drawing is up.
  ({
    ExportCelGroupPlan plan,
    Cut cut,
    List<ExportCelsBoardRow> rows,
    ExportCelsStanding standing,
  })
  _celsList() {
    final plan = _celGroupPlan();
    final cut = _celCutShown(plan);
    final rows = ExportCelsListing(
      cut,
      _specs.cels,
    ).rows(selection: _celsSelectionOf(cut), plan: plan, shut: _celShut);
    return (
      plan: plan,
      cut: cut,
      rows: rows,
      standing: _celStanding.settledOn(rows),
    );
  }

  /// The Cels tab's list, under its preview ([ExportCelsBoard]): the rules
  /// that pick the rows, the band, and the cut's rows with a block a
  /// drawing.
  ///
  /// ↩️Two lists stood here: the cels that would be written beside the
  /// preview, one row a BUNDLE with a tick, and the cut's rows in the
  /// settings column with a tick of their own (유저 2026-10-06: 「이렇게까지
  /// 출력리스트에도 셀 on off 넣으면 사실 오른쪽의 셀 리스트랑 많은게
  /// 겹쳐서 … 어떻게 하나로 직관적으로 합칠수있나 싶어」).
  Widget _celsBoard() {
    final (:plan, :cut, :rows, :standing) = _celsList();
    final row = standing.rowIn(rows);
    final (cut: _, :pages, :at) = _celPages();
    return ExportCelsBoard(
      rules: _celRules(cut),
      band: ExportCelsBand(
        cutPicker: _celCutPicker(plan, cut),
        count: AppText.strings.exWrittenCount(plan.length),
        onStep: _isExporting ? null : _stepCel,
        canStepBack: at > 0,
        canStepOn: at >= 0 && at < pages.length - 1,
        directions: _celDirections(cut, standing.sheetIn(rows)),
      ),
      rows: rows,
      layers: cut.layers,
      standing: row?.idValue,
      shown: standing.shown,
      enabled: !_isExporting,
      onRowSwitched: (row, on) => switch (row) {
        ExportCelsLayerRow(:final layer) => _toggleCelRows(
          cut,
          row.isFolder
              ? ExportCelsListing(cut, _specs.cels).leavesOf(layer)
              : [layer],
          on,
        ),
        ExportCelsDocumentRow() => _toggleCelDocument(row, on),
      },
      onFolded: _foldCelRow,
      onStoodOn: (row) => _standCels(
        (standing, rows) => standing.standingOn(row.idValue, rows),
      ),
      onSheetPressed: _pressCelSheet,
    );
  }

  /// Moves where the Cels list stands, and shows it.
  void _standCels(
    ExportCelsStanding Function(
      ExportCelsStanding standing,
      List<ExportCelsBoardRow> rows,
    )
    move,
  ) {
    final (plan: _, cut: _, :rows, :standing) = _celsList();
    setState(() => _celStanding = move(standing, rows));
    _settleStanding();
  }

  void _stepCel(int steps) =>
      _standCels((standing, rows) => standing.stepped(steps, rows));

  /// A twirl, pressed: what the row holds under it folds away, or comes
  /// back. The window's own fold — the film's folds are the film's.
  void _foldCelRow(ExportCelsBoardRow row) {
    // Only a row of the cut holds rows under it.
    if (row is! ExportCelsLayerRow) {
      return;
    }
    setState(() {
      if (!_celShut.remove(row.layer.id)) {
        _celShut.add(row.layer.id);
      }
    });
    _settleStanding();
  }

  /// A block, pressed: a file the export would write is turned off, or
  /// back on — and one it would not says why, where the pointer is
  /// (유저 2026-10-06: 「나갈 수 없는 그림은 작동하려하면 이유 띄우자」).
  void _pressCelSheet(ExportListSheet sheet) {
    final refused = sheet.refused;
    if (refused != null) {
      final strings = AppText.strings;
      _notices.show(switch (refused) {
        ExportCelRefusal.rowOff => strings.noticeExportRowOff,
        ExportCelRefusal.noPicture => strings.noticeExportNoPicture,
        ExportCelRefusal.notPlaced => strings.noticeExportNotPlaced,
        ExportCelRefusal.sameName => strings.noticeExportSameName,
        ExportCelRefusal.ridesBase => strings.noticeExportRidesBase,
      });
      return;
    }
    _editCelDelta(sheet.deltaCut, (delta) => switch (sheet) {
      ExportCelSheet() => delta.withCelSkipped(sheet.ref, !sheet.skipped),
      ExportDocumentSheet() => delta.withPageSkipped(
        sheet.ref,
        !sheet.skipped,
      ),
      _ => delta,
    });
  }

  /// A document row's switch: its files are written, or none of them is —
  /// each answer kept with the cut its document is of (a 겸용 group's cuts
  /// each keep a timesheet).
  void _toggleCelDocument(ExportCelsDocumentRow row, bool on) {
    _session.repository.updateExportOverrides((overrides) {
      var next = overrides;
      for (final cutId in {for (final sheet in row.sheets) sheet.deltaCut}) {
        next = next.withCelsDelta(
          cutId,
          (next.deltaFor(cutId) ?? ExportCelsCutDelta()).withDocumentOff(
            row.kind,
            !on,
          ),
        );
      }
      return next;
    });
    setState(() {});
    _settleStanding();
  }

  /// The direction drawings of [cut] the band offers to lay over [shown],
  /// each lit while it is laid. Nothing is laid over a direction row's own
  /// drawing, and nothing while no drawing is shown: the pills keep their
  /// place and take no press.
  List<ExportCelsDirection> _celDirections(Cut cut, ExportListSheet? sheet) {
    // A direction is laid over a DRAWING: not over a document's page, and
    // not over a direction row's own drawing.
    final shown = sheet is ExportCelSheet ? sheet : null;
    final takes = shown != null && shown.row.kind != LayerKind.instruction;
    final laid = shown == null
        ? const <ExportCelRef>{}
        : _overrides.deltaFor(cut.id)?.directionsOver(shown.ref) ?? const {};
    return [
      for (final direction in exportDirectionDrawingsOf(
        cut,
        _session.repository.requireProject().cameraInstructions,
      ))
        (
          keyValue:
              'export-cels-direction-${direction.ref.row.value}-'
              '${direction.ref.cel.value}',
          name: direction.name,
          fullName: direction.fullName,
          laid: laid.contains(direction.ref),
          onPressed: takes && !_isExporting
              ? () => _editCelDelta(
                  cut.id,
                  (delta) => delta.withDirectionOver(
                    shown.ref,
                    direction.ref,
                    !laid.contains(direction.ref),
                  ),
                )
              : null,
        ),
    ];
  }

  /// The cut the list shows, as a popover of the cuts the plan lists
  /// drawings for.
  ///
  /// 🗣️유저 2026-09-22 (F-177): 「범위를 프로젝트로 설정시 미리보기 셀 출력
  /// 리스트가 모든 컷 합쳐서 레이어들 보여주는데, 그게아니라 컷 리스트가 있고,
  /// 팝오버로 컷 선택하면 밑에 셀 리스트? 보여주게하도록」 — and the shape
  /// chosen on the board (cel-export-project-list, 09-23): a button at the
  /// head of the list, the list showing the picked cut alone.
  ///
  /// Present under the cut scope too, shut: one cut has nothing to pick,
  /// and a button that appeared with the scope would be UI that pops into
  /// existence. Labelled the way the scope grid labels a cut (a 겸용 group
  /// by its joined name — it exports once, as one cut).
  Widget _celCutPicker(ExportCelGroupPlan plan, Cut shown) {
    final project = _session.repository.requireProject();
    final cuts = _celListCuts(plan);
    return PanelFlyoutButton(
      key: const ValueKey<String>('export-cels-cut-picker'),
      label: celGroupCutName(project, shown),
      enabled: cuts.length > 1 && !_isExporting,
      entriesBuilder: () => cuts.asFlyoutValueChoices(
        current: cuts.where((cut) => cut.id == shown.id).firstOrNull,
        choiceOf: (cut) => PanelFlyoutChoice(
          key: 'export-cels-cut-${cut.id.value}',
          label: celGroupCutName(project, cut),
        ),
        onPicked: (cut) {
          setState(() => _celListCut = cut.id);
          _settleStanding();
        },
      ),
    );
  }

  /// The cuts [plan] lists drawings for, in the order the export walks
  /// them.
  List<Cut> _celListCuts(ExportCelGroupPlan plan) {
    final listed = {for (final sheet in plan.sheets) sheet.cut.id};
    return [
      for (final cut in resolveExportCuts(
        project: _session.repository.requireProject(),
        activeCutId: _activeCut.id,
        range: ExportRange.allCuts,
      ))
        if (listed.contains(cut.id)) cut,
    ];
  }

  /// The cut the list shows: the one picked while the plan still lists it,
  /// the cut the window opened on while it does, and the first the plan
  /// lists otherwise (the project scope walks a 겸용 group from its first
  /// cut, which need not be the one stood on).
  Cut _celCutShown(ExportCelGroupPlan plan) {
    final cuts = _celListCuts(plan);
    for (final wanted in [_celListCut, _activeCut.id]) {
      for (final cut in cuts) {
        if (cut.id == wanted) {
          return cut;
        }
      }
    }
    return cuts.firstOrNull ?? _activeCut;
  }

  // --- plans ----------------------------------------------------------------

  Cut get _activeCut => _anchorCut!;

  /// The FULL sequence axis (untrimmed, gapless): what the transport runs
  /// over and the in/out marks live on (cut-local frames under the cut
  /// scope, whole-track positions under the project scope).
  ///
  /// Memoized on what it reads — the project and the scope: the preview's
  /// document, its range and its name plate each ask for it every build,
  /// and a preview that runs builds a frame at a time.
  List<ExportFrameTask> _sequenceAxisPlan() {
    final project = _session.repository.requireProject();
    final scope = _specs.sequence.scope;
    final cached = _sequenceAxisCache;
    if (cached != null && identical(cached.$1, project) && cached.$2 == scope) {
      return cached.$3;
    }
    final plan = buildExportFramePlan(
      project: project,
      activeCutId: _activeCut.id,
      range: scope == ExportScopeKind.project
          ? ExportRange.allCuts
          : ExportRange.activeCut,
    );
    _sequenceAxisCache = (project, scope, plan);
    return plan;
  }

  (Object, ExportScopeKind, List<ExportFrameTask>)? _sequenceAxisCache;

  /// The frames an export actually renders: the axis sliced by in/out. An
  /// UNTRIMMED project-scope video keeps the gap black frames (full-track
  /// sync, the old behavior); a trimmed range is content-only.
  List<ExportFrameTask> _sequencePlanForRun({required bool video}) {
    final spec = _specs.sequence;
    final SequenceExportSpec(:inFrame, :outFrame) = spec;
    final untrimmed = inFrame == null && outFrame == null;
    if (video && untrimmed && spec.scope == ExportScopeKind.project) {
      return buildExportFramePlan(
        project: _session.repository.requireProject(),
        activeCutId: _activeCut.id,
        range: ExportRange.allCuts,
        includeGaps: true,
      );
    }
    final axis = _sequenceAxisPlan();
    if (axis.isEmpty) {
      return axis;
    }
    final kept = KeptSpan(
      length: axis.length,
      inFrame: inFrame,
      outFrame: outFrame,
    );
    return axis.sublist(kept.first, kept.last + 1);
  }

  ExportProjectOverrides get _overrides =>
      _session.repository.requireProject().exportOverrides;

  /// The Cels tab's label-group plan (v10: 파일 = 라벨×셀번호 1장,
  /// 기준+어태치 합성) — rules, then the per-cut manual delta, then the
  /// project-side cut checks.
  ///
  /// Memoized on what it reads — the project (what the hand did to a cut's
  /// list is the project's) and the spec: the board, the preview, the
  /// headline and the lines under the picture each ask for it every build.
  ExportCelGroupPlan _celGroupPlan() {
    final spec = _specs.cels;
    final project = _session.repository.requireProject();
    final cached = _celPlanCache;
    if (cached != null && identical(cached.$1, project) && cached.$2 == spec) {
      return cached.$3;
    }
    final plan = buildExportCelGroupPlan(
      project: project,
      activeCutId: _activeCut.id,
      spec: spec,
      overrides: _overrides,
      fileExtension: spec.format.stillFormat.fileExtension,
      sheetPagesOf: _sheetPagesOf,
    );
    _celPlanCache = (project, spec, plan);
    return plan;
  }

  (Object, CelsExportSpec, ExportCelGroupPlan)? _celPlanCache;

  AppLanguage get _notationLanguage =>
      _session.languageSettings.value.notationLanguage;

  TimesheetWords get _sheetWords => timesheetWordsIn(_notationLanguage);

  ConteWords get _conteWords => conteWordsIn(_notationLanguage);

  /// The app's face the documents export in — this window's, which is the
  /// panels' (documents-in-which-face-Q1). Read before a render is queued:
  /// the render may run after the window has closed.
  TextStyle get _documentFace => appFaceOf(DefaultTextStyle.of(context).style);

  /// The cut's start on the TRACK axis (gaps included) — the SE column
  /// reads track-global spans, so the sheet needs the true origin.
  int _trackStartOf(Cut target) {
    for (final placed in cutSpansOfCuts(
      resolveExportCuts(
        project: _session.repository.requireProject(),
        activeCutId: _activeCut.id,
        range: ExportRange.allCuts,
      ),
    )) {
      if (placed.cut.id == target.id) {
        return placed.startFrame;
      }
    }
    return 0;
  }

  (Cut, TimesheetDocument, TimesheetDocumentLayout) _sheetDocFor(Cut cut) {
    final cached = _sheetDocs[cut.id];
    if (cached != null && identical(cached.$1, cut)) {
      return cached;
    }
    final document = cutSheetDocument(
      _session,
      cut: cut,
      cutStartFrame: _trackStartOf(cut),
    );
    final layout = TimesheetDocumentLayout(document: document);
    final entry = (cut, document, layout);
    _sheetDocs[cut.id] = entry;
    return entry;
  }

  /// How many pages [cut]'s timesheet stands on — the plan lists a file a
  /// page ([buildExportCelGroupPlan]).
  int _sheetPagesOf(Cut cut) => _sheetDocFor(cut).$2.pages.length;

  /// The page of its cut's timesheet [sheet] is, as the page renderer takes
  /// it. The sheet's digital file has no picture of its own: its block
  /// shows the sheet's first page.
  ExportTimesheetPageTask _sheetPageTask(ExportDocumentSheet sheet) =>
      ExportTimesheetPageTask(
        cut: sheet.of,
        cutLabel: sheet.of.name,
        cutStartFrame: _trackStartOf(sheet.of),
        pageIndex: sheet.page,
        pageCount: _sheetPagesOf(sheet.of),
        fileName: sheet.fileName,
      );

  /// The conte sheet, laid out — pages the plan/preview/nav all read.
  (ConteSheetSource, List<ContePageLayout>) _conteSheet() {
    final project = _session.repository.requireProject();
    final cached = _conteSheetCache;
    if (cached != null && identical(cached.$1, project)) {
      return (cached.$2, cached.$3);
    }
    final source = buildConteSheetSource(project);
    final pages = layoutConteBook(
      source,
      metrics: ConteSheetMetrics(cameraAspect: _session.camera.cameraFrameAspect),
    );
    _conteSheetCache = (project, source, pages);
    return (source, pages);
  }

  String _contePageFileName(int index, int pageCount) {
    final extension = _specs.conte.image.stillFormat.fileExtension;
    final name = _typedName(_conteFileController);
    return pageCount == 1
        ? '$name.$extension'
        : '${name}_p${index + 1}.$extension';
  }

  /// The cut envelope [sheet] is, laid out on the paper the tab's format
  /// names ([CelsExportSpec.envelopePaper]): the sheet belongs to its
  /// owner, whose canvas sizes the cut-fitted paper.
  ExportEnvelopeTask _envelopeTask(ExportDocumentSheet sheet) {
    final project = _session.repository.requireProject();
    final paper = cutEnvelopePaperSize(
      mode: _specs.cels.envelopePaper,
      cut: sheet.of,
    );
    return ExportEnvelopeTask(
      owner: sheet.of,
      layout: CutEnvelopeLayout.fit(
        // The work's form, the one the panel shows (유저 답
        // envelope-form-in-export: the export follows it).
        form: CutEnvelopePresets.byId(project.timesheetInfo.envelopeFormId),
        paperWidth: paper.width.toDouble(),
        paperHeight: paper.height.toDouble(),
      ),
      source: buildCutEnvelopeSource(project: project, cut: sheet.of),
    );
  }

  /// Every sheet's saved ink for [keys], each composed from the session
  /// store its namespace names ([RenderCaches.sheetInkStoreFor]). Caller
  /// disposes the images.
  ///
  /// ⛔ONE for the three sheets: the conte and the envelope each composed
  /// their own, and the timesheet's would have been the third.
  ///
  /// The ink is read as a LOOK, like every render's cel ([CelRead.look]):
  /// a sheet nobody has open keeps its ink parked.
  Future<Map<BrushFrameKey, ui.Image>> _renderSheetInk(
    Iterable<BrushFrameKey> keys,
  ) async {
    final caches = _session.renderCaches;
    final images = <BrushFrameKey, ui.Image>{};
    for (final key in keys) {
      if (images.containsKey(key)) {
        continue;
      }
      final surface = caches
          .sheetInkStoreFor(key)
          ?.bakedSurfaceOrNull(key, read: CelRead.look);
      if (surface == null) {
        continue;
      }
      final image = await composeTiledSurfaceImage(
        surface,
        reuse: BitmapTileImageCache.instance,
        // An export's own render: the run waits for it.
        missing: MissingTilePictures.madeAtOnce,
      );
      if (image != null) {
        images[key] = image;
      }
    }
    return images;
  }

  /// One envelope image — every stratum of the sheet — with the ink
  /// composed and freed around it.
  ///
  /// ⛔THE EXPORT AND THE PREVIEW RENDER THROUGH HERE. They differ only in
  /// [outputSize] (the preview fits its pane); rendered separately, the
  /// preview showed a picture the file would not have been.
  Future<ui.Image> _renderEnvelope(
    ExportEnvelopeTask task, {
    required TextStyle face,
    ({int width, int height})? outputSize,
  }) async {
    final ink = await _renderSheetInk([
      for (final window in envelopeInkWindows(task.layout, task.owner.id))
        window.key,
    ]);
    try {
      return await renderCutEnvelopeImage(
        layout: task.layout,
        source: task.source,
        face: face,
        inkOwner: task.owner.id,
        inkImageFor: (key) => ink[key],
        outputSize: outputSize,
      );
    } finally {
      for (final image in ink.values) {
        image.dispose();
      }
    }
  }

  /// One timesheet page with its saved ink composed and freed around it —
  /// the preview's and the page-image export's one routine; they differ
  /// only in [outputSize] (the preview fits its pane, the file is the page
  /// at its paper's own pixels).
  ///
  /// The ink is the page's windows of the panel's own walk
  /// ([timesheetInkWindows]) — until 2026-09-26 the timesheet exported no
  /// ink at all (유저: 「다 통일해줘. 기능은 어차피 생길수있어」).
  Future<ui.Image> _renderSheetPage(
    ExportTimesheetPageTask task, {
    required TextStyle face,
    CanvasSize? outputSize,
  }) async {
    final (_, document, layout) = _sheetDocFor(task.cut);
    final page = layout.pageRect(task.pageIndex);
    final windows = [
      for (final window in timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: task.cut.id,
      ))
        if (window.documentRect.overlaps(page)) window.mark,
    ];
    final ink = await _renderSheetInk([for (final w in windows) w.key]);
    try {
      return await renderTimesheetPageImage(
        document: document,
        layout: layout,
        pageIndex: task.pageIndex,
        words: _sheetWords,
        face: face,
        outputSize: outputSize,
        ink: (windows: windows, imageFor: (key) => ink[key]),
      );
    } finally {
      for (final image in ink.values) {
        image.dispose();
      }
    }
  }

  /// The conte ink rasters for [pages] (R5): the page plane plus each
  /// cell's row band — the windows the page prints them through
  /// ([conteInkMarks]), which this used to walk once more for itself.
  /// Caller disposes the images.
  Future<Map<BrushFrameKey, ui.Image>> _renderConteInk(
    List<ContePageLayout> pages,
  ) => _renderSheetInk([
    for (final page in pages)
      for (final ink in conteInkMarks(page, page.metrics)) ink.key,
  ]);

  Cut? _conteCutById(String cutId) {
    for (final track in _session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id.value == cutId) {
          return cut;
        }
      }
    }
    return null;
  }

  /// Renders each cell picture the conte [pages] name, once — a window's
  /// [width] wide ([contePictureRenderWidth]) — fresh composites straight from
  /// the brush store (the storyboard thumbnail rule: the cache is
  /// panel-resolution, an export re-renders). [have] says which keys the
  /// caller already holds, and [take] receives each image and owns it from
  /// then on.
  ///
  /// ⛔ONE WALK FOR BOTH CONTE EXPORTS. The sheets and the PDF each wrote
  /// out the page/cell nesting, the (cut, frame) dedupe key, the cancel
  /// check and the missing-cut skip; the picture a cell names is one
  /// question, and asking it twice is how one exporter starts framing a
  /// different picture than the other.
  Future<void> _forEachContePicture(
    List<ContePageLayout> pages, {
    required int width,
    required bool Function(SheetPictureKey key) have,
    required Future<void> Function(SheetPictureKey key, ui.Image image) take,
  }) async {
    _contePictureSize = _session.camera.cameraFrameSize.scaledToWidth(width);
    final renderer = ExportFrameRenderer(session: _session);
    for (final page in pages) {
      for (final cell in page.cells) {
        final picture = contePictureOf(cell, page.metrics);
        final key = picture.key;
        if (have(key) || _cancelRequested) {
          continue;
        }
        final cut = _conteCutById(cell.cutId);
        if (cut == null) {
          continue;
        }
        await take(
          key,
          await renderer.renderPicture(
            cut,
            picture.pictureFrame,
            width: contePictureRenderWidth(picture, page.metrics, width),
            region: picture.canvasRegion,
          ),
        );
      }
    }
  }


  /// One conte page rendered with its cell pictures and sheet ink alive
  /// for exactly that render and disposed after — the preview's and the
  /// page-image export's one routine; they differ only in the values they
  /// pass ([pictureWidth], and [outputSize] for a fitted preview against
  /// [scale] for a run — both already [renderContePageImage]'s own).
  Future<ui.Image> _renderContePage(
    ContePageLayout page,
    ConteSheetSource source, {
    required int pictureWidth,
    CanvasSize? outputSize,
    required ConteWords words,
  }) async {
    final pictures = await _renderContePictures([page], width: pictureWidth);
    final ink = await _renderConteInk([page]);
    final images = await readContePageImages([page], source, words);
    try {
      return await renderContePageImage(
        page: page,
        source: source,
        pictureFor: (picture, _) => pictures[picture.key],
        imageFor: (path) => images[path],
        inkImageFor: (key) => ink[key],
        picturesOverInk: contePicturesOverInkIn(_session, page),
        outputSize: outputSize,
        words: words,
      );
    } finally {
      for (final image in [
        ...pictures.values,
        ...ink.values,
        ...images.values,
      ]) {
        image.dispose();
      }
    }
  }

  /// Renders every cell's picture once, a window's [width] wide.
  Future<Map<SheetPictureKey, ui.Image>> _renderContePictures(
    List<ContePageLayout> pages, {
    required int width,
  }) async {
    final images = <SheetPictureKey, ui.Image>{};
    try {
      await _forEachContePicture(
        pages,
        width: width,
        have: images.containsKey,
        take: (key, image) async => images[key] = image,
      );
    } on Object {
      // A failed render must not strand the ones already made.
      for (final image in images.values) {
        image.dispose();
      }
      rethrow;
    }
    return images;
  }

  Set<CanvasSize> _scopeCanvasSizes(ExportScopeKind scope) {
    return resolveExportCuts(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      range: scope == ExportScopeKind.project
          ? ExportRange.allCuts
          : ExportRange.activeCut,
    ).map((cut) => cut.canvasSize).toSet();
  }

  /// The Image tab's frame: the transport owns it (seeded from the editing
  /// playhead on open) — what the preview shows IS what exports.
  int _currentImageFrame() {
    final duration = math.max(1, _activeCut.duration);
    return _imageFrame.clamp(0, duration - 1);
  }

  @visibleForTesting
  int get debugImageFrame => _currentImageFrame();

  /// Test seam: the live tab specs (scope defaults, formats).
  @visibleForTesting
  ExportTabSpecs get debugSpecs => _specs;

  /// Test seam: the size the conte's cell pictures were last rendered at —
  /// what a page-image run asks, which its PNG files cannot tell a test.
  @visibleForTesting
  CanvasSize? get debugContePictureSize => _contePictureSize;
  CanvasSize? _contePictureSize;

  String _sequenceFileNameFor(int index) {
    final naming = _specs.sequence.naming;
    final number = '${index + 1}'.padLeft(naming.digits, '0');
    final extension = _specs.sequence.format.stillFormat.fileExtension;
    return '${naming.baseName}_$number.$extension';
  }

  /// The two sentences EVERY export ends with. Six routines wrote the
  /// cancelled one out and four the finished one, which is how one of them
  /// came to count files while it named frames — so the wording, and the
  /// pluralisation that goes with it, lives here once.
  ///
  /// ↩️The wording lives in the string tables now (F-124, 2026-09-16), and a
  /// count arrives already said with its noun: the `_plural` that stood here
  /// glued an English `s` onto every noun, which no other language can say.
  String _exportCancelled(String kept) =>
      AppText.strings.exCancelledAfter(kept);

  String _exportDone(String written, {int skipped = 0}) => skipped > 0
      ? AppText.strings.exDoneSkipped(written, skipped)
      : AppText.strings.exDone(written);

  // --- preview: the file each tab would write, as a document ----------------

  /// The file the tab stood on would write, as the document its preview
  /// shows ([ExportPreviewPanel]) — or null while it has nothing to write.
  ///
  /// ⚠️THE SWITCH STAYS A SWITCH. Several questions in this window dispatch
  /// on [_tab] and a tab-shaped object would gather them — but the set of
  /// tabs is the product's closed list, and Dart's exhaustive switch already
  /// refuses to compile until a new one is answered EVERYWHERE.
  ExportPreviewDocument? _previewDocument() => switch (_tab) {
    ExportTab.sequence => _sequencePreview(),
    ExportTab.image => _imagePreview(),
    ExportTab.cels => _celsPreview(),
    ExportTab.conte => _contePreview(),
  };

  /// The page of it the window stands on.
  int _previewPage() => switch (_tab) {
    ExportTab.sequence => _sequencePosition,
    ExportTab.image => _currentImageFrame(),
    ExportTab.cels => math.max(0, _celPages().at),
    ExportTab.conte => _contePosition,
  };

  /// The preview moved to [page] — a hand on its transport or its page
  /// cluster, or its run. (A row's drawings are turned by the list's band:
  /// [_stepCel].)
  void _turnPreviewTo(int page) => setState(() {
    switch (_tab) {
      case ExportTab.sequence:
        _sequencePosition = page;
      case ExportTab.image:
        _imageFrame = page;
      case ExportTab.conte:
        _contePosition = page;
      case ExportTab.cels:
        break;
    }
  });

  /// The pixels a frame of [cut] is written at under [mode].
  CanvasSize _frameSizeOf(Cut cut, ExportSizeMode mode) =>
      mode == ExportSizeMode.camera
      ? _session.camera.cameraFrameSize
      : cut.canvasSize;

  /// The project's rate, for a preview that runs.
  double get _previewRate => _session.projectSettings.projectFps.toDouble();

  ExportPreviewDocument? _sequencePreview() {
    final spec = _specs.sequence;
    final axis = _sequenceAxisPlan();
    if (axis.isEmpty) {
      return null;
    }
    final format = spec.format;
    final renderer = _previewRendererFor(
      applyLayerFx: spec.applyLayerFx,
      format: format,
    );
    // The video run burns the SE name tags in (renderCompositeForVideo);
    // stills stay clean because they are compositing sources. The preview
    // has to answer the same question, or it shows a frame the export
    // will not produce.
    final withNameTags = format.kind == ExportMediaKind.video;
    return ExportPreviewDocument(
      subject: (ExportTab.sequence, spec.scope),
      look: (
        spec.sizeMode,
        spec.applyLayerFx,
        _groundKeyOf(format),
        withNameTags,
      ),
      shape: ExportPreviewShape.runs,
      framesPerSecond: _previewRate,
      pageCount: axis.length,
      opensAlpha: format.wantsAlpha,
      sizeOf: (page) => _frameSizeOf(axis[page].cut, spec.sizeMode),
      renderAt: (page, size) async => axis[page].isGap
          ? null
          : await renderer.renderComposite(
              axis[page],
              spec.sizeMode,
              outputSize: size,
              withNameTags: withNameTags,
            ),
    );
  }

  /// The Image tab's cut, frame by frame: what the transport stands on IS
  /// the frame that is written.
  ExportPreviewDocument _imagePreview() {
    final spec = _specs.image;
    final cut = _activeCut;
    final renderer = _previewRendererFor(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    return ExportPreviewDocument(
      subject: ExportTab.image,
      look: (spec.sizeMode, spec.applyLayerFx, _groundKeyOf(spec.format)),
      shape: ExportPreviewShape.runs,
      framesPerSecond: _previewRate,
      pageCount: math.max(1, cut.duration),
      opensAlpha: spec.format.wantsAlpha,
      sizeOf: (_) => _frameSizeOf(cut, spec.sizeMode),
      renderAt: (page, size) => renderer.renderComposite(
        ExportFrameTask(cut: cut, frameIndex: page),
        spec.sizeMode,
        outputSize: size,
      ),
    );
  }

  /// The row the Cels list stands on, as the drawings it turns through —
  /// each of them ONE picture ([ExportPreviewShape.single]): a cel is a file
  /// of its own, and the list's band is what turns from one to the next.
  ExportPreviewDocument? _celsPreview() {
    final (:cut, :pages, at: _) = _celPages();
    if (pages.isEmpty) {
      return null;
    }
    final face = _documentFace;
    final pictures = [for (final sheet in pages) _sheetPicture(sheet, face)];
    return ExportPreviewDocument(
      subject: (ExportTab.cels, cut.id),
      // Every setting that changes a picture is in its look: two papers of
      // the same cut must not share a render.
      look: [for (final picture in pictures) picture.look].join('\n'),
      shape: ExportPreviewShape.single,
      pageCount: pages.length,
      // A cel is open where its format says; a document is its paper.
      opensAlpha:
          _specs.cels.format.wantsAlpha && pages.first is ExportCelSheet,
      sizeOf: (page) => pictures[page].size,
      renderAt: (page, size) => pictures[page].render(size),
    );
  }

  /// The drawings the row stood on turns through, where the one shown
  /// stands among them (-1 while none is), and the cut the list shows.
  ({Cut cut, List<ExportListSheet> pages, int at}) _celPages() {
    final (plan: _, :cut, :rows, :standing) = _celsList();
    final row = standing.rowIn(rows);
    final pages = row == null
        ? const <ExportListSheet>[]
        : exportCelsPages(row);
    return (
      cut: cut,
      pages: pages,
      at: pages.indexWhere((sheet) => sheet.idValue == standing.shown),
    );
  }

  /// [sheet] as a picture: the pixels its file is written at, what decides
  /// how it looks, and its render at a size — the very render the run
  /// writes it through.
  ///
  /// ONE place tells a cel from a timesheet's page from a cut envelope: the
  /// three answers were each a walk over the same question.
  ({
    CanvasSize size,
    String look,
    Future<ui.Image?> Function(CanvasSize size) render,
  })
  _sheetPicture(ExportListSheet sheet, TextStyle face) {
    final spec = _specs.cels;
    if (sheet is ExportCelSheet) {
      final renderer = _previewRendererFor(
        // The preview shows what the export writes — same switch.
        applyLayerFx: spec.applyLayerFx,
        format: spec.format,
      );
      return (
        size: _frameSizeOf(sheet.look.cut, spec.sizeMode),
        look: celGroupPreviewKey(
          sheet.look,
          sizeMode: spec.sizeMode.jsonValue,
          backgroundKey: _groundKeyOf(spec.format),
          applyLayerFx: spec.applyLayerFx,
        ),
        render: (size) => renderer.renderCelGroup(
          sheet.look,
          spec.sizeMode,
          outputSize: size,
        ),
      );
    }
    // What the list holds that is no drawing is a page of a document.
    final page = sheet as ExportDocumentSheet;
    final owner = page.of.id.value;
    if (page.kind == ExportCelKind.envelope) {
      final paper = cutEnvelopePaperSize(
        mode: spec.envelopePaper,
        cut: page.of,
      );
      final form = _session.repository
          .requireProject()
          .timesheetInfo
          .envelopeFormId;
      return (
        size: CanvasSize(width: paper.width, height: paper.height),
        look:
            'envelope:$owner:$form:${spec.envelopePaper.toJson()}:'
            '${face.fontFamily}',
        render: (size) => _renderEnvelope(
          _envelopeTask(page),
          face: face,
          outputSize: (width: size.width, height: size.height),
        ),
      );
    }
    return (
      size: _sheetDocFor(page.of).$3.paperPixelSize,
      look: 'sheet:$owner:${page.page}:${face.fontFamily}',
      render: (size) =>
          _renderSheetPage(_sheetPageTask(page), face: face, outputSize: size),
    );
  }

  /// The conte book, a page a page.
  ExportPreviewDocument? _contePreview() {
    final (source, pages) = _conteSheet();
    if (pages.isEmpty) {
      return null;
    }
    // The printed words are part of the look: switching the notation
    // language must not show the other language's page.
    final language = _notationLanguage;
    final words = conteWordsIn(language);
    final camera = _session.camera.cameraFrameSize;
    return ExportPreviewDocument(
      subject: ExportTab.conte,
      look: language,
      shape: ExportPreviewShape.book,
      pageCount: pages.length,
      sizeOf: (page) => pages[page].metrics.paperPixelSize,
      renderAt: (page, size) => _renderContePage(
        pages[page],
        source,
        // A cell's picture at the share of its own pixels the page is drawn
        // at — the run's are the camera's, on a page at its paper's pixels.
        pictureWidth: math.max(
          1,
          (camera.width *
                  size.width /
                  pages[page].metrics.paperPixelSize.width)
              .round(),
        ),
        outputSize: size,
        words: words,
      ),
    );
  }

  /// The span IN/OUT keep on the sequence axis, as the transport's range row
  /// holds it. An end at its own end of the axis is no trim at all — the
  /// untrimmed run is the one that keeps a project's gaps
  /// ([_sequencePlanForRun]).
  TransportRange _sequenceRange() {
    final spec = _specs.sequence;
    final length = _sequenceAxisPlan().length;
    final kept = KeptSpan(
      length: math.max(1, length),
      inFrame: spec.inFrame,
      outFrame: spec.outFrame,
    );
    return TransportRange(
      inFrame: kept.first,
      outFrame: kept.last,
      onChanged: length > 1 && !_isExporting
          ? (start, end) => _updateSpec(
              spec.copyWith(
                inFrame: start <= 0 ? null : start,
                outFrame: end >= length - 1 ? null : end,
              ),
            )
          : null,
    );
  }

  /// The name the page under preview is written under — and whether it
  /// names a picture the run does NOT write, which the plate says in the
  /// ink of what is off ([ExportPreviewPanel.fileAbsent]).
  ({String? name, bool absent}) _previewFile() {
    switch (_tab) {
      case ExportTab.sequence:
        final spec = _specs.sequence;
        if (spec.format.isVideo) {
          return (name: _firstOutputFile().name, absent: false);
        }
        final length = _sequenceAxisPlan().length;
        if (length == 0) {
          return (name: null, absent: false);
        }
        final page = _sequencePosition.clamp(0, length - 1);
        final kept = KeptSpan(
          length: length,
          inFrame: spec.inFrame,
          outFrame: spec.outFrame,
        );
        // Stills are numbered through the frames IN/OUT keep. A frame
        // outside them is no file: it says which frame it is.
        return page < kept.first || page > kept.last
            ? (name: 'F${page + 1}', absent: true)
            : (name: _sequenceFileNameFor(page - kept.first), absent: false);
      case ExportTab.image:
        return (name: _firstOutputFile().name, absent: false);
      case ExportTab.cels:
        final (cut: _, :pages, :at) = _celPages();
        if (at < 0) {
          return (name: null, absent: false);
        }
        // The file exactly as the naming rule will write it, extension
        // included (유저 2026-09-09: 「이름 규칙같은거에서 적용된걸 그대로 …
        // A0001.png 이런식으로 확장자까지」) — and one that is no file by its
        // whole name.
        final sheet = pages[at];
        return sheet.fileName.isNotEmpty
            ? (name: sheet.fileName, absent: false)
            : (name: sheet.fullName, absent: true);
      case ExportTab.conte:
        final (_, pages) = _conteSheet();
        if (pages.isEmpty) {
          return (name: null, absent: false);
        }
        return (
          name: _specs.conte.format == ExportConteFormat.pdf
              ? _firstOutputFile().name
              : _contePageFileName(
                  _contePosition.clamp(0, pages.length - 1),
                  pages.length,
                ),
          absent: false,
        );
    }
  }

  /// Settles where the window stands after a change: a row that left the
  /// Cels list, or a drawing that was turned off, is not kept stood on
  /// behind the board's back — the nearest one left is, and it STAYS stood
  /// on (유저 2026-10-06: 「서있는 상태나 마찬가지지」).
  void _settleStanding() {
    if (_tab == ExportTab.cels) {
      _celStanding = _celsList().standing;
    }
  }

  // --- summaries ------------------------------------------------------------

  /// THE FIRST FILE THIS TAB WRITES, and whether more follow.
  ///
  /// 🚨ONE ANSWER FOR TWO SURFACES (감사 2026-09-09). The preview's name
  /// plate and the naming accordion's summary both say 「what comes out」,
  /// and each used to work it out for itself — the same walk over the
  /// same plan, written twice. They had already drifted apart in three
  /// places, and one of them was a LIE: the summary printed a hardcoded
  /// `CUT1.xdts` for every project, whatever the cut was called. (The other
  /// two: the summary showed nothing at all on the Image tab, and showed
  /// the numbered still name while the Sequence tab was set to video.)
  ///
  /// ⛔The SHAPING stays with each caller — the arrow, the ellipsis, the
  /// empty word. Only the question 「which file」 is answered here.
  ({String? name, bool more}) _firstOutputFile() {
    if (_tab == ExportTab.conte && _conteSheet().$2.isEmpty) {
      return (name: null, more: false);
    }
    final lone = _loneFile();
    if (lone != null) {
      return (
        name: _singleFileName(lone.controller, lone.extension),
        more: false,
      );
    }
    switch (_tab) {
      case ExportTab.cels:
        final written = _celGroupPlan().writtenFileNames;
        return (name: written.firstOrNull, more: written.length > 1);
      case ExportTab.conte:
        final pages = _conteSheet().$2.length;
        return (name: _contePageFileName(0, pages), more: pages > 1);
      case ExportTab.sequence || ExportTab.image:
        // What is left once the lone files are answered: numbered stills.
        return (name: _sequenceFileNameFor(0), more: true);
    }
  }

  /// What the two surfaces say when the tab writes nothing — the cel tab
  /// counts cels, every other tab counts cuts.
  String _nothingToWriteText() => _tab == ExportTab.cels
      ? AppText.strings.exNoCels
      : AppText.strings.exNoCuts;

  static const List<String> _knownExtensions = [
    '.mp4',
    '.mov',
    '.png',
    '.jpg',
    '.psd',
    '.pdf',
  ];

  /// [name] less a format's extension written after it.
  static String _withoutKnownExtension(String name) {
    final lower = name.toLowerCase();
    for (final known in _knownExtensions) {
      if (lower.endsWith(known)) {
        return name.substring(0, name.length - known.length);
      }
    }
    return name;
  }

  /// The name typed for a lone file — the project's while the field is
  /// empty. An extension typed after it is not part of it: the format names
  /// the extension, so a stale one swaps instead of stacking (`name.mp4` +
  /// MOV → `name.mov`, never `name.mp4.mov`).
  String _typedName(TextEditingController controller) {
    final typed = controller.text.trim();
    return _withoutKnownExtension(
      typed.isEmpty
          ? sanitizeExportFileComponent(
              _session.repository.requireProject().name,
            )
          : typed,
    );
  }

  /// A lone file's name with the CURRENT format's extension.
  String _singleFileName(TextEditingController controller, String extension) =>
      '${_typedName(controller)}.$extension';

  /// Flattens un-premultiplied RGBA over the format's background and
  /// hands RGB24 to the native stb encoder. Null = no encoder (an older
  /// binary) — the file skips rather than lying.
  Future<List<int>?> _encodeJpgImage(
    ui.Image image,
    ExportFormatSelection format,
  ) async {
    final encoder = QaImageEncoder.instance;
    if (encoder == null) {
      return null;
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return null;
    }
    final rgba = data.buffer.asUint8List();
    final pixelCount = image.width * image.height;
    final rgb = Uint8List(pixelCount * 3);
    final bg = format.backgroundArgb;
    final bgR = argbRed(bg);
    final bgG = argbGreen(bg);
    final bgB = argbBlue(bg);
    for (var i = 0; i < pixelCount; i += 1) {
      final a = rgba[i * 4 + 3];
      if (a == 255) {
        rgb[i * 3] = rgba[i * 4];
        rgb[i * 3 + 1] = rgba[i * 4 + 1];
        rgb[i * 3 + 2] = rgba[i * 4 + 2];
      } else {
        rgb[i * 3] = (rgba[i * 4] * a + bgR * (255 - a)) ~/ 255;
        rgb[i * 3 + 1] = (rgba[i * 4 + 1] * a + bgG * (255 - a)) ~/ 255;
        rgb[i * 3 + 2] = (rgba[i * 4 + 2] * a + bgB * (255 - a)) ~/ 255;
      }
    }
    return encoder.encodeJpg(
      rgb: rgb,
      width: image.width,
      height: image.height,
      quality: format.jpgQuality,
    );
  }

  /// The still write-path override per format; null keeps the engine PNG.
  Future<List<int>?> Function(ui.Image image)? _stillEncodeFor(
    ExportFormatSelection format,
  ) {
    if (format.stillFormat != ExportStillFormat.jpg) {
      return null;
    }
    return (image) => _encodeJpgImage(image, format);
  }

  ExportFrameRenderer _runRenderer({
    required bool applyLayerFx,
    required ExportFormatSelection format,
    bool alphaVideo = false,
  }) => ExportFrameRenderer(
    session: _session,
    applyLayerFx: applyLayerFx,
    background: (alphaVideo || (format.isStill && format.wantsAlpha))
        ? const ui.Color(0x00000000)
        : format.isStill
        ? ui.Color(format.backgroundArgb)
        : const ui.Color(0xFFFFFFFF),
  );

  bool get _canExport => !_isExporting && _writesAnything;

  /// Whether this tab's run writes any file at all.
  bool get _writesAnything {
    switch (_tab) {
      case ExportTab.sequence:
        return _sequencePlanForRun(
          video: _specs.sequence.format.isVideo,
        ).isNotEmpty;
      case ExportTab.image:
        return true;
      case ExportTab.cels:
        return _celGroupPlan().length > 0;
      case ExportTab.conte:
        return _conteSheet().$2.isNotEmpty;
    }
  }

  // --- export runners -------------------------------------------------------

  /// Where the run writes the file a rule or a field calls [name]: under
  /// that name in [_outputDirectory] — or, for the lone file of a run asked
  /// a place of its own, at that place whatever it was to be called.
  String _joinLocation(String name) =>
      _placedFile ?? '$_outputDirectory${Platform.pathSeparator}$name';

  void _reportProgress(int completed, int total) {
    if (mounted) {
      _progress.value = (
        end: total <= 0 ? 0 : completed * _barPixels ~/ total,
        of: _barPixels,
      );
    }
    final jobId = _activeJobId;
    if (jobId != null) {
      _queue.update(
        jobId,
        (job) => job.copyWith(completed: completed, total: total),
      );
    }
  }

  Future<void> _runGuarded(Future<String> Function() run) async {
    setState(() {
      _isExporting = true;
      _cancelRequested = false;
    });
    try {
      final message = await run();
      if (mounted) {
        setState(() => _statusMessage = message);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusMessage = AppText.strings.exFailed(error));
      }
    } finally {
      if (mounted) {
        _progress.value = null;
        setState(() => _isExporting = false);
      }
    }
  }

  /// [run] where the destination sends it: into [_location] — its lone file
  /// at the place it was asked ([_placedFile]) — or, handing over, into an
  /// outbox of its own, answered with the run's sentence so the caller
  /// hands the outbox over when its time comes (at once for Export, after
  /// the last job for the queue). A run that was stopped or failed leaves
  /// nothing to hand over.
  Future<({String message, String? outbox})> _runIntoDestination(
    Future<String> Function() run,
  ) async {
    if (_destination is! ExportHandOver) {
      return (message: await run(), outbox: null);
    }
    final outbox = _freshOutbox();
    _runOutbox = outbox;
    try {
      final message = await run();
      if (_cancelRequested) {
        _discardOutboxes([outbox]);
        return (message: message, outbox: null);
      }
      return (message: message, outbox: outbox);
    } on Object {
      _discardOutboxes([outbox]);
      rethrow;
    } finally {
      _runOutbox = null;
    }
  }

  String _freshOutbox() {
    final outbox =
        '${SessionScratch.outboxFolder()}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}';
    Directory(outbox).createSync(recursive: true);
    return outbox;
  }

  /// Hands everything the [outboxes] hold to the user in ONE window
  /// ([handOverFilesForUser]), and answers the sentence the run ends on
  /// when the hand-over changed it — declined, or failed on the way — or
  /// null when the run's own sentence stands. Export and the queue end
  /// their runs through it alike.
  ///
  /// What was handed over is gone from the room afterwards — and so is
  /// what the user declined or what failed to arrive: nothing asks for it
  /// again.
  Future<String?> _handOverOutboxes(List<String> outboxes) async {
    try {
      final outputs = [
        for (final outbox in outboxes)
          for (final entry in Directory(outbox).listSync()) entry.path,
      ];
      if (outputs.isEmpty || !mounted) {
        return null;
      }
      final handed = await handOverFilesForUser(context, paths: outputs);
      return handed == HandOver.declined
          ? AppText.strings.exHandOverDeclined
          : null;
    } on Object catch (error) {
      return AppText.strings.exFailed(error);
    } finally {
      _discardOutboxes(outboxes);
    }
  }

  void _discardOutboxes(List<String> outboxes) {
    for (final outbox in outboxes) {
      try {
        Directory(outbox).deleteSync(recursive: true);
      } on FileSystemException {
        // The room goes with the run.
      }
    }
  }

  /// The CURRENT tab's export, as one message-returning run — the Export
  /// button wraps it in the guard, the queue runner drives it per job.
  Future<String> _runCurrentTabExport() {
    switch (_tab) {
      case ExportTab.sequence:
        return _specs.sequence.format.isVideo
            ? _exportVideo()
            : _exportPngSequence();
      case ExportTab.image:
        return _exportCurrentFrame();
      case ExportTab.cels:
        return _exportCels();
      case ExportTab.conte:
        return _exportConte();
    }
  }

  /// Public for tests; the Export button is the production entry point.
  ///
  /// 🗣️F-221 (유저 2026-10-06): the place is asked when the button is
  /// pressed — 「어차피 내보내기누르면 OS창 뜨게하는 최종통일안으로 통일할거니
  /// 문제없어보임」 — before the files are made where the platform can ask
  /// then, and once they are made where it cannot ([_askWhere]).
  Future<void> export() async {
    if (!_canExport) {
      return;
    }
    final destination = await _askWhere();
    if (destination == null || !mounted) {
      return;
    }
    _takeDestination(destination);
    await _runGuarded(() async {
      final ran = await _runIntoDestination(_runCurrentTabExport);
      final outbox = ran.outbox;
      if (outbox == null) {
        return ran.message;
      }
      return await _handOverOutboxes([outbox]) ?? ran.message;
    });
  }

  // --- the render queue (EX7) -----------------------------------------------

  TextEditingController? _fileControllerFor(ExportTab tab) => switch (tab) {
    ExportTab.sequence => _sequenceFileController,
    ExportTab.image => _imageFileController,
    ExportTab.conte => _conteFileController,
    ExportTab.cels => null,
  };

  /// The LONE FILE this tab writes under a name typed for it — its field,
  /// and the extension its format gives it — or null for a tab that writes
  /// files a rule names.
  ///
  /// ONE answer to "is this a single named file": the first file's name,
  /// the name a queued job carries and whether a place is asked with one
  /// file in mind each worked it out for themselves.
  ({TextEditingController controller, String extension})? _loneFile() =>
      switch (_tab) {
        ExportTab.image => (
          controller: _imageFileController,
          extension: _specs.image.format.stillFormat.fileExtension,
        ),
        ExportTab.sequence when _specs.sequence.format.isVideo => (
          controller: _sequenceFileController,
          extension: _specs.sequence.format.container.fileExtension,
        ),
        ExportTab.conte when _specs.conte.format == ExportConteFormat.pdf => (
          controller: _conteFileController,
          extension: 'pdf',
        ),
        _ => null,
      };

  String? _singleFileNameForCurrentTab() {
    final lone = _loneFile();
    return lone == null
        ? null
        : _singleFileName(lone.controller, lone.extension);
  }

  /// Add to Queue: the current tab's spec and where it goes, frozen as a
  /// job. The picture renders at RUN time — the spec is the restorable part.
  ///
  /// The place is asked HERE, as Export asks it ([_askWhere]): a job that
  /// can be asked before its files are made is asked when it is queued, and
  /// one that cannot hands its outputs over once the queue has run
  /// ([runQueue]) — 🗣️유저 2026-10-06: 「ios처럼 퍼센테이지 이후에
  /// 위치저장하는 플랫폼만 큐가 끝날때 한번 위치 묻는건 어떻지?」.
  Future<void> addToQueue() async {
    if (!_canExport) {
      return;
    }
    final destination = await _askWhere();
    if (destination == null || !mounted) {
      return;
    }
    _queue.enqueue(
      spec: _specs.specFor(_tab),
      destination: destination,
      fileName: _singleFileNameForCurrentTab(),
    );
    _takeDestination(destination);
  }

  /// Puts [job]'s setup into the live form, so the window honestly shows
  /// what is about to render (or what is being edited).
  ///
  /// ⛔THE ONE PLACE A JOB BECOMES THE FORM. Editing a queued job and
  /// running the queue both land here; when they each wrote this out, a
  /// field added to a job reached one of them and silently rendered the
  /// other's stale value.
  void _loadJobIntoForm(ExportJob job) {
    setState(() {
      _tab = job.tab;
      _specs = _specs.withSpec(job.spec);
      _destination = job.destination;
      final controller = _fileControllerFor(job.tab);
      final fileName = job.fileName;
      if (controller != null && fileName != null) {
        controller.text = _withoutKnownExtension(fileName);
      }
      _syncControllersFromSpecs();
    });
  }

  /// A queued job clicked: its setup returns to the window for editing
  /// and the job leaves the queue (수정 후 재등록 — the v10 flow).
  void _restoreJob(ExportJob job) {
    if (job.status != ExportJobStatus.queued || _isExporting) {
      return;
    }
    _loadJobIntoForm(job);
    _queue.remove(job.id);
    _persist();
    _settleStanding();
  }

  void _removeJob(ExportJob job) {
    _queue.remove(job.id);
    setState(() {});
  }

  int? _activeJobId;

  /// Runs every queued job in order, loading each job's setup into the
  /// live state (the window honestly shows what renders). A failure marks
  /// the job and the runner CONTINUES (부분 실패); Cancel stops the
  /// current job and leaves the rest queued. The user's own setup returns
  /// when the queue rests.
  Future<void> runQueue() async {
    if (_isExporting || _queue.nextQueued == null) {
      return;
    }
    final snapshotTab = _tab;
    final snapshotSpecs = _specs;
    final snapshotDestination = _destination;
    setState(() {
      _isExporting = true;
      _cancelRequested = false;
    });
    var succeeded = 0;
    var failed = 0;
    // Every job that hands over leaves its outbox here, and they go to the
    // user in ONE window once the last job is done — a queue of five does
    // not ask five times where its outputs go.
    final outboxes = <String>[];
    String? handOverSaid;
    // Whether the queue ran at all: backing out of a window that asks a
    // place runs nothing, and says nothing — as it does for Export.
    var ran = false;
    try {
      ran = await _placesStillFit();
      while (ran && !_cancelRequested) {
        final job = _queue.nextQueued;
        if (job == null) {
          break;
        }
        final status = await _runQueuedJob(job, outboxes);
        if (status == ExportJobStatus.succeeded) {
          succeeded += 1;
        } else if (status == ExportJobStatus.failed) {
          failed += 1;
        }
      }
      if (outboxes.isNotEmpty) {
        handOverSaid = await _handOverOutboxes(outboxes);
      }
    } finally {
      _activeJobId = null;
      if (mounted) {
        _progress.value = null;
        setState(() {
          _isExporting = false;
          _tab = snapshotTab;
          _specs = snapshotSpecs;
          _destination = snapshotDestination;
          _syncControllersFromSpecs();
          if (ran) {
            _statusMessage =
                handOverSaid ?? _queueRestSentence(succeeded, failed);
          }
        });
        _persist();
        _settleStanding();
      }
    }
  }

  /// [모두 렌더] IS WHERE A QUEUED PLACE IS HELD AGAINST WHAT ITS JOB WRITES
  /// NOW (F-221, 저장 세션의 제안을 유저가 2026-10-06 「ok 문제없음」으로
  /// 받음: 「받아 둔 자리가 지금 장수와 안 맞게 된 작업만 그 자리에서 다시
  /// 묻는다」).
  ///
  /// A job is asked its place when it is queued and renders the project as
  /// it stands when it RUNS — and the cut and layer ticks are the
  /// project's, not the job's, so a job queued while it wrote one file can
  /// have come to write several. A file's place holds one. Those jobs, and
  /// only those, are asked again — each with its setup in the form, so the
  /// window shows which job is asking — before anything runs. A folder
  /// asked for several holds the one they became.
  ///
  /// False when the user backed out of a window: nothing runs, and a place
  /// already answered in this pass is kept.
  Future<bool> _placesStillFit() async {
    for (final job in _queue.jobs) {
      if (job.status != ExportJobStatus.queued ||
          job.destination is! ExportToFile) {
        continue;
      }
      _loadJobIntoForm(job);
      if (!_writesAnything || _loneOutputName() != null) {
        continue;
      }
      final destination = await _askWhere();
      if (destination == null || !mounted) {
        return false;
      }
      _queue.update(
        job.id,
        (current) => current.copyWith(destination: destination),
      );
      _takeDestination(destination);
    }
    return true;
  }

  /// Runs ONE queued job and returns the status it ended in — the same
  /// status the job itself now wears, so the runner counts what the queue
  /// shows. The job's setup goes into the live form first (the window
  /// honestly shows what renders).
  ///
  /// ⚠️A failure is caught HERE, which is what 부분 실패 means: the runner
  /// above never sees a throw and carries on to the next job. Cancel ends
  /// the job as cancelled, and the runner counts it as neither.
  ///
  /// A job that hands over leaves its outbox in [outboxes] for the runner.
  Future<ExportJobStatus> _runQueuedJob(
    ExportJob job,
    List<String> outboxes,
  ) async {
    _activeJobId = job.id;
    _queue.update(
      job.id,
      (current) => current.copyWith(status: ExportJobStatus.running),
    );
    _loadJobIntoForm(job);
    _settleStanding();
    try {
      final ran = await _runIntoDestination(_runCurrentTabExport);
      if (ran.outbox case final outbox?) {
        outboxes.add(outbox);
      }
      final message = ran.message;
      final status = _cancelRequested
          ? ExportJobStatus.cancelled
          : ExportJobStatus.succeeded;
      _queue.update(
        job.id,
        (current) => current.copyWith(status: status, message: message),
      );
      return status;
    } on Object catch (error) {
      _queue.update(
        job.id,
        (current) =>
            current.copyWith(status: ExportJobStatus.failed, message: '$error'),
      );
      return ExportJobStatus.failed;
    } finally {
      _activeJobId = null;
    }
  }

  /// What the status bar says when the queue rests: how many jobs are done,
  /// how many failed (부분 실패), and whether Cancel left any queued.
  String _queueRestSentence(int succeeded, int failed) =>
      AppText.strings.exQueueRest(
        AppText.strings.exJobCount(succeeded),
        failed: failed,
        kept: _queue.nextQueued != null,
      );

  /// Runs an image export over [count] items and reports it the one way:
  /// cancelled when fewer landed than were asked for, done otherwise.
  ///
  /// ⛔THE FIXED ARGUMENTS ARE THE POINT. Every image export writes into
  /// the picked location, watches the same cancel flag and feeds the same
  /// progress bar; written out per export, the one that forgets
  /// `isCancelled` keeps rendering after the user pressed Cancel.
  ///
  /// A null render or a null encode answer skips that file (the service's
  /// rule); the finished sentence counts the skips, and says so only when
  /// there were any.
  ///
  /// [thenWrite] are the files of the run that are no picture — a digital
  /// sheet — written after the pictures, a file each, counted with them and
  /// stopped where they are stopped.
  Future<String> _runImageExport({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String Function(int index) fileNameFor,
    required _Tally says,
    ExportImageEncoder? Function(int index)? encoderFor,
    List<Future<void> Function()> thenWrite = const [],
  }) async {
    final total = count + thenWrite.length;
    // The lone file of a run asked a place of its own wears the name it was
    // given there, whatever its rule calls it ([_placedName]).
    final placedName = _placedName;
    if (placedName != null && total > 1) {
      // ⛔A file's place holds ONE file. Written on regardless, every file
      // of the run would land on that one name, each over the last — so a
      // run that reaches here with more is stopped before it writes
      // (the queue asks such a job its place again, [_placesStillFit]).
      throw StateError(
        'A place asked for one file cannot take the $total this run writes.',
      );
    }
    final summary = await _exportService.exportImages(
      count: count,
      renderImage: renderImage,
      fileNameFor: placedName == null ? fileNameFor : (_) => placedName,
      directoryPath: _outputDirectory,
      encoderFor: encoderFor,
      isCancelled: () => _cancelRequested,
      onProgress: (completed, _) => _reportProgress(completed, total),
    );
    var (:written, :processed) = summary;
    // Nothing more is written once the pictures were stopped short.
    final picturesDone = processed == count;
    for (final write in thenWrite) {
      if (!picturesDone || _cancelRequested) {
        break;
      }
      await write();
      written += 1;
      processed += 1;
      _reportProgress(processed, total);
    }
    final strings = AppText.strings;
    if (processed < total) {
      return _exportCancelled(says.kept(strings, written));
    }
    return _exportDone(
      says.done(strings, written),
      skipped: processed - written,
    );
  }

  Future<String> _exportConte() async {
    final (source, pages) = _conteSheet();
    final spec = _specs.conte;
    final words = _conteWords;
    // Every cell's picture at its ORIGINAL, the camera frame, in both
    // formats (유저 2026-09-25 conte-picture-resolution-Q1: 「내보내기는
    // 원본」 · 「내보낼땐 용지가 실제크기가 꽤 크니까 그에 맞춰서 해상도
    // 높기만하면됨」). ↩️320px a sheet-scale step for pages and 640px for
    // the PDF — about 170dpi on the printed sheet.
    final cameraSize = _session.camera.cameraFrameSize;
    if (spec.format == ExportConteFormat.pageImage) {
      // Streamed like every image export: ONE page's cell pictures live
      // at a time (a cut spanning two pages re-renders once per page —
      // cheaper than holding the whole film's cells).
      return _runImageExport(
        count: pages.length,
        renderImage: (index) => _renderContePage(
          pages[index],
          source,
          pictureWidth: cameraSize.width,
          words: words,
        ),
        fileNameFor: (index) => _contePageFileName(index, pages.length),
        encoderFor: (_) => _stillEncodeFor(spec.image),
        says: _Tally.contePages,
      );
    }
    // Vector PDF: one document, the layout's own points as page geometry.
    // Each cell renders, converts to raw bytes and FREES its ui.Image
    // before the next renders — only the raw copies (the document's own
    // material) live to the end.
    _reportProgress(0, pages.length + 1);
    final pdfPictures = <SheetPictureKey, ContePdfPicture>{};
    await _forEachContePicture(
      pages,
      width: cameraSize.width,
      have: pdfPictures.containsKey,
      take: (key, image) async {
        try {
          final picture = await ContePdfPicture.fromImage(image);
          if (picture != null) {
            pdfPictures[key] = picture;
          }
        } finally {
          image.dispose();
        }
      },
    );
    if (_cancelRequested) {
      return AppText.strings.exCancelled;
    }
    // The sheet ink (R5): compose per window, convert to raw bytes, free
    // the ui.Images — the same lifecycle the cell pictures follow.
    final inkImages = await _renderConteInk(pages);
    final inkPictures = <BrushFrameKey, ContePdfPicture>{};
    try {
      for (final entry in inkImages.entries) {
        final picture = await ContePdfPicture.fromImage(entry.value);
        if (picture != null) {
          inkPictures[entry.key] = picture;
        }
      }
    } finally {
      for (final image in inkImages.values) {
        image.dispose();
      }
    }
    // The media images the pages print (the logo, the cover's picture) —
    // one raw copy each for the file, the same lifecycle again.
    final sheetImages = await readContePageImages(pages, source, words);
    final pdfImages = <String, ContePdfPicture>{};
    try {
      for (final entry in sheetImages.entries) {
        final picture = await ContePdfPicture.fromImage(entry.value);
        if (picture != null) {
          pdfImages[entry.key] = picture;
        }
      }
    } finally {
      for (final image in sheetImages.values) {
        image.dispose();
      }
    }
    final fonts = await ContePdfFonts.load();
    _reportProgress(pages.length, pages.length + 1);
    final bytes = await writeContePdf(
      source: source,
      pages: pages,
      fonts: fonts,
      pictures: pdfPictures,
      images: pdfImages,
      inkPictures: inkPictures,
      picturesOverInkOf: (page) => contePicturesOverInkIn(_session, page),
      words: words,
    );
    final file = File(
      _joinLocation(_singleFileName(_conteFileController, 'pdf')),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    _reportProgress(pages.length + 1, pages.length + 1);
    return AppText.strings.exDoneContePdf(
      AppText.strings.exPageCount(pages.length),
    );
  }

  Future<String> _exportVideo() async {
    final spec = _specs.sequence;
    final format = spec.format;
    final alphaVideo = format.wantsAlpha;
    final plan = _sequencePlanForRun(video: true);
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: format,
      alphaVideo: alphaVideo,
    );
    final videoPath = _joinLocation(
      _singleFileName(_sequenceFileController, format.container.fileExtension),
    );
    final audioMixPath = spec.includeAudio ? await _renderAudioMix(plan) : null;
    try {
      final summary = await widget.videoExportService.exportVideo(
        count: plan.length,
        // Opaque codecs bake the cut fade/pose into RGB; ProRes 4444 α
        // keeps the channel (transparent ground, fade still paints).
        renderImage: (index) => renderer.renderCompositeForVideo(
          plan[index],
          spec.sizeMode,
          preserveAlpha: alphaVideo,
        ),
        outputFilePath: videoPath,
        frameRate: _session.projectSettings.projectFrameRate,
        audioMixPath: audioMixPath,
        container: format.container,
        codec: format.videoCodec,
        alpha: alphaVideo,
        bitrateBps: format.videoBitrateMbps * 1000000,
        isCancelled: () => _cancelRequested,
        onProgress: _reportProgress,
      );
      if (summary.processed < plan.length) {
        return summary.written == 0
            ? AppText.strings.exCancelled
            : AppText.strings.exCancelledVideo(
                AppText.strings.exFrameCount(summary.written),
              );
      }
      return AppText.strings.exDoneVideo(
        AppText.strings.exFrameCount(summary.written),
      );
    } finally {
      // The pictures the run held from one frame to the next.
      renderer.dispose();
      if (audioMixPath != null) {
        try {
          File(audioMixPath).deleteSync();
        } on Object {
          // A leftover temp mix is untidy, not an export failure.
        }
      }
    }
  }

  Future<String> _exportPngSequence() {
    final spec = _specs.sequence;
    final plan = _sequencePlanForRun(video: false);
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    return _runImageExport(
      count: plan.length,
      renderImage: (index) =>
          renderer.renderComposite(plan[index], spec.sizeMode),
      fileNameFor: _sequenceFileNameFor,
      encoderFor: (_) => _stillEncodeFor(spec.format),
      says: _Tally.frames,
    );
  }

  Future<String> _exportCurrentFrame() async {
    final spec = _specs.image;
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    final task = ExportFrameTask(
      cut: _activeCut,
      frameIndex: _currentImageFrame(),
    );
    // Under the name it was given where its place was asked, when it was
    // ([_placedName]) — the sentence below names the file that was written.
    final fileName =
        _placedName ??
        _singleFileName(
          _imageFileController,
          spec.format.stillFormat.fileExtension,
        );
    final summary = await _exportService.exportImages(
      count: 1,
      renderImage: (_) => renderer.renderComposite(task, spec.sizeMode),
      fileNameFor: (_) => fileName,
      directoryPath: _outputDirectory,
      encoderFor: (_) => _stillEncodeFor(spec.format),
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    return summary.written == 1
        ? AppText.strings.exDoneFile(fileName)
        : AppText.strings.exNothingInFrame;
  }

  /// The Cels tab's run: every file the list shows bright — the cels, and
  /// beside them the documents of the cuts in scope — one after another,
  /// each written as its own format says (유저 2026-10-05: 「타임시트 탭을
  /// 그냥 셀 탭의 내부로 편입. 컷봉투탭도 셀 내부로 편입」).
  Future<String> _exportCels() {
    final spec = _specs.cels;
    final plan = _celGroupPlan();
    // Cels stay raw artwork (no FX) — the renderer carries the paper
    // color for the RGB channel choice; the group render composites the
    // label's members at their static opacities.
    // ✅유저 2026-08-27: 「셀 출력 강제도 래스터라이즈시키고 출력하면
    // 되는거니까 멋대로 판단하지말고」. It is the tab's switch now, the same
    // one every other tab has carried since R4-new1 — the hardcoded false
    // was the asymmetry, and its stated reason (blur in delivery line art)
    // is a position an artist can choose rather than a law.
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    final face = _documentFace;
    final digital = spec.sheetFormat == ExportTimesheetFormat.xdts;
    bool isDigitalSheet(ExportDocumentSheet sheet) =>
        digital && sheet.kind == ExportCelKind.timesheet;
    // 🚨THE FILES THAT ARE ON, not every planned one. ↩️The run walked the
    // list the window PREVIEWS, so a cel whose switch was off was counted
    // out of the headline and written all the same (found reading the run
    // for F-289, 2026-10-06).
    final pictures = <_PictureFile>[
      for (final task in plan.writtenCels)
        (
          fileName: task.fileName,
          render: () => renderer.renderCelGroup(task, spec.sizeMode),
          encoder: _stillEncodeFor(spec.format),
        ),
      for (final sheet in plan.writtenDocuments)
        if (sheet.kind == ExportCelKind.envelope)
          (
            fileName: sheet.fileName,
            render: () => _renderEnvelope(_envelopeTask(sheet), face: face),
            encoder: _stillEncodeFor(spec.envelopeImage),
          )
        else if (!isDigitalSheet(sheet))
          (
            fileName: sheet.fileName,
            render: () => _renderSheetPage(_sheetPageTask(sheet), face: face),
            encoder: _stillEncodeFor(spec.sheetImage),
          ),
    ];
    return _runImageExport(
      count: pictures.length,
      renderImage: (index) => pictures[index].render(),
      fileNameFor: (index) => pictures[index].fileName,
      encoderFor: (index) => pictures[index].encoder,
      thenWrite: [
        for (final sheet in plan.writtenDocuments)
          if (isDigitalSheet(sheet)) () => _writeXdts(sheet),
      ],
      says: plan.writtenDocuments.isEmpty ? _Tally.cels : _Tally.files,
    );
  }

  /// The digital sheet of a cut's timesheet, at [sheet]'s file.
  Future<void> _writeXdts(ExportDocumentSheet sheet) async {
    final cut = sheet.of;
    final content = buildXdtsContent(
      cut: cut,
      cutLabel: cut.name,
      instructionDefById: _session.camera.cameraInstructionSet.defById,
      // The print sheet's own SE sources (track lanes + this cut's true
      // origin on the track axis) — the two sheets must read one story.
      trackSeLayers: _session.activeTrack.seLayers,
      cutStartFrame: _trackStartOf(cut),
    );
    final file = File(_joinLocation(sheet.fileName));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  /// Renders the SE mix to a temp WAV through the same mixer playback
  /// uses; null = nothing audible (video-only encode).
  Future<String?> _renderAudioMix(List<ExportFrameTask> videoPlan) async {
    final schedule = buildExportAudioPlan(
      plan: videoPlan,
      project: _session.repository.requireProject(),
    );
    if (schedule.isEmpty) {
      return null;
    }
    final store = _session.audioConformStore;
    for (final clip in schedule) {
      await store.ensureFor(clip.filePath);
    }
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'qa_export_mix_${DateTime.now().microsecondsSinceEpoch}.wav';
    final written = await writeExportAudioMixWav(
      schedule: schedule,
      rate: _session.projectSettings.projectFrameRate,
      totalFrames: videoPlan.length,
      sampleRate: store.projectSampleRate,
      resolveSource: (filePath) async {
        final entry = await store.ensureFor(filePath);
        final samples = entry != null && entry.isUsable ? entry.samples : null;
        if (samples == null) {
          return null;
        }
        return AudioMixSource(samples: samples, channels: entry!.channels);
      },
      resolveStreamReader: (filePath) =>
          store.isStreaming(filePath) ? store.streamReaderFor(filePath) : null,
      outputPath: path,
      log: debugPrint,
    );
    return written ? path : null;
  }

  void cancelExport() {
    _cancelRequested = true;
  }

  // --- presets --------------------------------------------------------------

  List<ExportPreset> get _tabPresets =>
      AppExport.settings.value.presetsFor(_tab);

  void _applyPreset(ExportPreset preset) {
    setState(() {
      _specs = _specs.withSpec(preset.spec);
      _syncControllersFromSpecs();
    });
    _persist();
    _settleStanding();
  }

  Future<void> _saveCurrentPreset() async {
    final name = await showExportPresetNameDialog(context);
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    final preset = ExportPreset(
      id: ExportPresetId('preset-${DateTime.now().microsecondsSinceEpoch}'),
      name: name,
      spec: _specs.specFor(_tab),
    );
    final settings = AppExport.settings.value;
    AppExport.settings.value = settings.copyWith(
      presets: [...settings.presets, preset],
    );
    setState(() {});
    _persist();
  }

  void _deletePreset(ExportPreset preset) {
    final settings = AppExport.settings.value;
    AppExport.settings.value = settings.copyWith(
      presets: [
        for (final entry in settings.presets)
          if (entry.id != preset.id) entry,
      ],
    );
    setState(() {});
    _persist();
  }

  // --- build ----------------------------------------------------------------

  /// THE DOOR — where this tab's outputs go, asked at the one door every
  /// export asks at ([askWhereOutputsGo]): a lone file is asked a save
  /// window with its name in it, several a folder — before they are made
  /// where the platform lets that be asked, and otherwise once the run
  /// hands them over ([ExportHandOver]). Null = the user backed out of the
  /// window that asks first, and nothing runs.
  ///
  /// The window opens where the last export was asked a place
  /// ([AppExportSettings.lastFolder]).
  Future<ExportDestination?> _askWhere() => askWhereOutputsGo(
    context,
    loneFileName: _loneOutputName(),
    initialDirectory: AppExport.settings.value.lastFolder,
    windows: _standInWindows(),
  );

  /// The test seam's windows: the folder [ExportDialog.exportDirectoryPicker]
  /// answers stands for what a person picks in WHICHEVER window the door
  /// opens — that folder, or the lone file under its offered name in it.
  /// Null in production: the door opens the system's own.
  OutputPlaceWindows? _standInWindows() {
    final picker = widget.exportDirectoryPicker;
    if (picker == null) {
      return null;
    }
    return (
      folder: (_) => picker(),
      file: (suggestedName, _) async => switch (await picker()) {
        final directory? => '$directory/$suggestedName',
        null => null,
      },
    );
  }

  /// Whether this tab's run is asked its place before it makes its files.
  bool get _asksWhereFirst =>
      outputsAskedTheirPlaceFirstHere(oneFile: _loneOutputName() != null);

  /// The ONE file this tab's run hands over, by the name a field or a rule
  /// gives it — or null when it hands over several, or a folder, or
  /// nothing.
  ///
  /// With the platform, what decides which window asks its place and when
  /// ([askWhereOutputsGo]). The count that is actually written decides, not
  /// the format (F-221-Q3, 유저 2026-10-06: 「한 장이면 파일 저장 창, 두
  /// 장부터 폴더 창」): a sheet of one page is one file.
  ///
  /// ⚠️ONE FILE BEHIND FOLDERS IS A FOLDER. A naming rule that files a cel
  /// under its cut and its layer makes `CUT1/A/A0001.png` of the only cel
  /// there is — and what leaves the run then is `CUT1`, which a save window
  /// cannot name. The hand-over reads a run's outbox the same way
  /// ([handOverFilesForUser]: one FILE at its top is one file), so the two
  /// ends of a run cannot disagree about which window it is owed.
  String? _loneOutputName() {
    final name = _onlyOutputName();
    return name == null || fileNameOfPath(name) != name ? null : name;
  }

  /// The name of the only file this tab's run writes, folders of its rule's
  /// making included — or null when it writes several, or none.
  String? _onlyOutputName() {
    final lone = _loneFile();
    if (lone != null) {
      return _singleFileName(lone.controller, lone.extension);
    }
    switch (_tab) {
      case ExportTab.sequence:
        return _sequencePlanForRun(video: false).length == 1
            ? _sequenceFileNameFor(0)
            : null;
      case ExportTab.cels:
        final written = _celGroupPlan().writtenFileNames;
        return written.length == 1 ? written.single : null;
      case ExportTab.conte:
        return _conteSheet().$2.length == 1 ? _contePageFileName(0, 1) : null;
      case ExportTab.image:
        // A lone file by its format, answered above.
        return null;
    }
  }

  /// The run about to start, or the job just queued, goes to [destination]
  /// — and where it was asked a place is remembered, as where the next
  /// window opens. A run that hands over was asked none, and leaves what
  /// was remembered as it was.
  void _takeDestination(ExportDestination destination) {
    setState(() => _destination = destination);
    if (destination is ExportPlace) {
      AppExport.settings.value = AppExport.settings.value.copyWith(
        lastFolder: destination.folderPath,
      );
    }
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_anchorCut == null) {
      return _noCutsDialog(context);
    }
    // LayoutBuilder sits OUTSIDE the window now: AppWindow owns the Dialog,
    // so the room the drawers negotiate over is the screen minus the
    // window's inset, not the dialog's interior.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = _windowMetrics(constraints);
        return AppWindow(
          windowKey: const ValueKey<String>('export-dialog'),
          title: AppText.strings.exExport,
          titleIcon: Icons.upload_file_outlined,
          onClose: _isExporting ? null : () => Navigator.of(context).pop(),
          width: room.width,
          height: room.height,
          scrollBody: false,
          bodyPadding: EdgeInsets.zero,
          tabs: _tabStrip(),
          selectedTab: ExportTab.values.indexOf(_tab),
          body: CursorNoticeOverlay(
            controller: _notices,
            child: _zones(
              theme,
              presetsOpen: room.presetsOpen,
              queueOpen: room.queueOpen,
            ),
          ),
          leadingActions: [
            AppWindowAction(
              label: AppText.strings.exAddToQueue,
              actionKey: const ValueKey<String>('export-queue-add-button'),
              onPressed: _canExport ? () => unawaited(addToQueue()) : null,
            ),
          ],
          footerBetween: _footerBetween(theme),
          actions: _windowActions(context),
        );
      },
    );
  }

  /// R27 #31: nothing to export. An empty state, never a throw.
  Widget _noCutsDialog(BuildContext context) {
    final strings = _session.uiStrings;
    return AppConfirmDialog(
      windowKey: const ValueKey<String>('export-dialog-no-cuts'),
      title: AppText.strings.exExport,
      titleIcon: Icons.upload_file_outlined,
      message: strings.exportNoCuts,
      actions: [
        AppWindowAction(
          label: strings.commonClose,
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// The four columns' widths. ⚠️The collapse rule and the row that lays
  /// the columns out must agree on these to the pixel, so they are read
  /// from here by both instead of typed twice.
  static const double _presetsDrawerWidth = 152;
  static const double _queueDrawerWidth = 200;
  static const double _collapsedDrawerWidth = 22;

  /// The least the preview column is given before a drawer folds for it:
  /// what the Cels list under the preview lays out at — its rules, its rail
  /// and five blocks ([ExportCelsBoard.minimumWidth]) — inside the column's
  /// padding. ↩️330, while the list stood beside the preview at 132.
  static const double _previewColumnWidth = ExportCelsBoard.minimumWidth + 16;
  static const double _settingsColumnWidth = 272;

  /// The window's size and whether each drawer still fits, for the room the
  /// screen leaves.
  ///
  /// The drawers yield before the preview does (v10: 전개 ~1020 / 최소
  /// ~700): a tight surface collapses the queue, then the presets, to
  /// presentational strips — the STORED preference stays untouched, so the
  /// drawer comes back the moment the room does.
  ({double width, double height, bool presetsOpen, bool queueOpen})
  _windowMetrics(BoxConstraints constraints) {
    // ⚠️The window sits in a Material `Dialog`, whose own insetPadding is
    // 40 a side horizontally and 24 vertically. Taking the full room means
    // taking THAT room: ask for more and the window overflows its dialog.
    const sideInset = 80.0;
    const verticalInset = 64.0;
    final availableWidth = constraints.maxWidth - sideInset;
    final availableHeight = constraints.maxHeight - verticalInset;
    var presetsOpen = _presetsOpen;
    var queueOpen = _queueOpen;
    double widthFor() =>
        _drawerWidth(presetsOpen, _presetsDrawerWidth) +
        _previewColumnWidth +
        _settingsColumnWidth +
        _drawerWidth(queueOpen, _queueDrawerWidth) +
        4;
    if (widthFor() > availableWidth && queueOpen) {
      queueOpen = false;
    }
    if (widthFor() > availableWidth && presetsOpen) {
      presetsOpen = false;
    }
    // 🗣️유저 2026-09-16: 「미리보기 셀 리스트 가로길이가 길어서 미리보기
    // 프리뷰창이 너무 작아지거든? … 그냥 출력 공용창 크기 자체를 더 크게
    // 키우는게 날거같기도? … 어차피 창은 이제 비율기준이니까 앱 전체 채워도
    // 문제는없잖아」.
    //
    // The window used to be exactly the four columns' sum, so the preview —
    // the only column that stretches — got whatever the fixed three left,
    // and the cel list ate into that. It takes the room the screen leaves
    // now; [widthFor] stays because it answers a different question: whether
    // a drawer still fits.
    return (
      width: availableWidth,
      height: availableHeight,
      presetsOpen: presetsOpen,
      queueOpen: queueOpen,
    );
  }

  static double _drawerWidth(bool open, double openWidth) =>
      open ? openWidth : _collapsedDrawerWidth;

  List<AppWindowTab> _tabStrip() => [
    for (final tab in ExportTab.values)
      AppWindowTab(
        label: ExportPresetRail.tabLabel(tab),
        tabKey: ValueKey<String>('export-tab-${tab.jsonValue}'),
        enabled: !_isExporting,
        onSelected: () {
          setState(() => _tab = tab);
          _settleStanding();
        },
      ),
  ];

  /// The window's four columns: presets · preview · settings · queue.
  ///
  /// ↩️A bar across their top named the file and where it went. The name is
  /// at the head of the settings column now ([_nameAccordion]) and the place
  /// is asked when Export is pressed ([_askWhere]) — 유저 2026-10-06:
  /// 「이름줄 없는거 맘에들고」.
  Widget _zones(
    ThemeData theme, {
    required bool presetsOpen,
    required bool queueOpen,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _drawerWidth(presetsOpen, _presetsDrawerWidth),
          child: _presetsZone(open: presetsOpen),
        ),
        VerticalDivider(width: 1, color: theme.dividerColor),
        Expanded(child: _previewZone(theme)),
        VerticalDivider(width: 1, color: theme.dividerColor),
        SizedBox(width: _settingsColumnWidth, child: _settingsZone()),
        VerticalDivider(width: 1, color: theme.dividerColor),
        SizedBox(
          width: _drawerWidth(queueOpen, _queueDrawerWidth),
          child: _queueZone(open: queueOpen),
        ),
      ],
    );
  }

  /// What stands between the footer's two ends: the progress of the run
  /// under way — there for the length of an export and at no other time
  /// (유저 2026-10-06: 「진행표시 원래위치대로 넣자. 출력때만 보이게」) — or the
  /// sentence the last run ended on; and, against the Export button, the
  /// order this export takes on this machine.
  ///
  /// ⚠️The order line is the one explanation this window carries. It is
  /// there because the user asked for it by name
  /// ([AppStrings.exOrderAsksFirst]) — not a precedent for a caption under
  /// a control.
  Widget _footerBetween(ThemeData theme) {
    final strings = AppText.strings;
    final order = _asksWhereFirst
        ? strings.exOrderAsksFirst
        : strings.exOrderAsksAfter;
    return LayoutBuilder(
      builder: (context, room) => Row(
        children: [
          Expanded(
            child: _isExporting
                ? LayoutBuilder(
                    builder: (context, bar) {
                      // What a run's frames are counted in from here on
                      // ([_progress]).
                      _barPixels =
                          (bar.maxWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .floor();
                      return ValueListenableBuilder<({int end, int of})?>(
                        valueListenable: _progress,
                        builder: (context, progress, _) =>
                            LinearProgressIndicator(
                              key: const ValueKey<String>('export-progress'),
                              // Nothing to stand on until a frame has been
                              // counted in a bar that has a length.
                              value: progress != null && progress.of > 0
                                  ? progress.end / progress.of
                                  : null,
                              minHeight: 4,
                            ),
                      );
                    },
                  )
                : _statusNote(theme),
          ),
          const SizedBox(width: _footerGap),
          // The words give way before the bar does: in a narrow window the
          // line is cut short, its whole sentence a hover away.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(
                0,
                room.maxWidth - _footerGap - _progressLeastWidth,
              ),
            ),
            child: AppTooltip(
              message: order,
              child: Text(
                order,
                key: const ValueKey<String>('export-order-line'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const double _footerGap = 12;

  /// The least the footer's bar is given — drawn so in the F-289 mock.
  static const double _progressLeastWidth = 24;

  Widget _statusNote(ThemeData theme) => Text(
    _statusMessage ?? '',
    key: const ValueKey<String>('export-status'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  /// The footer's right end: Export — and, for the length of a run, Cancel
  /// against its left.
  List<AppWindowAction> _windowActions(BuildContext context) => [
    if (_isExporting)
      AppWindowAction(
        label: AppText.strings.commonCancel,
        actionKey: const ValueKey<String>('export-cancel-button'),
        onPressed: cancelExport,
      ),
    AppWindowAction(
      label: AppText.strings.exExport,
      actionKey: const ValueKey<String>('export-run-button'),
      emphasis: AppWindowActionEmphasis.primary,
      onPressed: _canExport ? () => unawaited(export()) : null,
    ),
  ];

  /// The name of a file a hand names, at the head of the settings column —
  /// where every other name is set: the name typed alone, and beside it the
  /// extension its format gives it ([ExportFileNameModule]).
  ExportAccordion _nameAccordion({
    required TextEditingController controller,
    required String extension,
  }) => ExportAccordion(
    title: AppText.strings.commonNameField,
    summary: _patternPreview(),
    expansion: _expansion('name', open: true),
    child: ExportFileNameModule(
      controller: controller,
      extension: extension,
      enabled: !_isExporting,
      onChanged: () => setState(() {}),
    ),
  );

  /// The first file's name alone — what a naming module says in its head.
  String _patternPreview() => _firstOutputFile().name ?? _nothingToWriteText();

  Widget _presetsZone({required bool open}) {
    if (!open) {
      return ExportDrawerStrip(
        key: const ValueKey<String>('export-presets-strip'),
        caption: AppText.strings.exPresets,
        chevron: Icons.chevron_right,
        onTap: () {
          setState(() => _presetsOpen = true);
          _persist();
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ControlPressClaim(
            onPressed: () {
              setState(() => _presetsOpen = false);
              _persist();
            },
            child: InkWell(
              key: const ValueKey<String>('export-presets-collapse'),
              onTap: silentPress(() {
                setState(() => _presetsOpen = false);
                _persist();
              }),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.chevron_left, size: 13),
              ),
            ),
          ),
        ),
        Expanded(
          child: ExportPresetRail(
            tab: _tab,
            presets: _tabPresets,
            currentSpec: _specs.specFor(_tab),
            enabled: !_isExporting,
            onApply: _applyPreset,
            onSaveCurrent: () => unawaited(_saveCurrentPreset()),
            onDelete: _deletePreset,
          ),
        ),
      ],
    );
  }

  /// The preview — the file under the window's hand, in a canvas-base panel
  /// ([ExportPreviewPanel]) — and under it, on the Cels tab, the list.
  ///
  /// ↩️A scrub bar, a line saying where the playhead stood and a line naming
  /// the first file stood between the picture and the list. The panel's
  /// transport and its page cluster turn the picture now, and the file's
  /// name is on the picture (유저 2026-10-06: 「파일이름 위치도 심플해서
  /// 좋아」).
  Widget _previewZone(ThemeData theme) {
    final file = _previewFile();
    final well = AppShapes.container(AppShapes.wellRadius);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(shape: well),
              foregroundDecoration: ShapeDecoration(
                shape: well.copyWith(
                  side: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: ExportPreviewPanel(
                session: _session,
                document: _previewDocument(),
                page: _previewPage(),
                onPage: _turnPreviewTo,
                nothingToShow: _nothingToWriteText(),
                // The Sequence tab trims; no other does.
                range: _tab == ExportTab.sequence ? _sequenceRange() : null,
                fileName: file.name,
                fileAbsent: file.absent,
                enabled: !_isExporting,
              ),
            ),
          ),
          // The Cels tab's list stands under its preview (유저 2026-10-06:
          // 「가로/아래가 좋고」).
          if (_tab == ExportTab.cels) ...[
            const SizedBox(height: 6),
            _celsBoard(),
          ],
        ],
      ),
    );
  }

  Widget _settingsZone() {
    final children = switch (_tab) {
      ExportTab.sequence => _sequenceModules(),
      ExportTab.image => _imageModules(),
      ExportTab.cels => _celsModules(),
      ExportTab.conte => _conteModules(),
    };
    // A plain scroll view (not a lazy list): a handful of modules, and
    // collapsed accordions must exist for finders/ensureVisible.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) ...[
            child,
            const SizedBox(height: exportModuleGap),
          ],
        ],
      ),
    );
  }

  /// The format accordion an export tab offers: the same title, the same
  /// `format` fold key, and the module fed the tab's own [capabilities].
  ///
  /// ⛔ONE FORMAT ACCORDION. Three tabs wrote out the summarize call, the
  /// fold key and the enabled/onChanged pair; a tab that stopped passing
  /// `enabled` keeps its format pickers live DURING a render, which is
  /// the setting changing under the export it is feeding.
  ///
  /// On the Cels tab it is 「셀 형식」 — one of three formats the tab
  /// writes, beside the timesheet's and the cut envelope's — and stands
  /// folded (drawn so in the F-289 mock).
  ExportAccordion _formatAccordion({
    required ExportFormatSelection format,
    required ExportFormatCapabilities capabilities,
    required void Function(ExportFormatSelection format) onChanged,
    ({bool enabled, VoidCallback onTap})? reset,
  }) => ExportAccordion(
    title: _tab == ExportTab.cels
        ? AppText.strings.exCelFormat
        : AppText.strings.exFormat,
    summary: ExportFormatModule.summarize(format),
    expansion: _expansion('format', open: _tab != ExportTab.cels),
    reset: reset,
    child: ExportFormatModule(
      selection: format,
      capabilities: capabilities,
      enabled: !_isExporting,
      onChanged: onChanged,
    ),
  );

  List<Widget> _sequenceModules() {
    final spec = _specs.sequence;
    final projectScope = spec.scope == ExportScopeKind.project;
    return [
      // The name is always the first module: a video's one name, or the
      // rule its numbered stills are named by.
      if (spec.format.isVideo)
        _nameAccordion(
          controller: _sequenceFileController,
          extension: spec.format.container.fileExtension,
        )
      else
        _namingAccordion(
          summary: ExportSequenceNamingModule.summarize(
            spec.naming,
            spec.format.stillFormat.fileExtension,
          ),
          isDefault: spec.naming == const ExportSequenceNaming(),
          onReset: () {
            _updateSpec(spec.copyWith(naming: const ExportSequenceNaming()));
            _namingBaseController.text = 'frame';
          },
          child: ExportSequenceNamingModule(
            naming: spec.naming,
            enabled: !_isExporting,
            baseNameController: _namingBaseController,
            onChanged: (naming) => _updateSpec(spec.copyWith(naming: naming)),
          ),
        ),
      _formatAccordion(
        format: spec.format,
        capabilities: ExportFormatCapabilities(
          stills: const [ExportStillFormat.png, ExportStillFormat.jpg],
          video: const {
            ExportVideoContainer.mp4: [
              ExportVideoCodec.h264,
              ExportVideoCodec.h265,
            ],
            ExportVideoContainer.mov: [
              ExportVideoCodec.h264,
              ExportVideoCodec.proresProxy,
              ExportVideoCodec.proresLt,
              ExportVideoCodec.prores422,
              ExportVideoCodec.proresHq,
              ExportVideoCodec.prores4444,
            ],
          },
          stillEnabled: _availability.stillAllowed,
          videoEnabled: _availability.videoAllowed,
          videoReason: _availability.videoBlockedReason,
        ),
        onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
        reset: (
          enabled: spec.format != const ExportFormatSelection(),
          onTap: () =>
              _updateSpec(spec.copyWith(format: const ExportFormatSelection())),
        ),
      ),
      _scopeAccordion(
        scope: spec.scope,
        onChanged: (scope) => _updateSpec(
          spec.copyWith(
            scope: scope,
            // The v10 coupling: a project scope renders through the
            // camera (per-cut canvases cannot make one movie).
            sizeMode: scope == ExportScopeKind.project
                ? ExportSizeMode.camera
                : spec.sizeMode,
          ),
        ),
        fold: (key: 'scope', open: true),
      ),
      _sizeAccordion(
        sizeMode: spec.sizeMode,
        canvasSizes: _scopeCanvasSizes(spec.scope),
        projectScope: projectScope,
        open: true,
        onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
      ),
      if (spec.format.isVideo)
        ExportAccordion(
          title: AppText.strings.exAudio,
          summary: spec.includeAudio
              ? AppText.strings.exSeMuxed(
                  spec.format.videoCodec.isProRes ? 'PCM' : 'AAC',
                )
              : AppText.strings.commonOff,
          expansion: _expansion('audio'),
          child: _specToggle(
            keyValue: 'export-audio-toggle',
            label: AppText.strings.exMuxSeMix,
            value: spec.includeAudio,
            write: (value) => spec.copyWith(includeAudio: value),
          ),
        ),
      _fxAccordion(
        keyValue: 'export-apply-fx-toggle',
        label: AppText.strings.exApplyLayerFxHelp,
        applyLayerFx: spec.applyLayerFx,
        onChanged: (value) => _updateSpec(spec.copyWith(applyLayerFx: value)),
      ),
    ];
  }

  List<Widget> _imageModules() {
    final spec = _specs.image;
    return [
      _nameAccordion(
        controller: _imageFileController,
        extension: spec.format.stillFormat.fileExtension,
      ),
      _formatAccordion(
        format: spec.format,
        capabilities: _stillOnlyCapabilities,
        onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
      ),
      _sizeAccordion(
        sizeMode: spec.sizeMode,
        canvasSizes: {_activeCut.canvasSize},
        projectScope: false,
        open: true,
        onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
      ),
      _fxAccordion(
        keyValue: 'export-image-fx-toggle',
        label: AppText.strings.exApplyLayerFx,
        applyLayerFx: spec.applyLayerFx,
        onChanged: (value) => _updateSpec(spec.copyWith(applyLayerFx: value)),
      ),
    ];
  }

  // --- Cels delta plumbing (v10 ⑥: 규칙 적용 후 델타만) ------------------

  /// What the rules — and, unless [withDelta] is off, the hand — say of
  /// [cut]'s rows.
  ExportCelsSelection _celsSelectionOf(Cut cut, {bool withDelta = true}) =>
      resolveExportCelsSelection(
        cut: cut,
        spec: _specs.cels,
        delta: withDelta ? _overrides.deltaFor(cut.id) : null,
      );

  /// Rewrites what the hand did to [cutId]'s list — the project's, saved
  /// with it — and shows the result.
  ///
  /// ⚠️The cut the LIST shows, not the cut the window opened on: under the
  /// project scope the list shows other cuts' rows, and an answer written
  /// into the anchor's delta named a row the anchor does not have — that
  /// cut's plan never read it, so the switch never moved.
  void _editCelDelta(
    CutId cutId,
    ExportCelsCutDelta Function(ExportCelsCutDelta delta) edit,
  ) {
    _session.repository.updateExportOverrides(
      (overrides) => overrides.withCelsDelta(
        cutId,
        edit(overrides.deltaFor(cutId) ?? ExportCelsCutDelta()),
      ),
    );
    setState(() {});
    _settleStanding();
  }

  /// Turns [rows] of [cut] on or off — storing null where the wish equals
  /// the rule's outcome, so the delta stays exactly the hand exceptions
  /// (Reset = clear, a filter press re-applies the rule). A row's switch and
  /// a folder's (every row under it at once) are one write.
  void _toggleCelRows(Cut cut, Iterable<Layer> rows, bool include) {
    final rule = _celsSelectionOf(cut, withDelta: false);
    _editCelDelta(cut.id, (delta) {
      for (final row in rows) {
        delta = delta.withLayerOverride(
          row.id,
          include == rule.includes(row) ? null : include,
        );
      }
      return delta;
    });
  }

  /// A filter press — the label, its take, 기준 · 어태치 · 시트만 — drops the
  /// row exceptions of the cut the list shows (the drawings turned off stay
  /// off): the rule changed, so the hand's answers to the old rule go. It
  /// stores the filters in the spec, where presets are saved.
  void _applyCelFilter(CelsExportSpec next) {
    final cutId = _celsList().cut.id;
    _session.repository.updateExportOverrides((overrides) {
      final delta = overrides.deltaFor(cutId);
      return delta == null
          ? overrides
          : overrides.withCelsDelta(cutId, delta.withoutRowExceptions());
    });
    _updateSpec(next);
  }

  /// Scope-grid entries: one per cut, and ONE per 겸용 group — the siblings
  /// share a cell labelled with their joined name and toggle together
  /// (유저 2026-09-09: 「컷 리스트에도 한 칸 … 겸용컷 비포함이란게 불가능하도록」).
  List<ExportCutEntry> _scopeCutEntries() {
    final project = _session.repository.requireProject();
    final cuts = resolveExportCuts(
      project: project,
      activeCutId: _activeCut.id,
      range: ExportRange.allCuts,
    );
    final seen = <CutId>{};
    final entries = <ExportCutEntry>[];
    for (var i = 0; i < cuts.length; i += 1) {
      final cut = cuts[i];
      if (!seen.add(cut.id)) {
        continue;
      }
      final group = <CutId>{cut.id, ...linkedCutSiblings(project, cutId: cut.id)};
      seen.addAll(group);
      entries.add((
        ids: [
          for (final candidate in cuts)
            if (group.contains(candidate.id)) candidate.id,
        ],
        label: celGroupCutName(project, cut),
        number: i + 1,
      ));
    }
    return entries;
  }

  Widget _scopeCutGrid() {
    final entries = _scopeCutEntries();
    return ExportCutGrid(
      cuts: entries,
      isIncluded: _overrides.cutIncluded,
      enabled: !_isExporting,
      onToggle: (ids, included) {
        _session.repository.updateExportOverrides((overrides) {
          var next = overrides;
          for (final id in ids) {
            next = next.withCutIncluded(id, included);
          }
          return next;
        });
        setState(() {});
        _settleStanding();
      },
      onAllIncluded: () {
        _session.repository.updateExportOverrides(
          (overrides) => overrides.withAllCutsIncluded(),
        );
        setState(() {});
        _settleStanding();
      },
      onRangeSelected: (start, end) {
        _session.repository.updateExportOverrides((overrides) {
          var next = overrides;
          for (final entry in entries) {
            for (final id in entry.ids) {
              next = next.withCutIncluded(
                id,
                entry.number >= start && entry.number <= end,
              );
            }
          }
          return next;
        });
        setState(() {});
        _settleStanding();
      },
    );
  }

  /// The rules that pick the rows, left of the rows they pick and top to
  /// bottom in the order they are asked (F-289, 유저 2026-10-06:
  /// 「내보내기 타입/색라벨/기준 등/적용 용지 이렇게 위에서부터 순차적인
  /// 순서로 되도록」): the kinds — a kind that is off takes its rows OUT of
  /// the list — then the filters over the rows that are left, which stay in
  /// it, off: the label and its take, 기준 · 어태치 · 시트만 — then the paper
  /// that is applied. Reset puts [cut] back on them.
  ///
  /// ↩️They were the 「셀」 module of the settings column, a column away from
  /// the rows they switch.
  Widget _celRules(Cut cut) {
    final spec = _specs.cels;
    final strings = AppText.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _celRulesHead(cut),
          const SizedBox(height: 3),
          // A kind that is off takes its rows out of the list, and what the
          // hand did to them stays for when it is back on — so these write
          // the spec alone ([_updateSpec]). The kinds of the cut's rows in
          // one strip, its documents in a strip under them (drawn so in the
          // F-289 mock).
          _celKindStrip(spec, documents: false),
          const SizedBox(height: 3),
          _celKindStrip(spec, documents: true),
          Divider(height: 11, color: Theme.of(context).dividerColor),
          _celRuleCaption(strings.exLabel),
          const SizedBox(height: 3),
          // Both pickers give width up (their text ellipsising) before the
          // row overflows the column.
          Row(
            children: [
              Flexible(child: _celLabelPicker(spec)),
              const SizedBox(width: 5),
              Flexible(child: _celTakePicker(spec)),
            ],
          ),
          const SizedBox(height: 6),
          _celRuleCaption(strings.exLayerFilter),
          const SizedBox(height: 3),
          _celFilters(spec),
          const SizedBox(height: 6),
          _celRuleCaption(strings.exApply),
          const SizedBox(height: 3),
          PillStrip(
            items: [
              _specSwitch(
                'export-cels-apply-paper',
                strings.exPaperLabel,
                spec.applyPaper,
                () => spec.copyWith(applyPaper: !spec.applyPaper),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One strip of 「내보낼 종류」: the kinds that are the cut's documents, or
  /// the ones that are its rows'.
  Widget _celKindStrip(CelsExportSpec spec, {required bool documents}) =>
      PillStrip(
        items: [
          for (final kind in ExportCelKind.values)
            if (kind.isDocument == documents)
              _specSwitch(
                'export-cels-kind-${kind.jsonValue}',
                exportCelKindLabel(kind),
                spec.kinds.contains(kind),
                () => spec.withKind(kind, !spec.kinds.contains(kind)),
              ),
        ],
      );

  /// The head of the rules: what the first of them asks, and Reset at its
  /// far end — lit once [cut]'s rows have left the rules.
  Widget _celRulesHead(Cut cut) => Row(
    children: [
      Expanded(child: _celRuleCaption(AppText.strings.exKinds)),
      ExportResetChip(
        key: const ValueKey<String>('export-cels-reset'),
        enabled:
            (_overrides.deltaFor(cut.id)?.leavesTheRules ?? false) &&
            !_isExporting,
        onPressed: () =>
            _editCelDelta(cut.id, (delta) => delta.backOnTheRules()),
      ),
    ],
  );

  /// What a rule of the column is called, over its control.
  Widget _celRuleCaption(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// A pill that flips one spec field — lit while [on], writing [write]'s
  /// spec on tap, dead while an export runs.
  PillItem _specSwitch(
    String keyValue,
    String label,
    bool on,
    CelsExportSpec Function() write,
  ) => PillItem(
    keyValue: keyValue,
    label: label,
    selected: on,
    onTap: _isExporting ? null : () => _updateSpec(write()),
  );

  /// 레이어: the three FILTERS — each its own switch, stacking (유저
  /// 2026-09-09: 「단일선택이 아니라 중첩가능이야」): 기준 and 어태치 side by
  /// side in one strip, 시트만 in a strip of its own beside them (drawn so in
  /// the F-289 mock).
  ///
  /// 🪦A 「커스텀」 pill stood beside them in a strip of its own, lit while the
  /// cut's rows left the rule. The LABEL says it now ([_celLabelPicker]) —
  /// 유저 2026-10-06: 「색라벨 필터 LO일때에서 작감용지 레이어 추가하면
  /// 색라벨필터 LO인채인데, 그게아니라 커스텀인상태로 필터 바꾸고싶어」.
  Widget _celFilters(CelsExportSpec spec) {
    final strings = AppText.strings;
    PillItem filter(
      String key,
      String label,
      bool on,
      CelsExportSpec Function() flip,
    ) => PillItem(
      keyValue: 'export-cels-select-$key',
      label: label,
      selected: on,
      onTap: _isExporting ? null : () => _applyCelFilter(flip()),
    );
    // Side by side while the column has the room for both — and in a
    // language whose words do not leave it, the second strip under the
    // first, each at its own width.
    return Wrap(
      spacing: 6,
      runSpacing: 3,
      children: [
        PillStrip(
          items: [
            filter(
              'base',
              strings.exSelBase,
              spec.base,
              () => spec.copyWith(base: !spec.base),
            ),
            filter(
              'attach',
              strings.exSelAttach,
              spec.attach,
              () => spec.copyWith(attach: !spec.attach),
            ),
          ],
        ),
        PillStrip(
          items: [
            filter(
              'sheet',
              strings.exSelSheet,
              spec.sheetOnly,
              () => spec.copyWith(sheetOnly: !spec.sheetOnly),
            ),
          ],
        ),
      ],
    );
  }

  /// 「원화 작감 ▾」 — the timeline's own label flyout behind a button that
  /// wears the picked label's colour (유저: 「그냥 원화작감이라고 심플하게
  /// 텍스트 두고, 버튼 색만 색라벨 색 그대로」).
  ///
  /// While the cut's rows have left the label's rule the button reads
  /// 「커스텀」, on no label's colour — and picking a label, the one it left
  /// included, puts the rows back on that label's rule ([_applyCelFilter]).
  /// 🗣️F-298 (유저 2026-10-05): 「색 라벨 선택하면 사실상 초기화나
  /// 마찬가지인데 커스텀 설정한게 안풀림」.
  Widget _celLabelPicker(CelsExportSpec spec) {
    final theme = Theme.of(context);
    // 「커스텀」 is a state of the delta, not a label of its own: the rows
    // of the cut the list shows have left the rule.
    final custom =
        _overrides.deltaFor(_celsList().cut.id)?.hasRowExceptions ??
        false;
    final fill = custom ? null : layerMarkColor(spec.label);
    final ink = fill == null
        ? theme.colorScheme.onSurface
        : timelineTextOnColor(fill);
    return AbsorbPointer(
      absorbing: _isExporting,
      child: PanelFlyoutTrigger(
        key: const ValueKey<String>('export-cels-label-picker'),
        tooltip: AppText.strings.tlLayerMark,
        padding: EdgeInsets.zero,
        entriesBuilder: () => layerMarkFlyoutEntries(
          onSelected: (mark) => _applyCelFilter(
            spec.copyWith(label: mark.withTake(LayerMark.firstTake)),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 2, 3, 2),
          decoration: ShapeDecoration(
            color: fill,
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: fill == null
                  ? BorderSide(color: theme.dividerColor)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  custom
                      ? AppText.strings.exSelCustom
                      : exportCelLabelText(spec.label),
                  key: const ValueKey<String>('export-cels-label-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: ink),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 14, color: ink),
            ],
          ),
        ),
      ),
    );
  }

  /// 「테이크 최신 ▾」 — the timeline's take flyout plus the export's one
  /// added row, 「최신」.
  Widget _celTakePicker(CelsExportSpec spec) {
    final theme = Theme.of(context);
    final take = spec.take;
    return AbsorbPointer(
      absorbing: _isExporting,
      child: PanelFlyoutTrigger(
        key: const ValueKey<String>('export-cels-take-picker'),
        tooltip: AppText.strings.tlLayerTake,
        padding: EdgeInsets.zero,
        entriesBuilder: () => layerTakeFlyoutEntries(
          selectedTake: take,
          offerLatest: true,
          // The take is the label's other half: a pick is a rule again.
          onSelected: (next) => _applyCelFilter(spec.copyWith(take: next)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 2, 3, 2),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  take == null
                      ? AppText.strings.exTakeLatest
                      : AppText.strings.tlLayerTakeNumber(take),
                  key: const ValueKey<String>('export-cels-take-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _celsModules() {
    final spec = _specs.cels;
    return [
      // Three formats, one a kind of file the tab writes (유저 2026-10-05:
      // 「형식만 타임시트 형식이라는 항목 만들어서 법 통일해서 고를수있게.
      // 그리고 기존 형식 항목은 구분하기위해 셀 형식. 추가로 컷봉투용으로
      // 컷봉투 형식도 만들기」). They stand whether or not their kind is
      // written — a module that came and went with a pill would be UI that
      // pops into existence.
      _formatAccordion(
        format: spec.format,
        capabilities: _stillOnlyCapabilities,
        onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
      ),
      _sheetFormatAccordion(spec),
      _envelopeFormatAccordion(spec),
      _sizeAccordion(
        sizeMode: spec.sizeMode,
        canvasSizes: {_activeCut.canvasSize},
        projectScope: false,
        open: false,
        onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
      ),
      _celNamingAccordion(spec),
      _scopeAccordion(
        scope: spec.scope,
        onChanged: (scope) => _updateSpec(spec.copyWith(scope: scope)),
        // The v10 grid (Timesheet와 공용 부품): checks save with the project.
        child: spec.scope == ExportScopeKind.project ? _scopeCutGrid() : null,
      ),
      // ✅THE SWITCH THE OTHER TABS ALREADY HAD. This tab used to force FX
      // off with no way to say otherwise (see [CelsExportSpec.applyLayerFx]);
      // 유저 2026-08-27 made it a choice. Same accordion, same toggle row,
      // same key prefix as the Sequence and Image tabs — one control, three
      // places, rather than a fourth idea of what this question looks like.
      _fxAccordion(
        keyValue: 'export-cels-apply-fx-toggle',
        label: AppText.strings.exApplyLayerFxHelp,
        applyLayerFx: spec.applyLayerFx,
        onChanged: (value) => _updateSpec(spec.copyWith(applyLayerFx: value)),
      ),
    ];
  }

  /// The Cels tab's naming module. Its reset puts the spec's naming AND the
  /// fields that show it back — the suffix's and every kind's prefix.
  ExportAccordion _celNamingAccordion(CelsExportSpec spec) => _namingAccordion(
    // The collapsed summary IS the first file's name — the one example
    // the user can read (유저: 「미리보기 이름이니까 … 삭제」 of the
    // editable-looking example line).
    summary: _patternPreview(),
    isDefault: spec.naming == const ExportCelNaming(),
    onReset: () {
      _updateSpec(spec.copyWith(naming: const ExportCelNaming()));
      _celSuffixController.text = '';
      _syncCelPrefixFields();
    },
    child: ExportCelNamingModule(
      naming: spec.naming,
      enabled: !_isExporting,
      suffixController: _celSuffixController,
      prefixControllers: _celPrefixControllers,
      onChanged: (naming) => _updateSpec(spec.copyWith(naming: naming)),
    ),
  );

  /// 타임시트 형식: its pages as pictures — PNG or JPG — or the digital sheet.
  ExportAccordion _sheetFormatAccordion(CelsExportSpec spec) {
    final pictured = spec.sheetFormat == ExportTimesheetFormat.sheetImage;
    return ExportAccordion(
      title: AppText.strings.exTimesheetFormat,
      summary: pictured
          ? ExportPaperFormatModule.summarize(spec.sheetImage)
          : 'XDTS',
      expansion: _expansion('sheet-format', open: true),
      child: ExportPaperFormatModule(
        keyPrefix: 'export-tsformat',
        label: AppText.strings.exFormat,
        image: spec.sheetImage,
        pictured: pictured,
        onImageChanged: _isExporting
            ? null
            : (image) => _updateSpec(
                spec.copyWith(
                  sheetFormat: ExportTimesheetFormat.sheetImage,
                  sheetImage: image,
                ),
              ),
        after: [
          _pill(
            keyValue: 'export-tsformat-xdts',
            label: 'XDTS',
            selected: !pictured,
            onPick: () => _updateSpec(
              spec.copyWith(sheetFormat: ExportTimesheetFormat.xdts),
            ),
          ),
        ],
      ),
    );
  }

  /// 컷봉투 형식: the picture it is written as, and the paper it is written
  /// on — the cut's own pixels, or the real envelope's paper (유저
  /// 2026-10-05: 「기존의 컷봉투탭에 있던 용지는 컷크기/실측용지 이거는 컷봉투
  /// 형식안에 넣고」).
  ExportAccordion _envelopeFormatAccordion(CelsExportSpec spec) {
    final strings = AppText.strings;
    final cutPaper = spec.envelopePaper == CutEnvelopePaperMode.cut;
    return ExportAccordion(
      title: strings.exEnvelopeFormat,
      summary:
          '${ExportPaperFormatModule.summarize(spec.envelopeImage)} · '
          '${cutPaper ? strings.exCutSize : strings.exRealSheet}',
      expansion: _expansion('envelope-format', open: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExportPaperFormatModule(
            keyPrefix: 'export-envelope-format',
            label: strings.exImage,
            image: spec.envelopeImage,
            onImageChanged: _isExporting
                ? null
                : (image) => _updateSpec(spec.copyWith(envelopeImage: image)),
          ),
          ExportModuleRow(
            label: strings.exPaperLabel,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PillStrip(
                items: [
                  _pill(
                    keyValue: 'export-envelope-paper-cut',
                    label: strings.exCutSize,
                    selected: cutPaper,
                    onPick: () => _updateSpec(
                      spec.copyWith(envelopePaper: CutEnvelopePaperMode.cut),
                    ),
                  ),
                  _pill(
                    keyValue: 'export-envelope-paper-sheet',
                    label: strings.exRealSheet,
                    selected: !cutPaper,
                    onPick: () => _updateSpec(
                      spec.copyWith(envelopePaper: CutEnvelopePaperMode.sheet),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The conte sheet: one vector PDF, or its pages as pictures — PNG or JPG
  /// (유저 2026-10-05: 「콘티용지도 pdf면 단일파일, 그 외 사진파일이면
  /// 폴더피커. 시트 그리고 png말고 jpg도 추가」).
  List<Widget> _conteModules() {
    final spec = _specs.conte;
    final pictured = spec.format == ExportConteFormat.pageImage;
    return [
      // One name for the book in either format: the PDF's, and the base of
      // its pages' as pictures — the module keeps its place when the format
      // changes.
      _nameAccordion(
        controller: _conteFileController,
        extension: pictured ? spec.image.stillFormat.fileExtension : 'pdf',
      ),
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: pictured
            ? ExportPaperFormatModule.summarize(spec.image)
            : AppText.strings.exVectorPdf,
        expansion: _expansion('format', open: true),
        child: ExportPaperFormatModule(
          keyPrefix: 'export-conteformat',
          label: AppText.strings.exFormat,
          image: spec.image,
          pictured: pictured,
          onImageChanged: _isExporting
              ? null
              : (image) => _updateSpec(
                  spec.copyWith(
                    format: ExportConteFormat.pageImage,
                    image: image,
                  ),
                ),
          before: [
            _pill(
              keyValue: 'export-conteformat-pdf',
              label: 'PDF',
              selected: !pictured,
              onPick: () =>
                  _updateSpec(spec.copyWith(format: ExportConteFormat.pdf)),
            ),
          ],
        ),
      ),
    ];
  }

  /// The naming accordion an export tab offers: the same title, the same
  /// `naming` fold key, and a reset that puts BOTH the spec field and its
  /// text controller back.
  ///
  /// ⛔THE RESET IS THE PART THAT DRIFTS. Each tab wrote this out, and the
  /// reset has two halves — the spec's default and the controller's text.
  /// A tab that reset one and not the other shows a field the export no
  /// longer uses, which is the setting that lies.
  ExportAccordion _namingAccordion({
    required String summary,
    required bool isDefault,
    required VoidCallback onReset,
    required Widget child,
  }) => ExportAccordion(
    title: AppText.strings.exNaming,
    summary: summary,
    expansion: _expansion('naming'),
    reset: (enabled: !isDefault, onTap: onReset),
    child: child,
  );

  /// The layer-fx switch every raster tab offers — 유저 2026-08-27 made it
  /// a choice on the Cels tab too, so it is one control on three tabs.
  ///
  /// ⛔THE PREVIEW CLEAR IS PART OF THE SWITCH. Flipping fx changes what
  /// renders, and a tab that flipped the spec without clearing would keep
  /// showing the picture the OTHER setting made. [keyValue] and [label]
  /// stay each tab's own: the keys name their tab, and one tab's label
  /// carries the longer help line.
  ExportAccordion _fxAccordion({
    required String keyValue,
    required String label,
    required bool applyLayerFx,
    required void Function(bool applyLayerFx) onChanged,
  }) => ExportAccordion(
    title: AppText.strings.exOptions,
    summary: applyLayerFx ? AppText.strings.exFxOn : AppText.strings.exFxOff,
    expansion: _expansion('options'),
    child: SettingsSwitchRow(
      tileKey: ValueKey<String>(keyValue),
      label: label,
      value: applyLayerFx,
      onChanged: _isExporting
          ? null
          : (value) {
              onChanged(value);
            },
    ),
  );

  /// A toggle row bound to the tab's spec: DEAD while an export runs, and
  /// a change writes the spec [write] answers. Six rows wrote that binding
  /// out; a run in flight owns the spec, so one place says it — the same
  /// law [_chip] states for the chips. [_fxAccordion]'s row is not this: its
  /// preview clear is part of the switch.
  SettingsSwitchRow _specToggle({
    required String keyValue,
    required String label,
    required bool value,
    required ExportTabSpec Function(bool value) write,
  }) => SettingsSwitchRow(
    tileKey: ValueKey<String>(keyValue),
    label: label,
    value: value,
    onChanged: _isExporting ? null : (value) => _updateSpec(write(value)),
  );

  /// The Size accordion three tabs offer: one title, one fold key, one
  /// enabled law. What differs per tab is values — which canvas sizes are
  /// on the table, whether the scope is the project, whether it opens by
  /// default — the same shape [_scopeAccordion] was extracted for.
  ExportAccordion _sizeAccordion({
    required ExportSizeMode sizeMode,
    required Set<CanvasSize> canvasSizes,
    required bool projectScope,
    required bool open,
    required void Function(ExportSizeMode mode) onChanged,
  }) => ExportAccordion(
    title: AppText.strings.exSize,
    summary: ExportSizeModule.summarize(sizeMode),
    expansion: _expansion('size', open: open),
    child: ExportSizeModule(
      sizeMode: sizeMode,
      cameraSize: _session.camera.cameraFrameSize,
      canvasSizes: canvasSizes,
      projectScope: projectScope,
      enabled: !_isExporting,
      onChanged: onChanged,
    ),
  );

  /// The still-only format lineup the Image and Cels tabs share; the
  /// Sequence tab's table carries video and is its own value.
  ExportFormatCapabilities get _stillOnlyCapabilities =>
      ExportFormatCapabilities(
        stills: const [
          ExportStillFormat.png,
          ExportStillFormat.jpg,
          ExportStillFormat.psd,
        ],
        stillEnabled: _availability.stillAllowed,
      );

  /// The "this cut or the whole film" accordion every tab offers.
  ///
  /// ⛔ONE SCOPE CONTROL. Five tabs wrote out the title, the summarize
  /// call and the enabled pair; what actually differs is the fold key,
  /// whether it opens by default, and what rides inside it — the cut grid.
  ExportAccordion _scopeAccordion({
    required ExportScopeKind scope,
    required void Function(ExportScopeKind scope) onChanged,
    ({String key, bool open}) fold = (key: 'scope', open: false),
    Widget? child,
  }) => ExportAccordion(
    title: AppText.strings.exScope,
    summary: ExportScopeModule.summarize(scope),
    expansion: _expansion(fold.key, open: fold.open),
    child: ExportScopeModule(
      scope: scope,
      enabled: !_isExporting,
      onChanged: onChanged,
      child: child,
    ),
  );

  Widget _queueZone({required bool open}) {
    if (!open) {
      return ExportDrawerStrip(
        key: const ValueKey<String>('export-queue-strip'),
        caption: AppText.strings.exQueue,
        chevron: Icons.chevron_left,
        badgeCount: _queue.jobs.length,
        onTap: () {
          setState(() => _queueOpen = true);
          _persist();
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ControlPressClaim(
            onPressed: () {
              setState(() => _queueOpen = false);
              _persist();
            },
            child: InkWell(
              key: const ValueKey<String>('export-queue-collapse'),
              onTap: silentPress(() {
                setState(() => _queueOpen = false);
                _persist();
              }),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.chevron_right, size: 13),
              ),
            ),
          ),
        ),
        Expanded(
          child: ExportQueueColumn(
            queue: _queue,
            enabled: !_isExporting,
            onRemove: _removeJob,
            onRestore: _restoreJob,
            onRenderAll: _isExporting || _queue.nextQueued == null
                ? null
                : () => unawaited(runQueue()),
          ),
        ),
      ],
    );
  }
}

/// What an image export counts, said in the program language: the finished
/// sentence names the kind (「3 sheet pages」), the stopped one only the noun
/// (「after 3 pages」) — the two shapes the English sentences already had.
enum _Tally {
  frames,
  cels,
  contePages,

  /// A run of more than one kind of file: the Cels tab's cels beside its
  /// documents.
  files;

  String kept(AppStrings strings, int count) => switch (this) {
    _Tally.frames => strings.exFrameCount(count),
    _Tally.cels => strings.exCelCount(count),
    _Tally.contePages => strings.exPageCount(count),
    _Tally.files => strings.exFileCount(count),
  };

  String done(AppStrings strings, int count) => switch (this) {
    _Tally.frames => strings.exFrameCount(count),
    _Tally.cels => strings.exCelCount(count),
    _Tally.contePages => strings.exContePageCount(count),
    _Tally.files => strings.exFileCount(count),
  };
}

/// One picture file of a run: where it is written, what it is, and the
/// encoder its format asks for (null is the default PNG).
typedef _PictureFile = ({
  String fileName,
  Future<ui.Image?> Function() render,
  ExportImageEncoder? encoder,
});
