import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/argb_channels.dart';
import '../../models/kept_span.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import '../../models/sheet_paper.dart';
import '../../native/qa_image_encoder.dart';
import '../../services/audio/audio_mixer_reference.dart' show AudioMixSource;
import '../../services/brush_frame_store.dart' show CelRead;
import '../../services/export/xdts_builder.dart';
import '../../services/persistence/app_export_settings.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../../services/persistence/app_save_settings.dart'
    show GrantedDirectory;
import '../../services/persistence/folder_grant.dart' show FolderPicker;
import '../../services/persistence/session_scratch.dart';
import '../../services/project_lookup.dart' show cutPositionOf;
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
import '../../models/sheet_paint_layer.dart';
import '../../models/envelope/cut_envelope_presets.dart';
import '../../models/project.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../widgets/checkered_picture.dart';
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
import 'export_nav_bar.dart';
import 'export_plan.dart';
import 'export_preset_rail.dart';
import 'export_preview_engine.dart';
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
import '../widgets/app_window.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../text/app_face.dart';
import '../text/app_strings.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;
import '../widgets/cursor_notice.dart';
import '../widgets/pill_strip.dart';

/// Picks the output directory (the Browse… button); `null` on cancel.
typedef ExportDirectoryPicker = Future<String?> Function();

