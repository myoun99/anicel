import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/timesheet_info.dart';
import '../../services/cache_invalidation_executor.dart';
import '../brush/brush_tool_state.dart';
import '../brush/sheet_canvas_panel.dart' show SheetStrokeHold;
import '../editor_session_manager.dart';
import '../sheet/sheet_image_cache.dart' show SheetImageLookup;
import '../sheet/sheet_photo_drop.dart';
import 'timesheet_document_painter.dart';
import 'timesheet_header_edit_layer.dart';
import 'timesheet_ink_controller.dart';
import 'timesheet_ink_layer.dart';
import 'timesheet_strata.dart';
import 'timesheet_words_in.dart';

/// A CUT'S TIMESHEET AS IT IS EDITED, over a snapped view: the strata, the
/// header boxes and memo bands typed in place, the ink windows while the
/// sheet draws, and the photo drop.
///
/// 🗣️ONE stack for the timesheet panel and the cel export's page (I-127,
/// 유저 2026-10-25: 「셀 출력의 타임시트나 컷봉투에도 타임시트 용지패널/
/// 컷봉투 용지패널이랑 동일하게 잉크 사용이라던가, 눌러서 원화 이름
/// 텍스트편집이라던가 동등하게 가능하도록. 법 통일하면서」). ↩️The panel's
/// host wrote it inline, and the export showed the page as a picture.
class TimesheetPaper extends StatelessWidget {
  const TimesheetPaper({
    super.key,
    required this.session,
    required this.layout,
    required this.cutId,
    required this.viewport,
    required this.strokeHold,
    required this.cacheInvalidationSink,
    this.inkController,
    this.inkTool,
    this.imageFor,
    this.imageRepaint,
  });

  final EditorSessionManager session;
  final TimesheetDocumentLayout layout;

  /// The cut the sheet prints — where its ink and its typed words land.
  final CutId cutId;

  /// The view as the sheet's units read it ([SheetCanvasPanel.content]).
  final CanvasViewport viewport;

  /// The sheet's live-stroke hold ([SheetCanvasPanel.strokeHold]).
  final SheetStrokeHold strokeHold;

  final CacheInvalidationSink cacheInvalidationSink;

  /// The sheet's ink; null prints none and takes none.
  final TimesheetInkController? inkController;

  /// The tool in hand while the sheet DRAWS — its ink windows are mounted
  /// ([SheetCanvasPanel.drawingOn]); null while it does not.
  final ValueListenable<BrushToolState>? inkTool;

  /// The pool files the ink's photos are drawn from (I-97).
  final SheetImageLookup? imageFor;
  final Listenable? imageRepaint;

  @override
  Widget build(BuildContext context) {
    final inkController = this.inkController;
    final inkTool = this.inkTool;
    final drawing = inkController != null && inkTool != null;
    return Stack(
      children: [
        // The sheet paints in strata (UI-R10 #9, the PSD layering live):
        // the printed FORM below, the CONTENT above, the saved INK over
        // both — each re-recorded only when what it prints changes.
        //
        // Each stratum is baked rather than merely boundaried. This panel
        // measured 13.1 ms/frame of raster — 47% of the whole app's — while
        // sitting perfectly still, because a boundary stops the UI thread
        // re-RECORDING and does nothing about the GPU re-EXECUTING. The
        // form alone is ~334 lines and ~111 text paragraphs of B4 sheet at
        // every frame the app happens to produce.
        Positioned.fill(
          child: TimesheetStrata(
            layout: layout,
            viewport: viewport,
            words: timesheetWordsIn(
              session.languageSettings.value.notationLanguage,
            ),
            dragPreview: session.dragPreview,
            cutId: cutId,
            stroking: strokeHold,
            ink: inkController == null
                ? null
                : (controller: inkController, live: drawing),
            imageFor: imageFor,
            imageRepaint: imageRepaint,
          ),
        ),
        // Under the ink windows: reachable exactly when the brush is off
        // (the switch doubles as the edit-mode switch).
        Positioned.fill(
          child: TimesheetHeaderEditLayer(
            key: const ValueKey<String>('timesheet-header-edit-layer'),
            layout: layout,
            viewport: viewport,
            onMemoCommitted: (page, memo) => session.cutVerbs.updateCutNote(
              cutId: cutId,
              page: page,
              note: memo,
            ),
            headerCommits: _headerCommits(),
          ),
        ),
        if (drawing)
          Positioned.fill(
            // The tool-state boundary (R18 UI-3): the brush reaches only
            // this small overlay — the sheet document above never rebuilds
            // for it — and since H40 ② (2026-09-24) not even the overlay
            // does: its windows read the brush when a stroke starts.
            child: TimesheetInkLayer(
              key: const ValueKey<String>('timesheet-ink-layer'),
              controller: inkController,
              layout: layout,
              cutId: cutId,
              brushToolState: inkTool,
              historyManager: session.historyManager,
              viewport: viewport,
              strokeActive: strokeHold,
              cacheInvalidationSink: cacheInvalidationSink,
              imageFor: imageFor,
              imageRepaint: imageRepaint,
              photoHold: session.sheetPhotoHold,
            ),
          ),
        // A pool picture dropped on a page is its photo (I-97).
        if (inkController != null)
          Positioned.fill(
            child: SheetPhotoDrop(
              session: session,
              ink: inkController,
              windows: () => timesheetInkWindows(layout: layout, cutId: cutId),
              viewport: viewport,
              cacheInvalidationSink: cacheInvalidationSink,
            ),
          ),
      ],
    );
  }

  /// Where each header box edited in place lands (I-112): the work's
  /// episode and title — the values its settings show — the cut's name,
  /// and its sheet worker ([TimesheetHeaderEditLayer]) — on the cut the
  /// sheet prints (I-127).
  Map<TimesheetHeaderField, ValueChanged<String>> _headerCommits() {
    void work(TimesheetInfo Function(TimesheetInfo info) edit) =>
        session.updateTimesheetInfo(edit(session.timesheetInfo));
    return {
      TimesheetHeaderField.episode: (episode) =>
          work((info) => info.copyWith(episode: episode)),
      TimesheetHeaderField.title: (title) =>
          work((info) => info.copyWith(title: title)),
      // ⛔An empty name is no cut's name — the rename window refuses one
      // inline ([RenameCutDialog]); a box has no line to say so, so it
      // keeps the name it prints.
      TimesheetHeaderField.cut: (name) {
        if (name.isNotEmpty) {
          session.cutVerbs.renameCuts({cutId: name});
        }
      },
      TimesheetHeaderField.name: (name) =>
          session.cutVerbs.setCutSheetArtist(cutId, name),
    };
  }
}
