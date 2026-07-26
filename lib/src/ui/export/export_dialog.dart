import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import '../../native/qa_image_encoder.dart';
import '../../services/audio/audio_mixer_reference.dart' show AudioMixSource;
import '../../services/export/xdts_builder.dart';
import '../../services/persistence/app_export_settings.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../editor_session_manager.dart';
import '../../models/attached_layer_resolve.dart'
    show attachedLayersOf, isAttachedLayer;
import '../../models/export_overrides.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'export_audio_mix.dart';
import 'export_cel_group_plan.dart';
import 'export_cels_rows.dart';
import 'export_cels_selection.dart';
import 'export_cut_grid.dart';
import 'export_format_availability.dart';
import 'export_frame_renderer.dart';
import 'export_instruction_render.dart';
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
import '../timesheet/timesheet_document_painter.dart'
    show TimesheetDocumentLayout;
import '../timesheet/timesheet_notation.dart';
import '../widgets/app_window.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../text/app_strings.dart';

/// Picks the output directory (the Browse… button); `null` on cancel.
typedef ExportDirectoryPicker = Future<String?> Function();

Future<String?> _pickExportDirectory() => getDirectoryPath();

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
  String? _location;
  bool _presetsOpen = true;
  bool _queueOpen = true;
  final Map<String, bool> _expanded = {};
  final ExportQueueModel _queue = ExportQueueModel();

  late final TextEditingController _sequenceFileController;
  late final TextEditingController _imageFileController;
  late final TextEditingController _inController = TextEditingController();
  late final TextEditingController _outController = TextEditingController();
  late final TextEditingController _namingBaseController;
  late final TextEditingController _celSuffixController;

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
  int _celPosition = 0;
  int _sheetPosition = 0;
  // Sheet documents are chunky to derive; the modal dialog memoizes per
  // cut IDENTITY (the film cannot change under an open dialog).
  final Map<CutId, (Cut, TimesheetDocument, TimesheetDocumentLayout)>
      _sheetDocs = {};
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
    _anchorCut = _session.exportAnchorCutOrNull;
    final restored = AppExport.settings.value;
    _specs = restored.lastSpecs;
    _location = restored.lastLocation;
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
    if (_session.exportAnchorIsFallback) {
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
      _location = loaded.lastLocation ?? _location;
      _presetsOpen = loaded.presetsDrawerOpen;
      _queueOpen = loaded.queueDrawerOpen;
      _syncControllersFromSpecs();
    });
  }

  @override
  void dispose() {
    _sequenceFileController.dispose();
    _imageFileController.dispose();
    _inController.dispose();
    _outController.dispose();
    _namingBaseController.dispose();
    _celSuffixController.dispose();
    _queue.dispose();
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
        background: bgKey == -1
            ? const ui.Color(0x00000000)
            : ui.Color(bgKey),
      ),
    );
  }

  // --- state plumbing -------------------------------------------------------

  void _persist() {
    final next = AppExport.settings.value.copyWith(
      lastSpecs: _specs,
      lastLocation: _location,
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
    _inController.text = _specs.sequence.inFrame == null
        ? ''
        : '${_specs.sequence.inFrame! + 1}';
    _outController.text = _specs.sequence.outFrame == null
        ? ''
        : '${_specs.sequence.outFrame! + 1}';
  }

  bool _expandedFor(String id, {bool fallback = false}) =>
      _expanded['${_tab.jsonValue}:$id'] ?? fallback;

  void _toggleExpanded(String id, {bool fallback = false}) {
    setState(() {
      _expanded['${_tab.jsonValue}:$id'] =
          !_expandedFor(id, fallback: fallback);
    });
  }

  // --- plans ----------------------------------------------------------------

  Cut get _activeCut => _anchorCut!;

  bool _cutInScope(Cut cut) => _session.repository
      .requireProject()
      .exportOverrides
      .cutIncluded(cut.id);

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
    final lo = (inFrame ?? 0).clamp(0, axis.length - 1);
    final hi = (outFrame ?? axis.length - 1).clamp(lo, axis.length - 1);
    return axis.sublist(lo, hi + 1);
  }

  ExportProjectOverrides get _overrides =>
      _session.repository.requireProject().exportOverrides;

  /// The Cels tab's label-group plan (v10: 파일 = 라벨×셀번호 1장,
  /// 기준+어태치 합성) — rules, then the per-cut manual delta, then the
  /// project-side cut checks.
  ExportCelGroupPlan _celGroupPlan() {
    final spec = _specs.cels;
    return buildExportCelGroupPlan(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      spec: spec,
      overrides: _overrides,
      fileExtension: spec.format.stillFormat.fileExtension,
    );
  }

  List<Cut> _timesheetCuts() {
    final cuts = resolveExportCuts(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      range: _specs.timesheet.scope == ExportScopeKind.project
          ? ExportRange.allCuts
          : ExportRange.activeCut,
    );
    return [
      for (final cut in cuts)
        if (_cutInScope(cut)) cut,
    ];
  }

  TimesheetNotation get _sheetNotation =>
      TimesheetNotation.of(_session.languageSettings.value.notationLanguage);

  /// The cut's start on the TRACK axis (gaps included) — the SE column
  /// reads track-global spans, so the sheet needs the true origin.
  int _trackStartOf(Cut target) {
    var start = 0;
    for (final cut in resolveExportCuts(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      range: ExportRange.allCuts,
    )) {
      start += cut.leadingGapFrames;
      if (cut.id == target.id) {
        return start;
      }
      start += cut.duration;
    }
    return 0;
  }

  (Cut, TimesheetDocument, TimesheetDocumentLayout) _sheetDocFor(Cut cut) {
    final cached = _sheetDocs[cut.id];
    if (cached != null && identical(cached.$1, cut)) {
      return cached;
    }
    final document = TimesheetDocument.fromCut(
      cut: cut,
      projectName: _session.repository.requireProject().name,
      fps: _session.projectFps,
      info: _session.timesheetInfo,
      instructionDefById: _session.cameraInstructionSet.defById,
      trackSeLayers: _session.activeTrack.seLayers,
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
      final number = _cutNumberOf(cut);
      final (_, document, _) = _sheetDocFor(cut);
      final pageCount = document.pages.length;
      for (var page = 0; page < pageCount; page += 1) {
        tasks.add(
          ExportTimesheetPageTask(
            cut: cut,
            cutNumber: number,
            cutStartFrame: _trackStartOf(cut),
            pageIndex: page,
            pageCount: pageCount,
            fileName: pageCount == 1
                ? 'CUT$number.png'
                : 'CUT${number}_p${page + 1}.png',
          ),
        );
      }
    }
    return tasks;
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

  /// Test seam: sets the destination without the platform picker.
  @visibleForTesting
  void debugSetLocationForTests(String location) {
    setState(() => _location = location);
  }

  /// The 1-based position of [cut] within its track (sheet/XDTS number).
  int _cutNumberOf(Cut cut) {
    for (final track in _session.repository.requireProject().tracks) {
      final index = track.cuts.indexWhere((entry) => entry.id == cut.id);
      if (index != -1) {
        return index + 1;
      }
    }
    return 1;
  }

  String _sequenceFileNameFor(int index) {
    final naming = _specs.sequence.naming;
    final number = '${index + 1}'.padLeft(naming.digits, '0');
    final extension = _specs.sequence.format.stillFormat.fileExtension;
    return '${naming.baseName}_$number.$extension';
  }

  String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

  // --- preview (EX3) --------------------------------------------------------

  /// One flat position axis over the group plan: cels first, then the
  /// instruction events (the Instructions pseudo-label at the end).
  List<Object> _celEntries(ExportCelGroupPlan plan) => [
    ...plan.cels,
    ...plan.instructions,
  ];

  String _celEntryCaption(Object entry) => switch (entry) {
    ExportCelGroupTask(:final baseLayer, :final celName) =>
      '${baseLayer.name}-$celName',
    ExportInstructionTask(:final label) => label,
    _ => '',
  };

  ExportNavAxis _sequenceAxis(List<ExportFrameTask> plan) => ExportNavAxis(
    length: plan.length,
    ticks: [
      for (var i = 1; i < plan.length; i += 1)
        if (plan[i].cut.id != plan[i - 1].cut.id) i,
    ],
    captionOf: (position) => 'F${position + 1}',
  );

  ExportNavAxis _imageAxis() => ExportNavAxis(
    length: math.max(1, _activeCut.duration),
    captionOf: (position) => 'F${position + 1}',
  );

  ExportNavAxis _celsAxis(ExportCelGroupPlan plan) {
    final entries = _celEntries(plan);
    String groupOf(Object entry) => switch (entry) {
      ExportCelGroupTask(:final baseLayer) => 'cel:${baseLayer.id.value}',
      ExportInstructionTask(:final layer) => 'inst:${layer.id.value}',
      _ => '',
    };
    return ExportNavAxis(
      length: entries.length,
      ticks: [
        for (var i = 1; i < entries.length; i += 1)
          if (groupOf(entries[i]) != groupOf(entries[i - 1])) i,
      ],
      captionOf: (position) => _celEntryCaption(entries[position]),
    );
  }

  /// Re-aims the preview at whatever the tab currently points at. Called
  /// after every spec/nav/tab change; requests coalesce in the controller.
  void _refreshPreview() {
    switch (_tab) {
      case ExportTab.sequence:
        final spec = _specs.sequence;
        final axis = _sequenceAxisPlan();
        if (axis.isEmpty) {
          return;
        }
        _sequencePosition = _sequencePosition.clamp(0, axis.length - 1);
        final task = axis[_sequencePosition];
        _requestCompositePreview(
          task: task,
          sizeMode: spec.sizeMode,
          applyLayerFx: spec.applyLayerFx,
          format: spec.format,
          caption: 'F${_sequencePosition + 1}',
        );
      case ExportTab.image:
        final spec = _specs.image;
        _requestCompositePreview(
          task: ExportFrameTask(
            cut: _activeCut,
            frameIndex: _currentImageFrame(),
          ),
          sizeMode: spec.sizeMode,
          applyLayerFx: spec.applyLayerFx,
          format: spec.format,
          caption: 'F${_currentImageFrame() + 1}',
        );
      case ExportTab.cels:
        final spec = _specs.cels;
        final plan = _celGroupPlan();
        final entries = _celEntries(plan);
        if (entries.isEmpty) {
          _preview.clear();
          return;
        }
        _celPosition = _celPosition.clamp(0, entries.length - 1);
        final entry = entries[_celPosition];
        final format = spec.format;
        final renderer = _previewRendererFor(
          applyLayerFx: false,
          format: format,
        );
        final bgKey = format.wantsAlpha ? -1 : format.backgroundArgb;
        switch (entry) {
          case ExportCelGroupTask():
            _preview.request(
              key: 'celgroup:${entry.fileName}:${spec.sizeMode.jsonValue}:'
                  '$bgKey',
              caption: _celEntryCaption(entry),
              render: () => renderer.renderCelGroup(entry, spec.sizeMode),
            );
          case ExportInstructionTask():
            final size = spec.sizeMode == ExportSizeMode.camera
                ? _session.cameraFrameSize
                : entry.cut.canvasSize;
            _preview.request(
              key: 'celinst:${entry.fileName}:${size.width}x${size.height}:'
                  '$bgKey',
              caption: _celEntryCaption(entry),
              render: () => renderInstructionCelImage(
                task: entry,
                size: size,
                background: format.wantsAlpha
                    ? null
                    : ui.Color(format.backgroundArgb),
              ),
            );
        }
      case ExportTab.timesheet:
        final plan = _timesheetPagePlan();
        if (plan.isEmpty) {
          _preview.clear();
          return;
        }
        _sheetPosition = _sheetPosition.clamp(0, plan.length - 1);
        final task = plan[_sheetPosition];
        final (_, document, layout) = _sheetDocFor(task.cut);
        final page = layout.pageRect(task.pageIndex);
        final fitted = previewOutputSize(
          sourceWidth: page.width.round(),
          sourceHeight: page.height.round(),
          maxWidth: _previewMaxWidth,
          maxHeight: _previewMaxHeight,
        );
        _preview.request(
          key: 'sheet:${task.cut.id.value}:${task.pageIndex}',
          caption: 'p${task.pageIndex + 1}',
          render: () => renderTimesheetPageImage(
            document: document,
            layout: layout,
            pageIndex: task.pageIndex,
            notation: _sheetNotation,
            outputSize: fitted == null
                ? null
                : CanvasSize(width: fitted.width, height: fitted.height),
          ),
        );
    }
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
    final source = sizeMode == ExportSizeMode.camera
        ? _session.cameraFrameSize
        : task.cut.canvasSize;
    final fitted = previewOutputSize(
      sourceWidth: source.width,
      sourceHeight: source.height,
      maxWidth: _previewMaxWidth,
      maxHeight: _previewMaxHeight,
    );
    final outputSize = fitted == null
        ? null
        : CanvasSize(width: fitted.width, height: fitted.height);
    _preview.request(
      key: 'frame:${task.cut.id.value}:${task.frameIndex}:'
          '${sizeMode.jsonValue}:$applyLayerFx:$bgKey:'
          '${outputSize?.width ?? source.width}x'
          '${outputSize?.height ?? source.height}',
      caption: caption,
      render: () => task.isGap
          ? Future<ui.Image?>.value()
          : renderer.renderComposite(task, sizeMode, outputSize: outputSize),
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
          return 'Invalid in/out · F${position + 1} · $cutName';
        }
        final lo = (inOut.$1 ?? 0) + 1;
        final hi = (inOut.$2 ?? axis.length - 1) + 1;
        return 'in $lo – out $hi (${hi - lo + 1}f) · '
            'F${position + 1} · $cutName';
      case ExportTab.image:
        return 'F${_currentImageFrame() + 1} / '
            '${math.max(1, _activeCut.duration)} · ${_activeCut.name}';
      case ExportTab.cels:
        final entries = _celEntries(_celGroupPlan());
        if (entries.isEmpty) {
          return null;
        }
        final position = _celPosition.clamp(0, entries.length - 1);
        return '${_celEntryCaption(entries[position])} · '
            '${position + 1} / ${entries.length}';
      case ExportTab.timesheet:
        final plan = _timesheetPagePlan();
        if (plan.isEmpty) {
          return null;
        }
        final task = plan[_sheetPosition.clamp(0, plan.length - 1)];
        return 'CUT${task.cutNumber} · p${task.pageIndex + 1}/'
            '${task.pageCount} · ${plan.length} '
            '${_plural(plan.length, 'page')}';
    }
  }

  // --- summaries ------------------------------------------------------------

  String _planHeadline() {
    switch (_tab) {
      case ExportTab.sequence:
        final spec = _specs.sequence;
        final plan = _sequencePlanForRun(video: spec.format.isVideo);
        if (plan == null) {
          final duration = math.max(1, _activeCut.duration);
          return 'Enter a valid in/out range (1–$duration).';
        }
        final frames = '${plan.length} ${_plural(plan.length, 'frame')}';
        if (spec.sizeMode == ExportSizeMode.camera) {
          final size = _session.cameraFrameSize;
          return '$frames at ${size.width}×${size.height} through the camera.';
        }
        final sizes = _scopeCanvasSizes(spec.scope);
        if (sizes.length == 1) {
          final size = sizes.first;
          return '$frames at ${size.width}×${size.height} (raw canvas).';
        }
        return "$frames at each cut's own canvas size.";
      case ExportTab.image:
        final size = _specs.image.sizeMode == ExportSizeMode.camera
            ? _session.cameraFrameSize
            : _activeCut.canvasSize;
        return 'Frame ${_currentImageFrame() + 1} of ${_activeCut.name} at '
            '${size.width}×${size.height}.';
      case ExportTab.cels:
        final plan = _celGroupPlan();
        final labels = {
          for (final task in plan.cels) task.baseLayer.id,
        }.length;
        final background = _specs.cels.format.wantsAlpha
            ? 'transparent'
            : 'opaque';
        return '$labels ${_plural(labels, 'label')} · ${plan.length} '
            '${_plural(plan.length, 'file')} as $background '
            '${_specs.cels.format.stillFormat.label} '
            '(기준+어태치 composited per cel).';
      case ExportTab.timesheet:
        if (_specs.timesheet.format == ExportTimesheetFormat.sheetImage) {
          final pages = _timesheetPagePlan().length;
          return '$pages sheet ${_plural(pages, 'page')} as B4 PNG — the '
              "panel's own paper, offscreen.";
        }
        final count = _timesheetCuts().length;
        return '$count XDTS ${_plural(count, 'sheet')} '
            '(cels + serifu + camerawork columns).';
    }
  }

  String _outputLine() {
    final location = _location;
    if (location == null || location.isEmpty) {
      return 'Choose a location to enable Export.';
    }
    switch (_tab) {
      case ExportTab.sequence:
        final spec = _specs.sequence;
        if (spec.format.isVideo) {
          return '→ ${_singleFileName(_sequenceFileController, spec.format.container.fileExtension)}';
        }
        return '→ ${_sequenceFileNameFor(0)} …';
      case ExportTab.image:
        return '→ ${_singleFileName(_imageFileController, _specs.image.format.stillFormat.fileExtension)}';
      case ExportTab.cels:
        final plan = _celGroupPlan();
        final first = plan.cels.isNotEmpty
            ? plan.cels.first.fileName
            : plan.instructions.isNotEmpty
            ? plan.instructions.first.fileName
            : null;
        return first == null ? '→ (no cels)' : '→ $first …';
      case ExportTab.timesheet:
        if (_specs.timesheet.format == ExportTimesheetFormat.sheetImage) {
          final plan = _timesheetPagePlan();
          return plan.isEmpty
              ? '→ (no cuts)'
              : '→ ${plan.first.fileName}${plan.length > 1 ? ' …' : ''}';
        }
        final cuts = _timesheetCuts();
        return cuts.isEmpty
            ? '→ (no cuts)'
            : '→ CUT${_cutNumberOf(cuts.first)}.xdts'
                  '${cuts.length > 1 ? ' …' : ''}';
    }
  }

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
    final bgR = (bg >> 16) & 0xFF;
    final bgG = (bg >> 8) & 0xFF;
    final bgB = bg & 0xFF;
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

  bool get _hasLocation => _location != null && _location!.isNotEmpty;

  bool get _canExport {
    if (_isExporting || !_hasLocation) {
      return false;
    }
    switch (_tab) {
      case ExportTab.sequence:
        final plan =
            _sequencePlanForRun(video: _specs.sequence.format.isVideo);
        return plan != null && plan.isNotEmpty;
      case ExportTab.image:
        return true;
      case ExportTab.cels:
        return _celGroupPlan().length > 0;
      case ExportTab.timesheet:
        return _specs.timesheet.format == ExportTimesheetFormat.sheetImage
            ? _timesheetPagePlan().isNotEmpty
            : _timesheetCuts().isNotEmpty;
    }
  }

  // --- export runners -------------------------------------------------------

  String _joinLocation(String name) =>
      '$_location${Platform.pathSeparator}$name';

  void _reportProgress(int completed, int total) {
    if (mounted) {
      setState(() {
        _progress = (completed, total);
        _statusMessage = 'Exporting… $completed/$total';
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
      _statusMessage = 'Exporting…';
    });
    try {
      final message = await run();
      if (mounted) {
        setState(() => _statusMessage = message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusMessage = 'Export failed: $error');
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
    }
  }

  /// Public for tests; the Export button is the production entry point.
  Future<void> export() async {
    if (!_canExport) {
      return;
    }
    await _runGuarded(_runCurrentTabExport);
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
      outputDirectory: _location!,
      fileName: _singleFileNameForCurrentTab(),
    );
    setState(() {});
  }

  /// A queued job clicked: its setup returns to the window for editing
  /// and the job leaves the queue (수정 후 재등록 — the v10 flow).
  void _restoreJob(ExportJob job) {
    if (job.status != ExportJobStatus.queued || _isExporting) {
      return;
    }
    setState(() {
      _tab = job.tab;
      _specs = _specs.withSpec(job.spec);
      _location = job.outputDirectory;
      final controller = _fileControllerFor(job.tab);
      final fileName = job.fileName;
      if (controller != null && fileName != null) {
        controller.text = fileName;
      }
      _syncControllersFromSpecs();
    });
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
    final snapshotLocation = _location;
    setState(() {
      _isExporting = true;
      _cancelRequested = false;
      _statusMessage = 'Rendering the queue…';
    });
    var succeeded = 0;
    var failed = 0;
    try {
      while (!_cancelRequested) {
        final job = _queue.nextQueued;
        if (job == null) {
          break;
        }
        _activeJobId = job.id;
        _queue.update(
          job.id,
          (current) => current.copyWith(status: ExportJobStatus.running),
        );
        setState(() {
          _tab = job.tab;
          _specs = _specs.withSpec(job.spec);
          _location = job.outputDirectory;
          final controller = _fileControllerFor(job.tab);
          final fileName = job.fileName;
          if (controller != null && fileName != null) {
            controller.text = fileName;
          }
          _syncControllersFromSpecs();
        });
        _refreshPreview();
        try {
          final message = await _runCurrentTabExport();
          final cancelled = _cancelRequested;
          _queue.update(
            job.id,
            (current) => current.copyWith(
              status: cancelled
                  ? ExportJobStatus.cancelled
                  : ExportJobStatus.succeeded,
              message: message,
            ),
          );
          if (!cancelled) {
            succeeded += 1;
          }
        } catch (error) {
          failed += 1;
          _queue.update(
            job.id,
            (current) => current.copyWith(
              status: ExportJobStatus.failed,
              message: '$error',
            ),
          );
        }
        _activeJobId = null;
      }
    } finally {
      _activeJobId = null;
      if (mounted) {
        setState(() {
          _isExporting = false;
          _progress = null;
          _tab = snapshotTab;
          _specs = snapshotSpecs;
          _location = snapshotLocation;
          _syncControllersFromSpecs();
          _statusMessage =
              'Queue: $succeeded ${_plural(succeeded, 'job')} done'
              '${failed > 0 ? ', $failed failed' : ''}'
              '${_queue.nextQueued != null ? ', rest kept' : ''}.';
        });
        _persist();
        _preview.clear();
        _refreshPreview();
      }
    }
  }

  Future<String> _exportSheetImages() async {
    final plan = _timesheetPagePlan();
    final scale = _specs.timesheet.sheetScale.toDouble();
    final notation = _sheetNotation;
    final summary = await _exportService.exportImages(
      count: plan.length,
      renderImage: (index) {
        final task = plan[index];
        final (_, document, layout) = _sheetDocFor(task.cut);
        return renderTimesheetPageImage(
          document: document,
          layout: layout,
          pageIndex: task.pageIndex,
          notation: notation,
          scale: scale,
        );
      },
      fileNameFor: (index) => plan[index].fileName,
      directoryPath: _location!,
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    if (summary.processed < plan.length) {
      return 'Export cancelled after ${summary.written} '
          '${_plural(summary.written, 'page')}.';
    }
    return 'Exported ${summary.written} sheet '
        '${_plural(summary.written, 'page')}.';
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
    final audioMixPath =
        spec.includeAudio ? await _renderAudioMix(plan) : null;
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
        frameRate: _session.projectFrameRate,
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
            ? 'Export cancelled.'
            : 'Export cancelled after ${summary.written} '
                  '${_plural(summary.written, 'frame')} (partial video kept).';
      }
      return 'Exported video (${summary.written} '
          '${_plural(summary.written, 'frame')}).';
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

  Future<String> _exportPngSequence() async {
    final spec = _specs.sequence;
    final plan = _sequencePlanForRun(video: false)!;
    final renderer = _runRenderer(
      applyLayerFx: spec.applyLayerFx,
      format: spec.format,
    );
    final summary = await _exportService.exportImages(
      count: plan.length,
      renderImage: (index) =>
          renderer.renderComposite(plan[index], spec.sizeMode),
      fileNameFor: _sequenceFileNameFor,
      directoryPath: _location!,
      encode: _stillEncodeFor(spec.format),
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    if (summary.processed < plan.length) {
      return 'Export cancelled after ${summary.written} '
          '${_plural(summary.written, 'file')}.';
    }
    return 'Exported ${summary.written} '
        '${_plural(summary.written, 'frame')}.';
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
      directoryPath: _location!,
      encode: _stillEncodeFor(spec.format),
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    return summary.written == 1
        ? 'Exported $fileName.'
        : 'Nothing to export (empty frame).';
  }

  Future<String> _exportCels() async {
    final spec = _specs.cels;
    final plan = _celGroupPlan();
    final entries = _celEntries(plan);
    // Cels stay raw artwork (no FX) — the renderer carries the paper
    // color for the RGB channel choice; the group render composites the
    // label's members at their static opacities.
    final renderer = _runRenderer(applyLayerFx: false, format: spec.format);
    final summary = await _exportService.exportImages(
      count: entries.length,
      renderImage: (index) {
        final entry = entries[index];
        return switch (entry) {
          ExportCelGroupTask() =>
            renderer.renderCelGroup(entry, spec.sizeMode),
          ExportInstructionTask() => renderInstructionCelImage(
            task: entry,
            size: spec.sizeMode == ExportSizeMode.camera
                ? _session.cameraFrameSize
                : entry.cut.canvasSize,
            background: spec.format.wantsAlpha
                ? null
                : ui.Color(spec.format.backgroundArgb),
          ),
          _ => Future<ui.Image?>.value(),
        };
      },
      fileNameFor: (index) => switch (entries[index]) {
        ExportCelGroupTask(:final fileName) => fileName,
        ExportInstructionTask(:final fileName) => fileName,
        _ => 'cel_$index.png',
      },
      directoryPath: _location!,
      encode: _stillEncodeFor(spec.format),
      isCancelled: () => _cancelRequested,
      onProgress: _reportProgress,
    );
    if (summary.processed < entries.length) {
      return 'Export cancelled after ${summary.written} '
          '${_plural(summary.written, 'file')}.';
    }
    final skipped = summary.processed - summary.written;
    final cels = '${summary.written} ${_plural(summary.written, 'cel')}';
    return skipped > 0
        ? 'Exported $cels ($skipped empty skipped).'
        : 'Exported $cels.';
  }

  Future<String> _exportXdts() async {
    final cuts = _timesheetCuts();
    final defById = _session.cameraInstructionSet.defById;
    var written = 0;
    for (final cut in cuts) {
      final content = buildXdtsContent(
        cut: cut,
        cutNumber: _cutNumberOf(cut),
        instructionDefById: defById,
      );
      final file = File(_joinLocation('CUT${_cutNumberOf(cut)}.xdts'));
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      written += 1;
      _reportProgress(written, cuts.length);
    }
    return 'Exported $written XDTS ${_plural(written, 'sheet')}.';
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
      rate: _session.projectFrameRate,
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
      id: ExportPresetId(
        'preset-${DateTime.now().microsecondsSinceEpoch}',
      ),
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
    final picker = widget.exportDirectoryPicker ?? _pickExportDirectory;
    final directory = await picker();
    if (directory == null || !mounted) {
      return;
    }
    setState(() => _location = directory);
    _persist();
  }

  bool get _singleFileTab =>
      _tab == ExportTab.image ||
      (_tab == ExportTab.sequence && _specs.sequence.format.isVideo);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_anchorCut == null) {
      // R27 #31: nothing to export. An empty state, never a throw.
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
    // LayoutBuilder sits OUTSIDE the window now: AppWindow owns the Dialog,
    // so the room the drawers negotiate over is the screen minus the
    // window's inset, not the dialog's interior.
    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 64.0;
        final availableWidth = constraints.maxWidth - inset;
        final availableHeight = constraints.maxHeight - inset;
        // The drawers yield before the preview does (v10: 전개 ~1020 /
        // 최소 ~700): a tight surface collapses the queue, then the
        // presets, to presentational strips — the stored preference
        // stays untouched.
        var presetsOpen = _presetsOpen;
        var queueOpen = _queueOpen;
        double widthFor() =>
            (presetsOpen ? 152.0 : 22.0) +
            330 +
            272 +
            (queueOpen ? 200.0 : 22.0) +
            4;
        if (widthFor() > availableWidth && queueOpen) {
          queueOpen = false;
        }
        if (widthFor() > availableWidth && presetsOpen) {
          presetsOpen = false;
        }
        final presetsWidth = presetsOpen ? 152.0 : 22.0;
        final queueWidth = queueOpen ? 200.0 : 22.0;
        final width = math.min(widthFor(), availableWidth);
        final height = math.min(620.0, availableHeight);

        return AppWindow(
          windowKey: const ValueKey<String>('export-dialog'),
          title: AppText.strings.exExport,
          titleIcon: Icons.upload_file_outlined,
          onClose: _isExporting ? null : () => Navigator.of(context).pop(),
          width: width,
          height: height,
          scrollBody: false,
          bodyPadding: EdgeInsets.zero,
          tabs: [
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
          ],
          selectedTab: ExportTab.values.indexOf(_tab),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nameBar(theme),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: presetsWidth,
                      child: _presetsZone(open: presetsOpen),
                    ),
                    VerticalDivider(width: 1, color: theme.dividerColor),
                    Expanded(child: _previewZone(theme)),
                    VerticalDivider(width: 1, color: theme.dividerColor),
                    SizedBox(width: 272, child: _settingsZone()),
                    VerticalDivider(width: 1, color: theme.dividerColor),
                    SizedBox(
                      width: queueWidth,
                      child: _queueZone(open: queueOpen),
                    ),
                  ],
                ),
              ),
            ],
          ),
          footerNote: Text(
            _statusMessage ?? '',
            key: const ValueKey<String>('export-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            if (_isExporting)
              AppWindowAction(
                label: 'Cancel',
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
          ],
        );
      },
    );
  }

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
            singleFile ? 'File' : 'Pattern',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          if (singleFile)
            SizedBox(
              width: 180,
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
            Text(
              _patternPreview(),
              key: const ValueKey<String>('export-pattern-preview'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          const SizedBox(width: 14),
          Text(
            'Location',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _location ?? 'Choose a folder…',
              key: const ValueKey<String>('export-location-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: _hasLocation
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey<String>('export-browse-button'),
            onPressed: _isExporting ? null : _browseLocation,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(AppText.strings.exBrowse),
          ),
        ],
      ),
    );
  }

  String _patternPreview() {
    switch (_tab) {
      case ExportTab.sequence:
        return _sequenceFileNameFor(0);
      case ExportTab.cels:
        final plan = _celGroupPlan();
        return plan.cels.isEmpty
            ? (plan.instructions.isEmpty
                  ? '(no cels)'
                  : plan.instructions.first.fileName)
            : plan.cels.first.fileName;
      case ExportTab.timesheet:
        if (_specs.timesheet.format == ExportTimesheetFormat.sheetImage) {
          final plan = _timesheetPagePlan();
          return plan.isEmpty ? '(no cuts)' : plan.first.fileName;
        }
        return 'CUT1.xdts';
      case ExportTab.image:
        return '';
    }
  }

  Widget _presetsZone({required bool open}) {
    if (!open) {
      return ExportDrawerStrip(
        key: const ValueKey<String>('export-presets-strip'),
        caption: 'Presets',
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
          child: InkWell(
            key: const ValueKey<String>('export-presets-collapse'),
            onTap: () {
              setState(() => _presetsOpen = false);
              _persist();
            },
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.chevron_left, size: 13),
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
        return ExportNavBar(
          axis: _celsAxis(_celGroupPlan()),
          position: _celPosition,
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _celPosition = position);
            _refreshPreview();
          },
        );
      case ExportTab.timesheet:
        final plan = _timesheetPagePlan();
        return ExportNavBar(
          axis: ExportNavAxis(
            length: plan.length,
            ticks: [
              for (var i = 1; i < plan.length; i += 1)
                if (plan[i].cut.id != plan[i - 1].cut.id) i,
            ],
            captionOf: (position) {
              final task = plan[position.clamp(0, plan.length - 1)];
              return 'CUT${task.cutNumber}·p${task.pageIndex + 1}';
            },
          ),
          position: _sheetPosition,
          enabled: !_isExporting,
          onChanged: (position) {
            setState(() => _sheetPosition = position);
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
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(8),
              // The preview shows the CROPPED RESULT alone (v10: 오버레이
              // 없음) — or the plan headline while nothing has resolved.
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
                  return RawImage(
                    key: const ValueKey<String>('export-preview-image'),
                    image: image,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  );
                },
              ),
            ),
          ),
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

  List<Widget> _sequenceModules() {
    final spec = _specs.sequence;
    final projectScope = spec.scope == ExportScopeKind.project;
    return [
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: ExportFormatModule.summarize(spec.format),
        expanded: _expandedFor('format', fallback: true),
        onToggle: () => _toggleExpanded('format', fallback: true),
        resetEnabled: spec.format != const ExportFormatSelection(),
        onReset: () =>
            _updateSpec(spec.copyWith(format: const ExportFormatSelection())),
        child: ExportFormatModule(
          selection: spec.format,
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
          enabled: !_isExporting,
          onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exScope,
        summary: ExportScopeModule.summarize(spec.scope),
        expanded: _expandedFor('scope', fallback: true),
        onToggle: () => _toggleExpanded('scope', fallback: true),
        child: ExportScopeModule(
          scope: spec.scope,
          enabled: !_isExporting,
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
          // The in/out fields live on the nav bar's ends (v10) — the
          // module keeps the scope choice alone.
          note: projectScope
              ? 'No cut list here — in/out alone trims the sequence.'
              : null,
        ),
      ),
      ExportAccordion(
        title: 'Size',
        summary: ExportSizeModule.summarize(spec.sizeMode),
        expanded: _expandedFor('size', fallback: true),
        onToggle: () => _toggleExpanded('size', fallback: true),
        child: ExportSizeModule(
          sizeMode: spec.sizeMode,
          cameraSize: _session.cameraFrameSize,
          canvasSizes: _scopeCanvasSizes(spec.scope),
          projectScope: projectScope,
          enabled: !_isExporting,
          onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
        ),
      ),
      if (spec.format.isVideo)
        ExportAccordion(
          title: AppText.strings.exAudio,
          summary: spec.includeAudio
              ? 'SE muxed · ${spec.format.videoCodec.isProRes ? 'PCM' : 'AAC'}'
              : 'Off',
          expanded: _expandedFor('audio'),
          onToggle: () => _toggleExpanded('audio'),
          child: ExportToggleRow(
            widgetKey: const ValueKey<String>('export-audio-toggle'),
            label: AppText.strings.exMuxSeMix,
            value: spec.includeAudio,
            onChanged: _isExporting
                ? null
                : (value) => _updateSpec(spec.copyWith(includeAudio: value)),
          ),
        ),
      if (spec.format.isStill)
        ExportAccordion(
          title: AppText.strings.exNaming,
          summary: ExportSequenceNamingModule.summarize(
            spec.naming,
            spec.format.stillFormat.fileExtension,
          ),
          expanded: _expandedFor('naming'),
          onToggle: () => _toggleExpanded('naming'),
          resetEnabled: spec.naming != const ExportSequenceNaming(),
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
      ExportAccordion(
        title: AppText.strings.exOptions,
        summary: spec.applyLayerFx ? 'FX on' : 'FX off',
        expanded: _expandedFor('options'),
        onToggle: () => _toggleExpanded('options'),
        child: ExportToggleRow(
          widgetKey: const ValueKey<String>('export-apply-fx-toggle'),
          label: AppText.strings.exApplyLayerFxHelp,
          value: spec.applyLayerFx,
          onChanged: _isExporting
              ? null
              : (value) {
                  _preview.clear();
                  _updateSpec(spec.copyWith(applyLayerFx: value));
                },
        ),
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
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: ExportFormatModule.summarize(spec.format),
        expanded: _expandedFor('format', fallback: true),
        onToggle: () => _toggleExpanded('format', fallback: true),
        child: ExportFormatModule(
          selection: spec.format,
          capabilities: ExportFormatCapabilities(
            stills: const [
              ExportStillFormat.png,
              ExportStillFormat.jpg,
              ExportStillFormat.psd,
            ],
            stillEnabled: _availability.stillAllowed,
          ),
          enabled: !_isExporting,
          onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
        ),
      ),
      ExportAccordion(
        title: 'Size',
        summary: ExportSizeModule.summarize(spec.sizeMode),
        expanded: _expandedFor('size', fallback: true),
        onToggle: () => _toggleExpanded('size', fallback: true),
        child: ExportSizeModule(
          sizeMode: spec.sizeMode,
          cameraSize: _session.cameraFrameSize,
          canvasSizes: {_activeCut.canvasSize},
          projectScope: false,
          enabled: !_isExporting,
          onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exOptions,
        summary: spec.applyLayerFx ? 'FX on' : 'FX off',
        expanded: _expandedFor('options'),
        onToggle: () => _toggleExpanded('options'),
        child: ExportToggleRow(
          widgetKey: const ValueKey<String>('export-image-fx-toggle'),
          label: AppText.strings.exApplyLayerFx,
          value: spec.applyLayerFx,
          onChanged: _isExporting
              ? null
              : (value) {
                  _preview.clear();
                  _updateSpec(spec.copyWith(applyLayerFx: value));
                },
        ),
      ),
    ];
  }

  // --- Cels delta plumbing (v10 ⑥: 규칙 적용 후 델타만) ------------------

  ExportCelsSelection _activeCelsSelection({bool withDelta = true}) =>
      resolveExportCelsSelection(
        cut: _activeCut,
        spec: _specs.cels,
        delta: withDelta ? _overrides.deltaFor(_activeCut.id) : null,
      );

  /// Writes a per-layer include for the ACTIVE cut — storing null when
  /// the wish equals the rule outcome, so the delta stays exactly the
  /// hand exceptions (Reset = clear, preset switches stay live).
  void _writeLayerOverride(Layer layer, bool include) {
    final rule = _activeCelsSelection(withDelta: false).includes(layer);
    final value = include == rule ? null : include;
    final cutId = _activeCut.id;
    _session.repository.updateExportOverrides(
      (overrides) => overrides.withCelsDelta(
        cutId,
        (overrides.deltaFor(cutId) ?? ExportCelsCutDelta())
            .withLayerOverride(layer.id, value),
      ),
    );
    setState(() {});
    _refreshPreview();
  }

  void _clearOverridesFor(Iterable<LayerId> ids) {
    final cutId = _activeCut.id;
    _session.repository.updateExportOverrides((overrides) {
      var delta = overrides.deltaFor(cutId) ?? ExportCelsCutDelta();
      for (final id in ids) {
        delta = delta.withLayerOverride(id, null);
      }
      return overrides.withCelsDelta(cutId, delta);
    });
    setState(() {});
    _refreshPreview();
  }

  /// The label the Layers accordion edits: the current nav cel's base.
  Layer? _currentCelLabel() {
    final entries = _celEntries(_celGroupPlan());
    if (entries.isEmpty) {
      return null;
    }
    final entry = entries[_celPosition.clamp(0, entries.length - 1)];
    if (entry is ExportCelGroupTask && entry.cut.id == _activeCut.id) {
      return entry.baseLayer;
    }
    final selection = _activeCelsSelection();
    for (final layer in selection.celLayers) {
      if (!isAttachedLayer(layer)) {
        return layer;
      }
    }
    return null;
  }

  bool _isAttachedRow(Layer layer) => layer.attachedToLayerId != null;

  List<ExportCutEntry> _scopeCutEntries() {
    final cuts = resolveExportCuts(
      project: _session.repository.requireProject(),
      activeCutId: _activeCut.id,
      range: ExportRange.allCuts,
    );
    return [
      for (var i = 0; i < cuts.length; i += 1)
        (id: cuts[i].id, number: i + 1),
    ];
  }

  Widget _scopeCutGrid() {
    final entries = _scopeCutEntries();
    return ExportCutGrid(
      cuts: entries,
      isIncluded: _overrides.cutIncluded,
      enabled: !_isExporting,
      onToggle: (id, included) {
        _session.repository.updateExportOverrides(
          (overrides) => overrides.withCutIncluded(id, included),
        );
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
            next = next.withCutIncluded(
              entry.id,
              entry.number >= start && entry.number <= end,
            );
          }
          return next;
        });
        setState(() {});
        _refreshPreview();
      },
    );
  }

  Widget _celsAccordionBody() {
    final theme = Theme.of(context);
    final spec = _specs.cels;
    final selection = _activeCelsSelection();
    final labels = [
      for (final layer in selection.celLayers)
        if (!_isAttachedRow(layer)) layer,
    ];
    final current = _currentCelLabel();
    final entries = _celEntries(_celGroupPlan());

    void jumpToLabel(Layer label) {
      for (var i = 0; i < entries.length; i += 1) {
        final entry = entries[i];
        final matches = switch (entry) {
          ExportCelGroupTask(:final baseLayer) => baseLayer.id == label.id,
          ExportInstructionTask(:final layer) => layer.id == label.id,
          _ => false,
        };
        if (matches) {
          setState(() => _celPosition = i);
          _refreshPreview();
          return;
        }
      }
    }

    final includedIds = {
      for (final layer in selection.celLayers) layer.id,
      for (final layer in selection.instructionLayers) layer.id,
    };
    final addCandidates = [
      for (final layer in _activeCut.layers)
        if (!includedIds.contains(layer.id) &&
            !_isAttachedRow(layer) &&
            layerKindExportsCels(layer.kind))
          layer,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final label in labels)
          ExportLayerRow(
            key: ValueKey<String>('export-cels-label-${label.id.value}'),
            layer: label,
            selected: current?.id == label.id,
            onTap: () => jumpToLabel(label),
            onRemove: _isExporting
                ? null
                : () => _writeLayerOverride(label, false),
          ),
        for (final layer in selection.instructionLayers)
          ExportLayerRow(
            key: ValueKey<String>('export-cels-label-${layer.id.value}'),
            layer: layer,
            onTap: () => jumpToLabel(layer),
            onRemove: _isExporting
                ? null
                : () => _writeLayerOverride(layer, false),
          ),
        Divider(height: 8, color: theme.dividerColor),
        ExportToggleRow(
          widgetKey: const ValueKey<String>('export-cels-instruction-toggle'),
          label: AppText.strings.exInstructionLayer,
          value: spec.includeInstructionLayers,
          onChanged: _isExporting
              ? null
              : (value) => _updateSpec(
                  spec.copyWith(includeInstructionLayers: value),
                ),
        ),
        Tooltip(
          message: '용지 레이어 타입이 도입되면 여기서 합류합니다.',
          child: ExportToggleRow(
            label: '용지',
            value: false,
            onChanged: null,
          ),
        ),
        const ExportMarkSlotsRow(),
        Divider(height: 8, color: theme.dividerColor),
        Text(
          'ADD FROM TIMELINE',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 8,
            letterSpacing: 1.1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (addCandidates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Every timeline row is already in.',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final layer in addCandidates)
            ExportLayerRow(
              key: ValueKey<String>('export-cels-add-${layer.id.value}'),
              layer: layer,
              dimmed: true,
              includeDot: false,
              dotKey: ValueKey<String>(
                'export-cels-adddot-${layer.id.value}',
              ),
              onDotTap: _isExporting
                  ? null
                  : () => _writeLayerOverride(layer, true),
            ),
      ],
    );
  }

  Widget _celsLayersAccordionBody(Layer label) {
    final spec = _specs.cels;
    final selection = _activeCelsSelection();
    final attached = attachedLayersOf(label.id, _activeCut.layers);
    final members = [
      for (final layer in _activeCut.layers)
        if (layer.id == label.id ||
            attached.any((candidate) => candidate.id == layer.id))
          layer,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in members)
          ExportLayerRow(
            key: ValueKey<String>('export-cels-member-${member.id.value}'),
            layer: member,
            includeDot: selection.includes(member),
            dotKey: ValueKey<String>(
              'export-cels-memberdot-${member.id.value}',
            ),
            trailingTag: member.id == label.id
                ? '기준'
                : ExportLayerRow.attachTag(member),
            // The base leaves through the label's ×, not its own dot.
            onDotTap: member.id == label.id || _isExporting
                ? null
                : () => _writeLayerOverride(
                    member,
                    !selection.includes(member),
                  ),
          ),
        Divider(height: 8, color: Theme.of(context).dividerColor),
        ExportToggleRow(
          widgetKey: const ValueKey<String>('export-cels-sync-toggle'),
          label: AppText.strings.exSyncAttach,
          value: spec.includeSyncedAttach,
          onChanged: _isExporting
              ? null
              : (value) =>
                    _updateSpec(spec.copyWith(includeSyncedAttach: value)),
        ),
        ExportToggleRow(
          widgetKey: const ValueKey<String>('export-cels-free-toggle'),
          label: AppText.strings.exFreeAttach,
          value: spec.includeFreeAttach,
          onChanged: _isExporting
              ? null
              : (value) =>
                    _updateSpec(spec.copyWith(includeFreeAttach: value)),
        ),
        ExportToggleRow(
          widgetKey: const ValueKey<String>('export-cels-folder-toggle'),
          label: AppText.strings.exFolderMembers,
          value: spec.includeFolderMembers,
          onChanged: _isExporting
              ? null
              : (value) =>
                    _updateSpec(spec.copyWith(includeFolderMembers: value)),
        ),
        const ExportMarkSlotsRow(),
      ],
    );
  }

  List<Widget> _celsModules() {
    final spec = _specs.cels;
    final delta = _overrides.deltaFor(_activeCut.id);
    final labelLevelIds = <LayerId>{
      for (final layer in _activeCut.layers)
        if (!_isAttachedRow(layer)) layer.id,
    };
    final hasLabelDelta =
        delta != null &&
        delta.layerOverrides.keys.any(labelLevelIds.contains);
    final hasMemberDelta =
        delta != null &&
        delta.layerOverrides.keys.any((id) => !labelLevelIds.contains(id));
    final currentLabel = _currentCelLabel();
    return [
      ExportAccordion(
        title: AppText.strings.exCels,
        summary: '${_celGroupPlan().length} files',
        expanded: _expandedFor('cels', fallback: true),
        onToggle: () => _toggleExpanded('cels', fallback: true),
        resetEnabled: hasLabelDelta,
        onReset: () => _clearOverridesFor(labelLevelIds),
        child: _celsAccordionBody(),
      ),
      if (currentLabel != null)
        ExportAccordion(
          title: 'Layers · ${currentLabel.name}',
          summary: '',
          expanded: _expandedFor('layers', fallback: true),
          onToggle: () => _toggleExpanded('layers', fallback: true),
          resetEnabled: hasMemberDelta,
          onReset: () => _clearOverridesFor({
            for (final layer in _activeCut.layers)
              if (_isAttachedRow(layer)) layer.id,
          }),
          child: _celsLayersAccordionBody(currentLabel),
        ),
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: ExportFormatModule.summarize(spec.format),
        expanded: _expandedFor('format', fallback: true),
        onToggle: () => _toggleExpanded('format', fallback: true),
        child: ExportFormatModule(
          selection: spec.format,
          capabilities: ExportFormatCapabilities(
            stills: const [
              ExportStillFormat.png,
              ExportStillFormat.jpg,
              ExportStillFormat.psd,
            ],
            stillEnabled: _availability.stillAllowed,
          ),
          enabled: !_isExporting,
          onChanged: (format) => _updateSpec(spec.copyWith(format: format)),
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exFilter,
        summary: spec.onTimesheetOnly ? 'Sheet only' : 'All visible',
        expanded: _expandedFor('filter'),
        onToggle: () => _toggleExpanded('filter'),
        child: ExportToggleRow(
          widgetKey: const ValueKey<String>('export-cel-timesheet-only-toggle'),
          label: AppText.strings.exOnTimesheetOnly,
          value: spec.onTimesheetOnly,
          onChanged: _isExporting
              ? null
              : (value) =>
                    _updateSpec(spec.copyWith(onTimesheetOnly: value)),
        ),
      ),
      ExportAccordion(
        title: 'Size',
        summary: ExportSizeModule.summarize(spec.sizeMode),
        expanded: _expandedFor('size'),
        onToggle: () => _toggleExpanded('size'),
        child: ExportSizeModule(
          sizeMode: spec.sizeMode,
          cameraSize: _session.cameraFrameSize,
          canvasSizes: {_activeCut.canvasSize},
          projectScope: false,
          enabled: !_isExporting,
          onChanged: (mode) => _updateSpec(spec.copyWith(sizeMode: mode)),
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exNaming,
        summary: ExportCelNamingModule.summarize(spec.naming),
        expanded: _expandedFor('naming'),
        onToggle: () => _toggleExpanded('naming'),
        resetEnabled: spec.naming != const ExportCelNaming(),
        onReset: () {
          _updateSpec(spec.copyWith(naming: const ExportCelNaming()));
          _celSuffixController.text = '';
        },
        child: ExportCelNamingModule(
          naming: spec.naming,
          enabled: !_isExporting,
          suffixController: _celSuffixController,
          onChanged: (naming) => _updateSpec(spec.copyWith(naming: naming)),
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exScope,
        summary: ExportScopeModule.summarize(spec.scope),
        expanded: _expandedFor('scope'),
        onToggle: () => _toggleExpanded('scope'),
        child: ExportScopeModule(
          scope: spec.scope,
          enabled: !_isExporting,
          onChanged: (scope) => _updateSpec(spec.copyWith(scope: scope)),
          // The v10 grid (Timesheet와 공용 부품): checks save with the
          // project.
          child: spec.scope == ExportScopeKind.project
              ? _scopeCutGrid()
              : null,
        ),
      ),
    ];
  }

  List<Widget> _timesheetModules() {
    final spec = _specs.timesheet;
    return [
      ExportAccordion(
        title: AppText.strings.exFormat,
        summary: spec.format == ExportTimesheetFormat.sheetImage
            ? 'Sheet PNG · ${spec.sheetScale}x'
            : 'XDTS',
        expanded: _expandedFor('format', fallback: true),
        onToggle: () => _toggleExpanded('format', fallback: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 5,
              children: [
                ExportChip(
                  key: const ValueKey<String>('export-tsformat-sheet'),
                  label: AppText.strings.exSheetPng,
                  selected:
                      spec.format == ExportTimesheetFormat.sheetImage,
                  onTap: _isExporting
                      ? null
                      : () => _updateSpec(
                          spec.copyWith(
                            format: ExportTimesheetFormat.sheetImage,
                          ),
                        ),
                ),
                ExportChip(
                  key: const ValueKey<String>('export-tsformat-xdts'),
                  label: 'XDTS',
                  selected: spec.format == ExportTimesheetFormat.xdts,
                  onTap: _isExporting
                      ? null
                      : () => _updateSpec(
                          spec.copyWith(format: ExportTimesheetFormat.xdts),
                        ),
                ),
              ],
            ),
            if (spec.format == ExportTimesheetFormat.sheetImage) ...[
              const SizedBox(height: 6),
              ExportModuleRow(
                label: AppText.strings.brScale,
                child: Wrap(
                  spacing: 5,
                  children: [
                    for (final scale in const [1, 2, 3, 4])
                      ExportChip(
                        key: ValueKey<String>('export-tsscale-$scale'),
                        label: '${scale}x',
                        selected: spec.sheetScale == scale,
                        onTap: _isExporting
                            ? null
                            : () => _updateSpec(
                                spec.copyWith(sheetScale: scale),
                              ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 5),
            exportModuleNote(
              context,
              spec.format == ExportTimesheetFormat.sheetImage
                  ? "The panel's B4 paper rendered per page — what the "
                        'Timesheet tab shows is what prints.'
                  : 'One .xdts digital timesheet per cut (OpenToonz/CSP-'
                        'compatible sheet data, no rendering). TDTS and the '
                        'Auto Sheet JSON join once their sample files '
                        'arrive.',
            ),
          ],
        ),
      ),
      ExportAccordion(
        title: AppText.strings.exScope,
        summary: ExportScopeModule.summarize(spec.scope),
        expanded: _expandedFor('scope', fallback: true),
        onToggle: () => _toggleExpanded('scope', fallback: true),
        child: ExportScopeModule(
          scope: spec.scope,
          enabled: !_isExporting,
          onChanged: (scope) => _updateSpec(spec.copyWith(scope: scope)),
          // The same grid part the Cels scope uses (v10: 공용 부품).
          child: spec.scope == ExportScopeKind.project
              ? _scopeCutGrid()
              : null,
        ),
      ),
    ];
  }

  Widget _queueZone({required bool open}) {
    if (!open) {
      return ExportDrawerStrip(
        key: const ValueKey<String>('export-queue-strip'),
        caption: 'Queue',
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
          child: InkWell(
            key: const ValueKey<String>('export-queue-collapse'),
            onTap: () {
              setState(() => _queueOpen = false);
              _persist();
            },
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.chevron_right, size: 13),
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