/// The v10 export window: five zones (file/location bar → presets |
/// preview | settings | queue → footer), four tabs, location-first flow —
/// Export starts immediately, files land in the chosen location.
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

  /// Injectable for tests; defaults to the platform directory picker.
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

  /// Where the outputs go; null until the user picks. A folder carries the
  /// security-scoped token the OS issued for it (macOS/iOS), which is what
  /// lets the replayed location be WRITTEN to after a relaunch, not just
  /// displayed (Q-scoped-folder-settings, 유저 08-26). 「끝나면 고르기」
  /// (drive-folder-windows-Q1) writes into an outbox of the run's own
  /// ([_runOutbox]) and [handOverFilesForUser] takes it from there.
  ///
  /// ⚠️ONE value on purpose. The path and its token were two fields kept
  /// together by one setter — a bookmark that outlived its path is a grant
  /// for somewhere else — and 「끝나면 고르기」 would have made a third to
  /// keep apart from them. As one value, no code can leave half of a
  /// destination behind.
  ExportDestination? _destination;

  /// The chosen folder's path; null while the outputs are handed over or
  /// nothing is chosen.
  String? get _location => switch (_destination) {
    ExportIntoFolder(:final folder) => folder.path,
    _ => null,
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
  late final TextEditingController _inController = TextEditingController();
  late final TextEditingController _outController = TextEditingController();
  late final TextEditingController _namingBaseController;
  late final TextEditingController _celSuffixController;

  /// The naming module's prefix fields, one a kind.
  late final Map<ExportCelKind, TextEditingController> _celPrefixControllers = {
    for (final kind in ExportCelKind.values) kind: TextEditingController(),
  };

  bool _isExporting = false;
  bool _cancelRequested = false;
  String? _statusMessage;
  (int completed, int total)? _progress;

  // EX3: the preview loop — one controller; renderers key on (FX,
  // background) since EX4 made both change what a frame looks like.
  final ExportPreviewController _preview = ExportPreviewController();
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
  int _sheetPosition = 0;
  int _contePosition = 0;
  int _envelopePosition = 0;
  // Sheet documents are chunky to derive; the modal dialog memoizes per
  // cut IDENTITY (the film cannot change under an open dialog).
  final Map<CutId, (Cut, TimesheetDocument, TimesheetDocumentLayout)>
  _sheetDocs = {};
  // The conte sheet reads the WHOLE project — memoized on its identity
  // (the film cannot change under an open dialog).
  (Object, ConteSheetSource, List<ContePageLayout>)? _conteSheetCache;
  static const int _previewMaxWidth = 316;
  static const int _previewMaxHeight = 300;

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
    _destination = restored.lastDestination;
    _presetsOpen = restored.presetsDrawerOpen;
    _queueOpen = restored.queueDrawerOpen;
    final projectName = sanitizeExportFileComponent(
      _session.repository.requireProject().name,
    );
    _sequenceFileController = TextEditingController(text: '$projectName.mp4');
    _imageFileController = TextEditingController(text: '$projectName.png');
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
          .withSpec(_specs.cels.copyWith(scope: ExportScopeKind.project))
          .withSpec(_specs.timesheet.copyWith(scope: ExportScopeKind.project));
    }
    _syncControllersFromSpecs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshPreview();
      }
    });
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
      _destination = loaded.lastDestination ?? _destination;
      _presetsOpen = loaded.presetsDrawerOpen;
      _queueOpen = loaded.queueDrawerOpen;
      _syncControllersFromSpecs();
    });
    unawaited(_resolveLocationGrant());
  }

  /// Reopens the replayed location's scope for this run — on macOS a
  /// stored path without its resolved bookmark is refused at the first
  /// write, silently. Follows a folder the user renamed, and persists
  /// only when something actually moved. A token that will not resolve
  /// leaves the folder untouched (unavailable is not deleted), and so does
  /// a destination the user changed while the token was resolving.
  Future<void> _resolveLocationGrant() async {
    final replayed = _destination;
    if (replayed is! ExportIntoFolder) {
      return;
    }
    final token = replayed.folder.bookmark;
    if (token == null) {
      return;
    }
    final grant = await FolderPicker.resolveBookmark(token);
    final path = grant.path;
    if (!mounted ||
        !grant.isGranted ||
        path == null ||
        !identical(_destination, replayed)) {
      return;
    }
    final moved = path != replayed.folder.path;
    setState(
      () => _destination = ExportIntoFolder(
        GrantedDirectory(path: path, bookmark: grant.bookmark ?? token),
      ),
    );
    if (moved) {
      _persist();
    }
  }

  @override
  void dispose() {
    _sequenceFileController.dispose();
    _imageFileController.dispose();
    _inController.dispose();
    _outController.dispose();
    _namingBaseController.dispose();
    _celSuffixController.dispose();
    for (final controller in _celPrefixControllers.values) {
      controller.dispose();
    }
    _queue.dispose();
    _notices.dispose();
    _preview.dispose();
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
    // -1 keys the transparent background (RGBA outputs).
    final bgKey = format.wantsAlpha ? -1 : format.backgroundArgb;
    return _previewRenderers.putIfAbsent(
      (applyLayerFx, bgKey),
      () => ExportFrameRenderer(
        session: _session,
        applyLayerFx: applyLayerFx,
        background: bgKey == -1 ? const ui.Color(0x00000000) : ui.Color(bgKey),
      ),
    );
  }

  // --- state plumbing -------------------------------------------------------

  void _persist() {
    final next = AppExport.settings.value.copyWith(
      lastSpecs: _specs,
      lastDestination: _destination,
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
    _refreshPreview();
  }

  void _syncControllersFromSpecs() {
    _namingBaseController.text = _specs.sequence.naming.baseName;
    _celSuffixController.text = _specs.cels.naming.suffix;
    _syncCelPrefixFields();
    _inController.text = _specs.sequence.inFrame == null
        ? ''
        : '${_specs.sequence.inFrame! + 1}';
    _outController.text = _specs.sequence.outFrame == null
        ? ''
        : '${_specs.sequence.outFrame! + 1}';
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

  /// The preview picture — the cropped result alone (v10: 오버레이 없음), or
  /// the plan headline while nothing has resolved.
  Widget _previewWell(ThemeData theme) => Container(
    decoration: ShapeDecoration(
      shape: AppShapes.container(
        AppShapes.wellRadius,
        side: BorderSide(color: theme.dividerColor),
      ),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(8),
    child: AnimatedBuilder(
      animation: _preview,
      builder: (context, _) {
        final image = _preview.image;
        if (image == null) {
          return Text(
            _planHeadline(),
            key: const ValueKey<String>('export-plan-headline'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          );
        }
        final picture = RawImage(
          key: const ValueKey<String>('export-preview-image'),
          image: image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        );
        if (!_previewShowsAlpha()) {
          return picture;
        }
        // Open alpha reads as the checkerboard, not as nothing — the same
        // checker the canvas's alpha preview paints (유저 2026-09-09: 「투명
        // 이라는 의미의 체크무늬 … 이미있으면 있던거 쓰고」). It sits under
        // the picture's own box, so it shows exactly where the file is open.
        return CheckeredPicture(
          image: image,
          checkerKey: const ValueKey<String>('export-preview-checker'),
          imageKey: const ValueKey<String>('export-preview-image'),
        );
      },
    ),
  );

  /// Whether the picture under preview is written with open alpha: the
  /// still formats' channels, or the envelope without its paper. One
  /// answer for every tab's preview, so the checker appears wherever a
  /// file would be open.
  bool _previewShowsAlpha() => switch (_tab) {
    ExportTab.sequence => _specs.sequence.format.wantsAlpha,
    ExportTab.image => _specs.image.format.wantsAlpha,
    ExportTab.cels => _specs.cels.format.wantsAlpha,
    ExportTab.envelope =>
      !_specs.envelope.layers.contains(SheetPaintLayer.paper),
    ExportTab.timesheet || ExportTab.conte => false,
  };

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
    final rows = ExportCelsListing(cut, _specs.cels).rows(
      selection: _celsSelectionOf(cut),
      sheets: plan.sheets.where((sheet) => sheet.cut.id == cut.id),
      shut: _celShut,
    );
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
    final pages = row == null
        ? const <ExportCelSheet>[]
        : exportCelsPages(row);
    final at = pages.indexWhere((sheet) => sheet.frame.id == standing.shown);
    return ExportCelsBoard(
      rules: _celRules(cut),
      band: ExportCelsBand(
        cutPicker: _celCutPicker(plan, cut),
        count: AppText.strings.exCelCount(plan.length),
        onStep: _isExporting ? null : _stepCel,
        canStepBack: at > 0,
        canStepOn: at >= 0 && at < pages.length - 1,
        directions: _celDirections(cut, standing.sheetIn(rows)),
      ),
      rows: rows,
      layers: cut.layers,
      standing: row?.layer.id,
      shown: standing.shown,
      enabled: !_isExporting,
      onRowSwitched: (row, on) => _toggleCelRows(
        cut,
        row.isFolder
            ? ExportCelsListing(cut, _specs.cels).leavesOf(row.layer)
            : [row.layer],
        on,
      ),
      onFolded: _foldCelRow,
      onStoodOn: (row) => _standCels(
        (standing, rows) => standing.standingOn(row.layer.id, rows),
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
    _refreshPreview();
  }

  void _stepCel(int steps) =>
      _standCels((standing, rows) => standing.stepped(steps, rows));

  /// A twirl, pressed: what the row holds under it folds away, or comes
  /// back. The window's own fold — the film's folds are the film's.
  void _foldCelRow(ExportCelsBoardRow row) {
    setState(() {
      if (!_celShut.remove(row.layer.id)) {
        _celShut.add(row.layer.id);
      }
    });
    _refreshPreview();
  }

  /// A block, pressed: a drawing the export would write is turned off, or
  /// back on — and one it would not says why, where the pointer is
  /// (유저 2026-10-06: 「나갈 수 없는 그림은 작동하려하면 이유 띄우자」).
  void _pressCelSheet(ExportCelSheet sheet) {
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
    _editCelDelta(
      sheet.cut.id,
      (delta) => delta.withCelSkipped(sheet.ref, !sheet.skipped),
    );
  }

  /// The direction drawings of [cut] the band offers to lay over [shown],
  /// each lit while it is laid. Nothing is laid over a direction row's own
  /// drawing, and nothing while no drawing is shown: the pills keep their
  /// place and take no press.
  List<ExportCelsDirection> _celDirections(Cut cut, ExportCelSheet? shown) {
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
          _refreshPreview();
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

  /// The 0-based in/out marks on the SEQUENCE AXIS (cut-local frames
  /// under the cut scope, whole-track positions under the project scope);
  /// `null` = the fields don't form a valid range right now.
  (int?, int?)? _sequenceInOut() {
    int? parse(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) {
        return null;
      }
      final value = int.tryParse(raw);
      return (value == null || value < 1) ? -1 : value - 1;
    }

    final inFrame = parse(_inController);
    final outFrame = parse(_outController);
    if (inFrame == -1 || outFrame == -1) {
      return null;
    }
    if (inFrame != null && outFrame != null && inFrame > outFrame) {
      return null;
    }
    return (inFrame, outFrame);
  }

  /// The FULL sequence axis (untrimmed, gapless): what the nav bar scrubs
  /// and the in/out marks live on.
  List<ExportFrameTask> _sequenceAxisPlan() {
    final spec = _specs.sequence;
    return buildExportFramePlan(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      range: spec.scope == ExportScopeKind.project
          ? ExportRange.allCuts
          : ExportRange.activeCut,
    );
  }

  /// The frames an export actually renders: the axis sliced by in/out.
  /// `null` while the fields are invalid. An UNTRIMMED project-scope video
  /// keeps the gap black frames (full-track sync, the old behavior); a
  /// trimmed range is content-only.
  List<ExportFrameTask>? _sequencePlanForRun({required bool video}) {
    final spec = _specs.sequence;
    final inOut = _sequenceInOut();
    if (inOut == null) {
      return null;
    }
    final (inFrame, outFrame) = inOut;
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
    );
    _celPlanCache = (project, spec, plan);
    return plan;
  }

  (Object, CelsExportSpec, ExportCelGroupPlan)? _celPlanCache;

  List<Cut> _timesheetCuts() => exportCutsInScope(
    project: _session.repository.requireProject(),
    activeCutId: _activeCut.id,
    scope: _specs.timesheet.scope,
    overrides: _overrides,
  );

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

  List<ExportTimesheetPageTask> _timesheetPagePlan() {
    final tasks = <ExportTimesheetPageTask>[];
    for (final cut in _timesheetCuts()) {
      final label = cut.name;
      final fileLabel = sanitizeExportFileComponent(label);
      final (_, document, _) = _sheetDocFor(cut);
      final pageCount = document.pages.length;
      for (var page = 0; page < pageCount; page += 1) {
        tasks.add(
          ExportTimesheetPageTask(
            cut: cut,
            cutLabel: label,
            cutStartFrame: _trackStartOf(cut),
            pageIndex: page,
            pageCount: pageCount,
            fileName: pageCount == 1
                ? 'CUT$fileLabel.png'
                : 'CUT${fileLabel}_p${page + 1}.png',
          ),
        );
      }
    }
    return tasks;
  }

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

  String _contePageFileName(int index, int pageCount) =>
      pageCount == 1 ? 'conte.png' : 'conte_p${index + 1}.png';

  /// The envelopes in scope — ONE per sheet, not one per cut.
  ///
  /// A 겸용 cut and its siblings share a single envelope (the folder they
  /// share in the studio), so the plan is keyed by the sheet's OWNER cut
  /// and a sibling that is also in scope adds no second file.
  List<ExportEnvelopeTask> _envelopePlan() {
    final spec = _specs.envelope;
    final project = _session.repository.requireProject();
    // Five things per build ask for this plan (headline, output line,
    // transport, canExport, nav bar) and each task lays out a form and
    // reads the whole project, so it is memoized on what it depends on:
    // the project's identity and the spec.
    final cached = _envelopePlanCache;
    if (cached != null && identical(cached.$1, project) && cached.$2 == spec) {
      return cached.$3;
    }
    final plan = _buildEnvelopePlan(spec, project);
    _envelopePlanCache = (project, spec, plan);
    return plan;
  }

  (Object, EnvelopeExportSpec, List<ExportEnvelopeTask>)? _envelopePlanCache;

  List<ExportEnvelopeTask> _buildEnvelopePlan(
    EnvelopeExportSpec spec,
    Project project,
  ) {
    // The work's form, the one the panel shows (유저 답
    // envelope-form-in-export: the export follows it).
    final form = CutEnvelopePresets.byId(project.timesheetInfo.envelopeFormId);
    final cuts = exportCutsInScope(
      project: project,
      activeCutId: _activeCut.id,
      scope: spec.scope,
      overrides: project.exportOverrides,
    );
    final tasks = <ExportEnvelopeTask>[];
    final seen = <CutId>{};
    for (final cut in cuts) {
      final ownerId = cutEnvelopeInkOwner(project, cut.id);
      if (!seen.add(ownerId)) {
        continue;
      }
      // The sheet belongs to the owner: its canvas sizes the cut-fitted
      // paper and its name the file, whichever sibling was in scope.
      final owner = cutPositionOf(project, ownerId)?.cut ?? cut;
      final paper = cutEnvelopePaperSize(
        mode: spec.paperMode,
        cut: owner,
        sheetScale: spec.sheetScale,
      );
      tasks.add(
        ExportEnvelopeTask(
          owner: owner,
          layout: CutEnvelopeLayout.fit(
            form: form,
            paperWidth: paper.width.toDouble(),
            paperHeight: paper.height.toDouble(),
          ),
          source: buildCutEnvelopeSource(project: project, cut: owner),
        ),
      );
    }
    return tasks;
  }

  /// One output file: the sheet, plus the stratum when the layers ship
  /// separately.
  String _envelopeFileName(ExportEnvelopeTask task, SheetPaintLayer? layer) {
    final label = sanitizeExportFileComponent(task.owner.name);
    return layer == null
        ? 'CUT${label}_envelope.png'
        : 'CUT${label}_envelope_${layer.jsonValue}.png';
  }

  /// Every (sheet, layer) pair the run writes, in order. A flat export
  /// carries a null layer — one file drawing all the enabled strata.
  List<(ExportEnvelopeTask, SheetPaintLayer?)> _envelopeFilePlan() {
    final spec = _specs.envelope;
    final tasks = _envelopePlan();
    return [
      for (final task in tasks)
        if (spec.separateLayerFiles)
          for (final layer in spec.orderedLayers) (task, layer)
        else
          (task, null),
    ];
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
      );
      if (image != null) {
        images[key] = image;
      }
    }
    return images;
  }

  /// One envelope image, with the ink composed and freed around it.
  ///
  /// ⛔THE EXPORT AND THE PREVIEW RENDER THROUGH HERE. They differ only in
  /// [outputSize] (the preview fits its pane); rendered separately, the
  /// preview showed a picture the file would not have been.
  Future<ui.Image> _renderEnvelope(
    ExportEnvelopeTask task, {
    required TextStyle face,
    required Set<SheetPaintLayer> layers,
    ({int width, int height})? outputSize,
  }) async {
    final wantsInk = layers.contains(SheetPaintLayer.ink);
    final ink = wantsInk
        ? await _renderSheetInk([
            for (final window in envelopeInkWindows(
              task.layout,
              task.owner.id,
            ))
              window.key,
          ])
        : const <BrushFrameKey, ui.Image>{};
    try {
      return await renderCutEnvelopeImage(
        layout: task.layout,
        source: task.source,
        face: face,
        layers: layers,
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
  /// only in [outputSize] against [scale].
  ///
  /// The ink is the page's windows of the panel's own walk
  /// ([timesheetInkWindows]) — until 2026-09-26 the timesheet exported no
  /// ink at all (유저: 「다 통일해줘. 기능은 어차피 생길수있어」).
  Future<ui.Image> _renderSheetPage(
    ExportTimesheetPageTask task, {
    required TextStyle face,
    double scale = 2,
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
        scale: scale,
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
    double scale = 1,
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
        scale: scale,
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

  /// The Image tab's frame: the nav bar owns it (seeded from the editing
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

  /// Test seam: awaits the debounced preview render (call inside
  /// `tester.runAsync` so the raster completes).
  @visibleForTesting
  Future<void> debugFlushPreview() => _preview.debugFlushPending();

  /// Test seam: the size the conte's cell pictures were last rendered at —
  /// what a page-image run asks, which its PNG files cannot tell a test.
  @visibleForTesting
  CanvasSize? get debugContePictureSize => _contePictureSize;
  CanvasSize? _contePictureSize;

  /// Test seam: sets the destination without the platform picker.
  @visibleForTesting
  void debugSetLocationForTests(String location) {
    setState(
      () => _destination = ExportIntoFolder(GrantedDirectory(path: location)),
    );
  }

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

  // --- preview (EX3) --------------------------------------------------------

  ExportNavAxis _sequenceAxis(List<ExportFrameTask> plan) =>
      ExportNavAxis.grouped(
        entries: plan,
        groupOf: (task) => task.cut.id,
        captionOf: (position) => 'F${position + 1}',
      );

  ExportNavAxis _imageAxis() => ExportNavAxis(
    length: math.max(1, _activeCut.duration),
    captionOf: (position) => 'F${position + 1}',
  );

  ExportNavAxis _timesheetAxis(List<ExportTimesheetPageTask> plan) =>
      ExportNavAxis.grouped(
        entries: plan,
        groupOf: (task) => task.cut.id,
        captionOf: (position) {
          final task = plan[position.clamp(0, plan.length - 1)];
          return 'CUT${task.cutLabel}·p${task.pageIndex + 1}';
        },
      );

  /// The size the preview renders at: [width]×[height] fitted into the
  /// panel's budget, or null when it already fits (render at full size).
  ///
  /// ⚠️ONE budget for every tab. Four call sites spelled the same
  /// four-argument call and the same null-or-[CanvasSize] line after it,
  /// each rounding its own pair of doubles — a preview that fits on one tab
  /// and overflows on another is the drift that shape invites.
  CanvasSize? _previewFit(num width, num height) {
    final fitted = previewOutputSize(
      sourceWidth: width.round(),
      sourceHeight: height.round(),
      maxWidth: _previewMaxWidth,
      maxHeight: _previewMaxHeight,
    );
    return fitted == null
        ? null
        : CanvasSize(width: fitted.width, height: fitted.height);
  }

  /// The entry the preview is parked on: [position] clamped into [plan] and
  /// written back through [park]. Null — with the well CLEARED — when the
  /// plan holds nothing.
  ///
  /// 🚨ONE ANSWER TO 「보여줄 게 없다」. Four tabs spelled the empty-check,
  /// the clamp and the write-back themselves, and the sequence tab spelled
  /// it WITHOUT the clear — a fifth answer to the same question, which
  /// would have left a stale picture in the well the day a project with no
  /// frames reached it.
  T? _parkedPreviewEntry<T>(
    List<T> plan,
    int position,
    void Function(int) park,
  ) {
    if (plan.isEmpty) {
      _preview.clear();
      return null;
    }
    final index = position.clamp(0, plan.length - 1);
    park(index);
    return plan[index];
  }

  /// Re-aims the preview at whatever the tab currently points at. Called
  /// after every spec/nav/tab change; requests coalesce in the controller.
  ///
  /// ⚠️THE SWITCH STAYS A SWITCH. Nine questions in this window dispatch on
  /// [_tab] and a tab-shaped object would gather them — but the set of tabs
  /// is the product's closed list, and Dart's exhaustive switch already
  /// refuses to compile until a new one is answered EVERYWHERE. What the
  /// cases must not hold is a second copy of a shared step; that is what
  /// [_previewFit] and [_parkedPreviewEntry] above are.
  void _refreshPreview() {
    switch (_tab) {
      case ExportTab.sequence:
        _refreshSequencePreview();
      case ExportTab.image:
        _refreshImagePreview();
      case ExportTab.cels:
        _refreshCelsPreview();
      case ExportTab.timesheet:
        _refreshTimesheetPreview();
      case ExportTab.conte:
        _refreshContePreview();
      case ExportTab.envelope:
        _refreshEnvelopePreview();
    }
  }

  void _refreshSequencePreview() {
    final spec = _specs.sequence;
    final task = _parkedPreviewEntry(
      _sequenceAxisPlan(),
      _sequencePosition,
      (index) => _sequencePosition = index,
    );
    if (task == null) {
      return;
    }
    _requestCompositePreview(
      task: task,
      sizeMode: spec.sizeMode,
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
      caption: 'F${_sequencePosition + 1}',
    );
  }

  void _refreshImagePreview() {
    final spec = _specs.image;
    _requestCompositePreview(
      task: ExportFrameTask(cut: _activeCut, frameIndex: _currentImageFrame()),
      sizeMode: spec.sizeMode,
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
      caption: 'F${_currentImageFrame() + 1}',
    );
  }

  void _refreshCelsPreview() {
    final spec = _specs.cels;
    final (plan: _, cut: _, :rows, :standing) = _celsList();
    // Where the list stands is settled HERE, on the way to the picture: a
    // row that left the list or a drawing that was turned off is not kept
    // stood on behind the board's back.
    _celStanding = standing;
    final sheet = standing.sheetIn(rows);
    if (sheet == null) {
      _preview.clear();
      return;
    }
    final format = spec.format;
    final renderer = _previewRendererFor(
      // The preview shows what the export writes — same switch.
      applyLayerFx: spec.applyLayerFx,
      format: format,
    );
    _preview.request(
      key: celGroupPreviewKey(
        sheet.look,
        sizeMode: spec.sizeMode.jsonValue,
        backgroundKey: format.wantsAlpha ? -1 : format.backgroundArgb,
        applyLayerFx: spec.applyLayerFx,
      ),
      caption: sheet.celName,
      render: () => renderer.renderCelGroup(sheet.look, spec.sizeMode),
    );
  }

  void _refreshTimesheetPreview() {
    final task = _parkedPreviewEntry(
      _timesheetPagePlan(),
      _sheetPosition,
      (index) => _sheetPosition = index,
    );
    if (task == null) {
      return;
    }
    final (_, _, layout) = _sheetDocFor(task.cut);
    final page = layout.pageRect(task.pageIndex);
    final outputSize = _previewFit(page.width, page.height);
    final face = _documentFace;
    _preview.request(
      key: 'sheet:${task.cut.id.value}:${task.pageIndex}:${face.fontFamily}',
      caption: 'p${task.pageIndex + 1}',
      render: () => _renderSheetPage(task, face: face, outputSize: outputSize),
    );
  }

  void _refreshContePreview() {
    final (source, pages) = _conteSheet();
    final page = _parkedPreviewEntry(
      pages,
      _contePosition,
      (index) => _contePosition = index,
    );
    if (page == null) {
      return;
    }
    final outputSize = _previewFit(
      page.metrics.pageWidth,
      page.metrics.pageHeight,
    );
    // The printed words are in the key: switching the notation language
    // must not show the other language's cached page.
    final language = _notationLanguage;
    final words = conteWordsIn(language);
    _preview.request(
      key: 'conte:${page.pageIndex}:${language.name}',
      caption: 'p${page.pageIndex + 1}',
      // Preview pictures at panel resolution — fast, and the run
      // re-renders sharper ones anyway.
      render: () => _renderContePage(
        page,
        source,
        pictureWidth: 128,
        outputSize: outputSize,
        words: words,
      ),
    );
  }

  void _refreshEnvelopePreview() {
    final task = _parkedPreviewEntry(
      _envelopePlan(),
      _envelopePosition,
      (index) => _envelopePosition = index,
    );
    if (task == null) {
      return;
    }
    final spec = _specs.envelope;
    final fitted = _previewFit(
      task.layout.paperWidth,
      task.layout.paperHeight,
    );
    final face = _documentFace;
    _preview.request(
      // Every setting that changes the picture is in the key: two
      // different layer sets of the same SIZE must not share a
      // cached render.
      key:
          'envelope:${task.owner.id.value}:${task.layout.form.id}:'
          '${spec.paperMode.toJson()}:${spec.sheetScale}:'
          '${[for (final layer in spec.orderedLayers) layer.jsonValue].join('+')}'
          ':${face.fontFamily}',
      caption: 'CUT${task.owner.name}',
      render: () => _renderEnvelope(
        task,
        face: face,
        layers: spec.layers,
        outputSize: fitted == null
            ? null
            : (width: fitted.width, height: fitted.height),
      ),
    );
  }

  void _requestCompositePreview({
    required ExportFrameTask task,
    required ExportSizeMode sizeMode,
    required bool applyLayerFx,
    required ExportFormatSelection format,
    required String caption,
  }) {
    final renderer = _previewRendererFor(
      applyLayerFx: applyLayerFx,
      format: format,
    );
    final bgKey = format.wantsAlpha ? -1 : format.backgroundArgb;
    // The video run burns the SE name tags in (renderCompositeForVideo);
    // stills stay clean because they are compositing sources. The preview
    // has to answer the same question, or it shows a frame the export
    // will not produce.
    final withNameTags = format.kind == ExportMediaKind.video;
    final source = sizeMode == ExportSizeMode.camera
        ? _session.camera.cameraFrameSize
        : task.cut.canvasSize;
    final outputSize = _previewFit(source.width, source.height);
    _preview.request(
      key:
          'frame:${task.cut.id.value}:${task.frameIndex}:'
          '${sizeMode.jsonValue}:$applyLayerFx:$bgKey:$withNameTags:'
          '${outputSize?.width ?? source.width}x'
          '${outputSize?.height ?? source.height}',
      caption: caption,
      render: () => task.isGap
          ? Future<ui.Image?>.value()
          : renderer.renderComposite(
              task,
              sizeMode,
              outputSize: outputSize,
              withNameTags: withNameTags,
            ),
    );
  }

  String? _transportLine() {
    switch (_tab) {
      case ExportTab.sequence:
        final axis = _sequenceAxisPlan();
        if (axis.isEmpty) {
          return null;
        }
        final inOut = _sequenceInOut();
        final position = _sequencePosition.clamp(0, axis.length - 1);
        final cutName = axis[position].cut.name;
        if (inOut == null) {
          return AppText.strings.exInvalidInOut(
            frame: position + 1,
            cut: cutName,
          );
        }
        final kept = KeptSpan(
          length: axis.length,
          inFrame: inOut.$1,
          outFrame: inOut.$2,
        );
        return AppText.strings.exInOut(
          inFrame: kept.first + 1,
          outFrame: kept.last + 1,
          count: kept.count,
          frame: position + 1,
          cut: cutName,
        );
      case ExportTab.image:
        return 'F${_currentImageFrame() + 1} / '
            '${math.max(1, _activeCut.duration)} · ${_activeCut.name}';
      case ExportTab.cels:
        final (plan: _, cut: _, :rows, :standing) = _celsList();
        final row = standing.rowIn(rows);
        final sheet = standing.sheetIn(rows);
        if (row == null || sheet == null) {
          return null;
        }
        final pages = exportCelsPages(row);
        // The file exactly as the naming rule will write it, extension
        // included (유저 2026-09-09: 「이름 규칙같은거에서 적용된걸 그대로 …
        // A0001.png 이런식으로 확장자까지」) — and a drawing that is no file
        // by its whole name.
        final file = sheet.look.fileName;
        final name = file.isNotEmpty ? file : sheet.fullName;
        return '$name · ${pages.indexOf(sheet) + 1} / ${pages.length}';
      case ExportTab.timesheet:
        final plan = _timesheetPagePlan();
        if (plan.isEmpty) {
          return null;
        }
        final task = plan[_sheetPosition.clamp(0, plan.length - 1)];
        return 'CUT${task.cutLabel} · p${task.pageIndex + 1}/'
            '${task.pageCount} · '
            '${AppText.strings.exPageCount(plan.length)}';
      case ExportTab.conte:
        final (_, pages) = _conteSheet();
        if (pages.isEmpty) {
          return null;
        }
        final position = _contePosition.clamp(0, pages.length - 1);
        return 'p${position + 1} / ${pages.length} · '
            '${AppText.strings.exPageCount(pages.length)}';
      case ExportTab.envelope:
        final plan = _envelopePlan();
        if (plan.isEmpty) {
          return null;
        }
        final position = _envelopePosition.clamp(0, plan.length - 1);
        final files = _envelopeFilePlan().length;
        return 'CUT${plan[position].owner.name} · ${position + 1} / '
            '${plan.length} · ${AppText.strings.exFileCount(files)}';
    }
  }

  // --- summaries ------------------------------------------------------------

  /// The sentence under the preview: what THIS tab would write, in the
  /// terms that tab thinks in. One case per tab, each its own method —
  /// every one of them ends in a sentence, and a switch that also builds
  /// them reads as one function doing six jobs.
  String _planHeadline() => switch (_tab) {
    ExportTab.sequence => _sequenceHeadline(),
    ExportTab.image => _imageHeadline(),
    ExportTab.cels => _celsHeadline(),
    ExportTab.timesheet => _timesheetHeadline(),
    ExportTab.conte => _conteHeadline(),
    ExportTab.envelope => _envelopeHeadline(),
  };

  String _sequenceHeadline() {
    final spec = _specs.sequence;
    final plan = _sequencePlanForRun(video: spec.format.isVideo);
    final strings = AppText.strings;
    if (plan == null) {
      return strings.exInvalidRange(math.max(1, _activeCut.duration));
    }
    final frames = strings.exFrameCount(plan.length);
    if (spec.sizeMode == ExportSizeMode.camera) {
      final size = _session.camera.cameraFrameSize;
      return strings.exSequenceCamera(frames, size.width, size.height);
    }
    final sizes = _scopeCanvasSizes(spec.scope);
    if (sizes.length == 1) {
      final size = sizes.first;
      return strings.exSequenceCanvas(frames, size.width, size.height);
    }
    return strings.exSequencePerCut(frames);
  }

  String _imageHeadline() {
    final size = _specs.image.sizeMode == ExportSizeMode.camera
        ? _session.camera.cameraFrameSize
        : _activeCut.canvasSize;
    return AppText.strings.exImageHeadline(
      frame: _currentImageFrame() + 1,
      cut: _activeCut.name,
      width: size.width,
      height: size.height,
    );
  }

  String _celsHeadline() {
    final plan = _celGroupPlan();
    final labels = {for (final task in plan.cels) task.bundleAxis.id}.length;
    final strings = AppText.strings;
    return strings.exCelsHeadline(
      labels: strings.exLabelCount(labels),
      files: strings.exFileCount(plan.length),
      background: _specs.cels.format.wantsAlpha
          ? strings.exTransparent
          : strings.exOpaque,
      format: _specs.cels.format.stillFormat.label,
    );
  }

  String _timesheetHeadline() {
    if (_specs.timesheet.format == ExportTimesheetFormat.sheetImage) {
      return AppText.strings.exSheetImageHeadline(
        pages: AppText.strings.exSheetPageCount(_timesheetPagePlan().length),
        // The paper the panel stands on, read off the table — ↩️it said
        // 「B4」 by hand, and went on saying it after the paper became
        // another (F-294).
        paper: SheetPaper.timesheet.format.label,
      );
    }
    return AppText.strings.exXdtsHeadline(
      AppText.strings.exXdtsSheetCount(_timesheetCuts().length),
    );
  }

  String _conteHeadline() {
    final (_, pages) = _conteSheet();
    final counted = AppText.strings.exContePageCount(pages.length);
    if (_specs.conte.format == ExportConteFormat.pdf) {
      return AppText.strings.exContePdfHeadline(counted);
    }
    return AppText.strings.exContePngHeadline(counted);
  }

  String _envelopeHeadline() {
    final spec = _specs.envelope;
    final sheets = _envelopePlan().length;
    final files = _envelopeFilePlan().length;
    final strings = AppText.strings;
    return strings.exEnvelopeHeadline(
      sheets: strings.exEnvelopeCount(sheets),
      files: strings.exPngCount(files),
      paper: spec.paperMode == CutEnvelopePaperMode.cut
          ? strings.exEnvelopePaperCut
          : strings.exEnvelopePaperSheet(
              envelopeSheetPaperSize(spec.sheetScale).width,
            ),
      layered: spec.separateLayerFiles
          ? strings.exEnvelopeLayered(spec.orderedLayers.length)
          : '',
    );
  }

  String _outputLine() {
    if (!_hasDestination) {
      return AppText.strings.exChooseLocation;
    }
    final (:name, :more) = _firstOutputFile();
    if (name == null) {
      return '→ ${_nothingToWriteText()}';
    }
    return '→ $name${more ? ' …' : ''}';
  }

  /// THE FIRST FILE THIS TAB WRITES, and whether more follow.
  ///
  /// 🚨ONE ANSWER FOR TWO SURFACES (감사 2026-09-09). The output line under
  /// the file bar and the naming accordion's summary both say 「what comes
  /// out」, and each used to work it out for itself — the same walk over the
  /// same plan, written twice. They had already drifted apart in three
  /// places, and one of them was a LIE: the summary printed a hardcoded
  /// `CUT1.xdts` for every project, whatever the cut was called. (The other
  /// two: the summary showed nothing at all on the Image tab, and showed
  /// the numbered still name while the Sequence tab was set to video.)
  ///
  /// ⛔The SHAPING stays with each caller — the arrow, the ellipsis, the
  /// empty word. Only the question 「which file」 is answered here.
  ({String? name, bool more}) _firstOutputFile() {
    switch (_tab) {
      case ExportTab.sequence:
        final spec = _specs.sequence;
        if (spec.format.isVideo) {
          return (
            name: _singleFileName(
              _sequenceFileController,
              spec.format.container.fileExtension,
            ),
            more: false,
          );
        }
        return (name: _sequenceFileNameFor(0), more: true);
      case ExportTab.image:
        return (
          name: _singleFileName(
            _imageFileController,
            _specs.image.format.stillFormat.fileExtension,
          ),
          more: false,
        );
      case ExportTab.cels:
        final plan = _celGroupPlan();
        final written = plan.writtenCels;
        return (
          name: written.isEmpty ? null : written.first.fileName,
          more: written.length > 1,
        );
      case ExportTab.timesheet:
        return _firstTimesheetFile();
      case ExportTab.conte:
        final (_, pages) = _conteSheet();
        if (pages.isEmpty) {
          return (name: null, more: false);
        }
        if (_specs.conte.format == ExportConteFormat.pdf) {
          return (name: 'conte.pdf', more: false);
        }
        return (
          name: _contePageFileName(0, pages.length),
          more: pages.length > 1,
        );
      case ExportTab.envelope:
        final files = _envelopeFilePlan();
        return files.isEmpty
            ? (name: null, more: false)
            : (
                name: _envelopeFileName(files.first.$1, files.first.$2),
                more: files.length > 1,
              );
    }
  }

  ({String? name, bool more}) _firstTimesheetFile() {
    if (_specs.timesheet.format == ExportTimesheetFormat.sheetImage) {
      final plan = _timesheetPagePlan();
      return plan.isEmpty
          ? (name: null, more: false)
          : (name: plan.first.fileName, more: plan.length > 1);
    }
    final cuts = _timesheetCuts();
    return cuts.isEmpty
        ? (name: null, more: false)
        : (
            name: 'CUT${sanitizeExportFileComponent(cuts.first.name)}.xdts',
            more: cuts.length > 1,
          );
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
  ];

  /// The single-file name with the CURRENT format's extension — a stale
  /// lineup extension in the field swaps instead of stacking
  /// (`name.mp4` + MOV → `name.mov`, never `name.mp4.mov`).
  String _singleFileName(TextEditingController controller, String extension) {
    var name = controller.text.trim();
    if (name.isEmpty) {
      name = sanitizeExportFileComponent(
        _session.repository.requireProject().name,
      );
    }
    final lower = name.toLowerCase();
    for (final known in _knownExtensions) {
      if (lower.endsWith(known)) {
        name = name.substring(0, name.length - known.length);
        break;
      }
    }
    return '$name.$extension';
  }

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

  bool get _hasDestination => switch (_destination) {
    ExportIntoFolder(:final folder) => folder.path.isNotEmpty,
    ExportHandOver() => true,
    null => false,
  };

  bool get _canExport {
    if (_isExporting || !_hasDestination) {
      return false;
    }
    switch (_tab) {
      case ExportTab.sequence:
        final plan = _sequencePlanForRun(video: _specs.sequence.format.isVideo);
        return plan != null && plan.isNotEmpty;
      case ExportTab.image:
        return true;
      case ExportTab.cels:
        return _celGroupPlan().length > 0;
      case ExportTab.timesheet:
        return _specs.timesheet.format == ExportTimesheetFormat.sheetImage
            ? _timesheetPagePlan().isNotEmpty
            : _timesheetCuts().isNotEmpty;
      case ExportTab.conte:
        return _conteSheet().$2.isNotEmpty;
      case ExportTab.envelope:
        return _envelopeFilePlan().isNotEmpty;
    }
  }

  // --- export runners -------------------------------------------------------

  String _joinLocation(String name) =>
      '$_outputDirectory${Platform.pathSeparator}$name';

  void _reportProgress(int completed, int total) {
    if (mounted) {
      setState(() {
        _progress = (completed, total);
        _statusMessage = AppText.strings.exExportingProgress(completed, total);
      });
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
      _statusMessage = AppText.strings.exExporting;
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
        setState(() {
          _isExporting = false;
          _progress = null;
        });
      }
    }
  }

  /// [run] where the destination sends it: into [_location] — or, handing
  /// over, into an outbox of its own, answered with the run's sentence so
  /// the caller hands the outbox over when its time comes (at once for
  /// Export, after the last job for the queue). A run that was stopped or
  /// failed leaves nothing to hand over.
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
  /// again. What another app was only offered (Android's share sheet)
  /// stays for it to read, and goes with the run.
  Future<String?> _handOverOutboxes(List<String> outboxes) async {
    var handed = HandOver.declined;
    try {
      final outputs = [
        for (final outbox in outboxes)
          for (final entry in Directory(outbox).listSync()) entry.path,
      ];
      if (outputs.isEmpty || !mounted) {
        return null;
      }
      handed = await handOverFilesForUser(context, paths: outputs);
      return handed == HandOver.declined
          ? AppText.strings.exHandOverDeclined
          : null;
    } on Object catch (error) {
      return AppText.strings.exFailed(error);
    } finally {
      if (handed != HandOver.offered) {
        _discardOutboxes(outboxes);
      }
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
      case ExportTab.timesheet:
        return _specs.timesheet.format == ExportTimesheetFormat.sheetImage
            ? _exportSheetImages()
            : _exportXdts();
      case ExportTab.conte:
        return _exportConte();
      case ExportTab.envelope:
        return _exportEnvelopes();
    }
  }

  /// Public for tests; the Export button is the production entry point.
  Future<void> export() async {
    if (!_canExport) {
      return;
    }
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
    _ => null,
  };

  String? _singleFileNameForCurrentTab() {
    if (_tab == ExportTab.image) {
      return _singleFileName(
        _imageFileController,
        _specs.image.format.stillFormat.fileExtension,
      );
    }
    if (_tab == ExportTab.sequence && _specs.sequence.format.isVideo) {
      return _singleFileName(
        _sequenceFileController,
        _specs.sequence.format.container.fileExtension,
      );
    }
    return null;
  }

  /// Add to Queue: the current tab's spec + destination, frozen as a job.
  /// The picture renders at RUN time — the spec is the restorable part.
  void addToQueue() {
    if (!_canExport) {
      return;
    }
    _queue.enqueue(
      spec: _specs.specFor(_tab),
      destination: _destination!,
      fileName: _singleFileNameForCurrentTab(),
    );
    setState(() {});
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
        controller.text = fileName;
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
    _preview.clear();
    _refreshPreview();
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
      _statusMessage = AppText.strings.exRenderingQueue;
    });
    var succeeded = 0;
    var failed = 0;
    // Every job that hands over leaves its outbox here, and they go to the
    // user in ONE window once the last job is done — a queue of five does
    // not ask five times where its outputs go.
    final outboxes = <String>[];
    String? handOverSaid;
    try {
      while (!_cancelRequested) {
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
        setState(() {
          _isExporting = false;
          _progress = null;
          _tab = snapshotTab;
          _specs = snapshotSpecs;
          _destination = snapshotDestination;
          _syncControllersFromSpecs();
          _statusMessage =
              handOverSaid ?? _queueRestSentence(succeeded, failed);
        });
        _persist();
        _preview.clear();
        _refreshPreview();
      }
    }
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
    _refreshPreview();
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
  /// A null render or a null [encode] answer skips that file (the service's
  /// rule); the finished sentence counts the skips, and says so only when
  /// there were any.
  Future<String> _runImageExport({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String Function(int index) fileNameFor,
    required _Tally says,
    Future<List<int>?> Function(ui.Image image)? encode,
  }) async {
    final summary = await _exportService.exportImages(
      count: count,
      renderImage: renderImage,
      fileNameFor: fileNameFor,
      directoryPath: _outputDirectory,
      encode: encode,
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    final strings = AppText.strings;
    if (summary.processed < count) {
      return _exportCancelled(says.kept(strings, summary.written));
    }
    return _exportDone(
      says.done(strings, summary.written),
      skipped: summary.processed - summary.written,
    );
  }

  Future<String> _exportSheetImages() {
    final plan = _timesheetPagePlan();
    final scale = _specs.timesheet.sheetScale.toDouble();
    final face = _documentFace;
    return _runImageExport(
      count: plan.length,
      renderImage: (index) =>
          _renderSheetPage(plan[index], face: face, scale: scale),
      fileNameFor: (index) => plan[index].fileName,
      says: _Tally.sheetPages,
    );
  }

  /// The envelopes, one PNG per (sheet, layer) — streamed like every image
  /// export, so only the sheet being written holds its ink rasters.
  Future<String> _exportEnvelopes() {
    final files = _envelopeFilePlan();
    final face = _documentFace;
    return _runImageExport(
      count: files.length,
      renderImage: (index) {
        final (task, layer) = files[index];
        return _renderEnvelope(
          task,
          face: face,
          // One stratum per file when they ship separately, so only the
          // paper file is opaque and the rest stack over it.
          layers: layer == null ? _specs.envelope.layers : {layer},
        );
      },
      fileNameFor: (index) =>
          _envelopeFileName(files[index].$1, files[index].$2),
      says: _Tally.envelopeFiles,
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
          scale: spec.sheetScale.toDouble(),
          words: words,
        ),
        fileNameFor: (index) => _contePageFileName(index, pages.length),
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
    final file = File(_joinLocation('conte.pdf'));
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
    final plan = _sequencePlanForRun(video: true)!;
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
    final plan = _sequencePlanForRun(video: false)!;
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    return _runImageExport(
      count: plan.length,
      renderImage: (index) =>
          renderer.renderComposite(plan[index], spec.sizeMode),
      fileNameFor: _sequenceFileNameFor,
      encode: _stillEncodeFor(spec.format),
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
    final fileName = _singleFileName(
      _imageFileController,
      spec.format.stillFormat.fileExtension,
    );
    final summary = await _exportService.exportImages(
      count: 1,
      renderImage: (_) => renderer.renderComposite(task, spec.sizeMode),
      fileNameFor: (_) => fileName,
      directoryPath: _outputDirectory,
      encode: _stillEncodeFor(spec.format),
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    return summary.written == 1
        ? AppText.strings.exDoneFile(fileName)
        : AppText.strings.exNothingInFrame;
  }

  Future<String> _exportCels() {
    final spec = _specs.cels;
    // 🚨THE TICKED CELS, not every planned one. ↩️The run walked the list
    // the window PREVIEWS (`cels`, unticked bundles included), so a bundle
    // whose dot was off was counted out of the headline and written all the
    // same (found reading the run for F-289, 2026-10-06).
    final entries = _celGroupPlan().writtenCels;
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
    return _runImageExport(
      count: entries.length,
      renderImage: (index) =>
          renderer.renderCelGroup(entries[index], spec.sizeMode),
      fileNameFor: (index) => entries[index].fileName,
      encode: _stillEncodeFor(spec.format),
      says: _Tally.cels,
    );
  }

  Future<String> _exportXdts() async {
    final cuts = _timesheetCuts();
    final defById = _session.camera.cameraInstructionSet.defById;
    var written = 0;
    for (final cut in cuts) {
      final content = buildXdtsContent(
        cut: cut,
        cutLabel: cut.name,
        instructionDefById: defById,
        // The print sheet's own SE sources (track lanes + this cut's true
        // origin on the track axis) — the two sheets must read one story.
        trackSeLayers: _session.activeTrack.seLayers,
        cutStartFrame: _trackStartOf(cut),
      );
      final file = File(
        _joinLocation('CUT${sanitizeExportFileComponent(cut.name)}.xdts'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      written += 1;
      _reportProgress(written, cuts.length);
    }
    return _exportDone(AppText.strings.exXdtsSheetCount(written));
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
    _refreshPreview();
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

  Future<void> _browseLocation() async {
    // PICK-2: the export location is PERSISTED as `lastLocation` and replayed
    // on the next launch, so it has to be a durable real path. `getDirectoryPath`
    // gave a SAF tree URI on Android and threw on iOS — either way the stored
    // value would come back a dead location one session later.
    if (widget.exportDirectoryPicker != null) {
      final directory = await widget.exportDirectoryPicker!();
      if (directory == null || !mounted) {
        return;
      }
      setState(
        () =>
            _destination = ExportIntoFolder(GrantedDirectory(path: directory)),
      );
      _persist();
      return;
    }
    // The GRANT flavour: `lastLocation` is replayed at the next launch,
    // and on macOS a stored path without its token is refused at the
    // first write there (Q-scoped-folder-settings, 유저 08-26).
    final grant = await pickFolderGrantForUser(context);
    final path = grant?.path;
    if (path == null || !mounted) {
      return;
    }
    setState(
      () => _destination = ExportIntoFolder(
        GrantedDirectory(path: path, bookmark: grant!.bookmark),
      ),
    );
    _persist();
  }

  /// 「끝나면 고르기」: the destination is chosen once the run is done.
  void _chooseHandOver() {
    setState(() => _destination = const ExportHandOver());
    _persist();
  }

  bool get _singleFileTab =>
      _tab == ExportTab.image ||
      (_tab == ExportTab.sequence && _specs.sequence.format.isVideo);

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
          footerNote: _statusNote(theme),
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
          // Tabs share the one preview slot; a stale picture from
          // another domain must not linger under the new axis.
          _preview.clear();
          _refreshPreview();
        },
      ),
  ];

  /// The window's four columns: presets · preview · settings · queue.
  Widget _zones(
    ThemeData theme, {
    required bool presetsOpen,
    required bool queueOpen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nameBar(theme),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _drawerWidth(presetsOpen, _presetsDrawerWidth),
                child: _presetsZone(open: presetsOpen),
              ),
              VerticalDivider(width: 1, color: theme.dividerColor),
              Expanded(child: _previewZone(theme)),
              VerticalDivider(width: 1, color: theme.dividerColor),
              SizedBox(
                width: _settingsColumnWidth,
                child: _settingsZone(),
              ),
              VerticalDivider(width: 1, color: theme.dividerColor),
              SizedBox(
                width: _drawerWidth(queueOpen, _queueDrawerWidth),
                child: _queueZone(open: queueOpen),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusNote(ThemeData theme) => Text(
    _statusMessage ?? '',
    key: const ValueKey<String>('export-status'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  List<AppWindowAction> _windowActions(BuildContext context) => [
    if (_isExporting)
      AppWindowAction(
        label: AppText.strings.commonCancel,
        actionKey: const ValueKey<String>('export-cancel-button'),
        onPressed: cancelExport,
      ),
    AppWindowAction(
      label: AppText.strings.exAddToQueue,
      actionKey: const ValueKey<String>('export-queue-add-button'),
      onPressed: _canExport ? addToQueue : null,
    ),
    AppWindowAction(
      label: AppText.strings.exExport,
      actionKey: const ValueKey<String>('export-run-button'),
      emphasis: AppWindowActionEmphasis.primary,
      onPressed: _canExport ? () => unawaited(export()) : null,
    ),
  ];

  Widget _nameBar(ThemeData theme) {
    final singleFile = _singleFileTab;
    final controller = _tab == ExportTab.image
        ? _imageFileController
        : _sequenceFileController;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Text(
            singleFile
                ? AppText.strings.exFileLabel
                : AppText.strings.exPatternLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          // The name and the destination share what the buttons leave: the
          // name takes its width while the destination keeps half the room,
          // and gives way evenly below that — in a narrow window a name
          // field of fixed width and the two destination buttons outgrow
          // the bar.
          Expanded(
            child: LayoutBuilder(
              builder: (context, room) => Row(
                children: [
                  if (singleFile)
                    SizedBox(
                      width: math.min(180, room.maxWidth / 2),
                      child: TextField(
                        key: const ValueKey<String>('export-file-name-field'),
                        controller: controller,
                        enabled: !_isExporting,
                        style: theme.textTheme.bodySmall,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 5,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: room.maxWidth / 2,
                      ),
                      child: Text(
                        _patternPreview(),
                        key: const ValueKey<String>('export-pattern-preview'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Text(
                    AppText.strings.exLocationLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (_destination) {
                        ExportIntoFolder(:final folder) => folder.path,
                        ExportHandOver() => AppText.strings.exHandOverWhenDone,
                        null => AppText.strings.exChooseFolder,
                      },
                      key: const ValueKey<String>('export-location-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _hasDestination
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _destinationButton(
            key: 'export-browse-button',
            label: AppText.strings.exBrowse,
            onPressed: _browseLocation,
          ),
          const SizedBox(width: 6),
          _destinationButton(
            key: 'export-hand-over-button',
            label: AppText.strings.exHandOverWhenDone,
            onPressed: _chooseHandOver,
          ),
        ],
      ),
    );
  }

  /// A button that picks where the outputs go — dead while a run is under
  /// way, whose destination is already decided.
  Widget _destinationButton({
    required String key,
    required String label,
    required VoidCallback onPressed,
  }) {
    final pressed = _isExporting ? null : onPressed;
    return ControlPressClaim(
      onPressed: pressed,
      child: OutlinedButton(
        key: ValueKey<String>(key),
        onPressed: silentPress(pressed),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(label),
      ),
    );
  }

  /// The name alone — the naming summary and the file-bar preview show what
  /// the first file is called, without the output line's arrow.
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

  ExportNavBar? _navBar() {
    switch (_tab) {
      case ExportTab.sequence:
        final axis = _sequenceAxis(_sequenceAxisPlan());
        final inOut = _sequenceInOut();
        return ExportNavBar(
          axis: axis,
          position: _sequencePosition,
          enabled: !_isExporting,
          inController: _inController,
          outController: _outController,
          onInOutEdited: _writeInOutToSpec,
          inMark: inOut?.$1,
          outMark: inOut?.$2,
          onChanged: (position) {
            setState(() => _sequencePosition = position);
            _refreshPreview();
          },
        );
      case ExportTab.image:
        return ExportNavBar(
          axis: _imageAxis(),
          position: _currentImageFrame(),
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _imageFrame = position);
            _refreshPreview();
          },
        );
      case ExportTab.cels:
        // The list's band turns through the drawings ([ExportCelsBand]).
        return null;
      case ExportTab.timesheet:
        return ExportNavBar(
          axis: _timesheetAxis(_timesheetPagePlan()),
          position: _sheetPosition,
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _sheetPosition = position);
            _refreshPreview();
          },
        );
      case ExportTab.conte:
        final (_, pages) = _conteSheet();
        return ExportNavBar(
          axis: ExportNavAxis(
            length: pages.length,
            captionOf: (position) =>
                'p${position.clamp(0, math.max(0, pages.length - 1)) + 1}',
          ),
          position: _contePosition,
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _contePosition = position);
            _refreshPreview();
          },
        );
      case ExportTab.envelope:
        final plan = _envelopePlan();
        return ExportNavBar(
          axis: ExportNavAxis(
            length: plan.length,
            captionOf: (position) => plan.isEmpty
                ? '-'
                : 'CUT${plan[position.clamp(0, plan.length - 1)].owner.name}',
          ),
          position: _envelopePosition,
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _envelopePosition = position);
            _refreshPreview();
          },
        );
    }
  }

  Widget _previewZone(ThemeData theme) {
    final progress = _progress;
    final navBar = _navBar();
    final transport = _transportLine();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _previewWell(theme)),
          if (navBar != null) ...[const SizedBox(height: 6), navBar],
          if (transport != null) ...[
            const SizedBox(height: 3),
            Text(
              transport,
              key: const ValueKey<String>('export-transport-line'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _outputLine(),
            key: const ValueKey<String>('export-output-line'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // The Cels tab's list stands under its preview (유저 2026-10-06:
          // 「가로/아래가 좋고」).
          if (_tab == ExportTab.cels) ...[
            const SizedBox(height: 6),
            _celsBoard(),
          ],
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress.$2 > 0 ? progress.$1 / progress.$2 : null,
              minHeight: 4,
            ),
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
      ExportTab.timesheet => _timesheetModules(),
      ExportTab.conte => _conteModules(),
      ExportTab.envelope => _envelopeModules(),
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
  ExportAccordion _formatAccordion({
    required ExportFormatSelection format,
    required ExportFormatCapabilities capabilities,
    required void Function(ExportFormatSelection format) onChanged,
    ({bool enabled, VoidCallback onTap})? reset,
  }) => ExportAccordion(
    title: AppText.strings.exFormat,
    summary: ExportFormatModule.summarize(format),
    expansion: _expansion('format', open: true),
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
      if (spec.format.isStill)
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
      _fxAccordion(
        keyValue: 'export-apply-fx-toggle',
        label: AppText.strings.exApplyLayerFxHelp,
        applyLayerFx: spec.applyLayerFx,
        onChanged: (value) => _updateSpec(spec.copyWith(applyLayerFx: value)),
      ),
    ];
  }

  void _writeInOutToSpec() {
    final spec = _specs.sequence;
    final inOut = _sequenceInOut();
    setState(() {
      if (inOut != null) {
        _specs = _specs.withSpec(
          spec.copyWith(inFrame: inOut.$1, outFrame: inOut.$2),
        );
      }
    });
    if (inOut != null) {
      _persist();
    }
    _refreshPreview();
  }

  List<Widget> _imageModules() {
    final spec = _specs.image;
    return [
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
    _refreshPreview();
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
          : overrides.withCelsDelta(cutId, delta.withoutLayerOverrides());
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
        _refreshPreview();
      },
      onAllIncluded: () {
        _session.repository.updateExportOverrides(
          (overrides) => overrides.withAllCutsIncluded(),
        );
        setState(() {});
        _refreshPreview();
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
        _refreshPreview();
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
          // the spec alone ([_updateSpec]).
          PillStrip(
            items: [
              for (final kind in ExportCelKind.values)
                _specSwitch(
                  'export-cels-kind-${kind.jsonValue}',
                  exportCelKindLabel(kind),
                  spec.kinds.contains(kind),
                  () => spec.withKind(kind, !spec.kinds.contains(kind)),
                ),
            ],
          ),
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
        _overrides.deltaFor(_celsList().cut.id)?.layerOverrides.isNotEmpty ??
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
      _formatAccordion(
        format: spec.format,
        capabilities: _stillOnlyCapabilities,
        onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
      ),
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

  List<Widget> _timesheetModules() {
    final spec = _specs.timesheet;
    return [
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: spec.format == ExportTimesheetFormat.sheetImage
            ? '${AppText.strings.exSheetPng} · ${spec.sheetScale}x'
            : 'XDTS',
        expansion: _expansion('format', open: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillStrip(
              items: [
                _pill(
                  keyValue: 'export-tsformat-sheet',
                  label: AppText.strings.exSheetPng,
                  selected: spec.format == ExportTimesheetFormat.sheetImage,
                  onPick: () => _updateSpec(
                    spec.copyWith(format: ExportTimesheetFormat.sheetImage),
                  ),
                ),
                _pill(
                  keyValue: 'export-tsformat-xdts',
                  label: 'XDTS',
                  selected: spec.format == ExportTimesheetFormat.xdts,
                  onPick: () => _updateSpec(
                    spec.copyWith(format: ExportTimesheetFormat.xdts),
                  ),
                ),
              ],
            ),
            ..._sheetScaleRow(
              shown: spec.format == ExportTimesheetFormat.sheetImage,
              keyPrefix: 'export-tsscale',
              scale: spec.sheetScale,
              onPick: (step) => _updateSpec(spec.copyWith(sheetScale: step)),
            ),
          ],
        ),
      ),
      _scopeAccordion(
        scope: spec.scope,
        onChanged: (scope) => _updateSpec(spec.copyWith(scope: scope)),
        fold: (key: 'scope', open: true),
        // The same grid part the Cels scope uses (v10: 공용 부품).
        child: spec.scope == ExportScopeKind.project ? _scopeCutGrid() : null,
      ),
    ];
  }

  List<Widget> _conteModules() {
    final spec = _specs.conte;
    return [
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: spec.format == ExportConteFormat.pdf
            ? AppText.strings.exVectorPdf
            : '${AppText.strings.exPagePng} · ${spec.sheetScale}x',
        expansion: _expansion('format', open: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillStrip(
              items: [
                _pill(
                  keyValue: 'export-conteformat-pdf',
                  label: 'PDF',
                  selected: spec.format == ExportConteFormat.pdf,
                  onPick: () =>
                      _updateSpec(spec.copyWith(format: ExportConteFormat.pdf)),
                ),
                _pill(
                  keyValue: 'export-conteformat-png',
                  label: AppText.strings.exSheetPng,
                  selected: spec.format == ExportConteFormat.pageImage,
                  onPick: () => _updateSpec(
                    spec.copyWith(format: ExportConteFormat.pageImage),
                  ),
                ),
              ],
            ),
            ..._sheetScaleRow(
              shown: spec.format == ExportConteFormat.pageImage,
              keyPrefix: 'export-contescale',
              scale: spec.sheetScale,
              onPick: (step) => _updateSpec(spec.copyWith(sheetScale: step)),
            ),
          ],
        ),
      ),
    ];
  }

  /// The scale row a sheet-image export offers, or nothing while the
  /// picked format does not rasterize.
  ///
  /// ⛔ONE SCALE ROW. The timesheet and the conte each wrote it out — the
  /// same four scales, the same label, the same reserved gap — so a fifth
  /// scale, or a changed step, reached one export and not the other. The
  /// envelope's real sheet takes it too (F-294; ↩️it had a row of widths in
  /// pixels): the steps are [SheetImageScale]'s, whole papers.
  List<Widget> _sheetScaleRow({
    required bool shown,
    required String keyPrefix,
    required int scale,
    required void Function(int scale) onPick,
  }) => [
    if (shown) ...[
      const SizedBox(height: 6),
      ExportModuleRow(
        label: AppText.strings.brScale,
        child: Align(
          alignment: Alignment.centerLeft,
          child: PillStrip(
            items: [
              for (final step in SheetImageScale.steps)
                _pill(
                  keyValue: '$keyPrefix-$step',
                  label: '${step}x',
                  selected: scale == step,
                  onPick: () => onPick(step),
                ),
            ],
          ),
        ),
      ),
    ],
  ];

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
              _preview.clear();
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

  List<Widget> _envelopeModules() {
    final spec = _specs.envelope;
    final cutPaper = spec.paperMode == CutEnvelopePaperMode.cut;
    return [
      ExportAccordion(
        title: AppText.strings.exPaperLabel,
        summary: cutPaper
            ? AppText.strings.exCutSize
            : AppText.strings.exSheetWidth(
                envelopeSheetPaperSize(spec.sheetScale).width,
              ),
        expansion: _expansion('envelope-paper', open: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillStrip(
              items: [
                _pill(
                  keyValue: 'export-envelope-paper-cut',
                  label: AppText.strings.exCutSize,
                  selected: cutPaper,
                  onPick: () => _updateSpec(
                    spec.copyWith(paperMode: CutEnvelopePaperMode.cut),
                  ),
                ),
                _pill(
                  keyValue: 'export-envelope-paper-sheet',
                  label: AppText.strings.exRealSheet,
                  selected: !cutPaper,
                  onPick: () => _updateSpec(
                    spec.copyWith(paperMode: CutEnvelopePaperMode.sheet),
                  ),
                ),
              ],
            ),
            // The real envelope is its paper, at the sheets' one scale.
            ..._sheetScaleRow(
              shown: !cutPaper,
              keyPrefix: 'export-envelopescale',
              scale: spec.sheetScale,
              onPick: (step) => _updateSpec(spec.copyWith(sheetScale: step)),
            ),
          ],
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exSheetLayers,
        summary: spec.separateLayerFiles
            ? AppText.strings.exSeparatePngs(spec.orderedLayers.length)
            : AppText.strings.exFlatLayers(spec.orderedLayers.length),
        expansion: _expansion('envelope-layers', open: true),
        reset: (
          enabled:
              spec.layers.length != EnvelopeExportSpec.defaultLayers.length,
          onTap: () => _updateSpec(
            spec.copyWith(layers: EnvelopeExportSpec.defaultLayers),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillStrip(
              items: [
                // The strata an envelope HAS — it shows no film pictures.
                for (final layer in EnvelopeExportSpec.strata)
                  _pill(
                    keyValue: 'export-envelope-layer-${layer.jsonValue}',
                    label: switch (layer) {
                      SheetPaintLayer.paper => AppText.strings.exPaperLabel,
                      SheetPaintLayer.form => AppText.strings.exForm,
                      SheetPaintLayer.content => AppText.strings.exContent,
                      SheetPaintLayer.picture => AppText.strings.exPictureLayer,
                      SheetPaintLayer.ink => AppText.strings.exInk,
                    },
                    selected: spec.layers.contains(layer),
                    onPick: () => _updateSpec(
                      spec.withLayer(layer, !spec.layers.contains(layer)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ExportModuleRow(
              label: AppText.strings.exFiles,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PillStrip(
                  items: [
                    _pill(
                      keyValue: 'export-envelope-files-flat',
                      label: AppText.strings.exOneImage,
                      selected: !spec.separateLayerFiles,
                      onPick: () =>
                          _updateSpec(spec.copyWith(separateLayerFiles: false)),
                    ),
                    _pill(
                      keyValue: 'export-envelope-files-layered',
                      label: AppText.strings.exOnePerLayer,
                      selected: spec.separateLayerFiles,
                      onPick: () =>
                          _updateSpec(spec.copyWith(separateLayerFiles: true)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _scopeAccordion(
        scope: spec.scope,
        onChanged: (scope) => _updateSpec(spec.copyWith(scope: scope)),
        // Open by default: "this cut or the whole film" is the first thing
        // anyone asks of a per-cut document.
        fold: (key: 'envelope-scope', open: true),
        // The cut checks this tab's project scope obeys, shown where they
        // are obeyed — the same grid part the Cels and Timesheet scopes
        // use. ↩️The tab obeyed them from its first day (2026-08-06) with
        // no grid of its own: a cut unticked in another tab simply went
        // missing here (envelope-export-cut-grid-Q1).
        child: spec.scope == ExportScopeKind.project ? _scopeCutGrid() : null,
      ),
    ];
  }

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
  sheetPages,
  contePages,
  envelopeFiles;

  String kept(AppStrings strings, int count) => switch (this) {
    _Tally.frames => strings.exFrameCount(count),
    _Tally.cels => strings.exCelCount(count),
    _Tally.sheetPages || _Tally.contePages => strings.exPageCount(count),
    _Tally.envelopeFiles => strings.exFileCount(count),
  };

  String done(AppStrings strings, int count) => switch (this) {
    _Tally.frames => strings.exFrameCount(count),
    _Tally.cels => strings.exCelCount(count),
    _Tally.sheetPages => strings.exSheetPageCount(count),
    _Tally.contePages => strings.exContePageCount(count),
    _Tally.envelopeFiles => strings.exEnvelopeFileCount(count),
  };
}
