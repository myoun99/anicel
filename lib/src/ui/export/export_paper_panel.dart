import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/sheet_canvas_panel.dart';
import '../editor_session_manager.dart';
import '../envelope/cut_envelope_paper.dart';
import '../sheet/paper_editing.dart';
import '../timesheet/timesheet_document_painter.dart'
    show TimesheetDocumentLayout;
import '../timesheet/timesheet_paper.dart';

/// Which of a cut's papers a page of the Cels list is, as it is ruled.
sealed class ExportPaper {
  const ExportPaper();
}

/// Page [page] of [cutId]'s timesheet, laid out as [layout].
final class ExportTimesheetPage extends ExportPaper {
  const ExportTimesheetPage({
    required this.cutId,
    required this.layout,
    required this.page,
  });

  final CutId cutId;
  final TimesheetDocumentLayout layout;
  final int page;
}

/// [owner]'s cut envelope, its form ruled onto the paper the export writes
/// ([layout]).
final class ExportEnvelopePage extends ExportPaper {
  const ExportEnvelopePage({
    required this.owner,
    required this.layout,
    required this.source,
  });

  final CutId owner;
  final CutEnvelopeLayout layout;
  final CutEnvelopeSource source;
}

/// A PAGE OF A CUT'S PAPERS IN THE CEL EXPORT, AS IT IS EDITED — the
/// timesheet's page or the cut envelope the Cels list stands on, written on
/// as its panel writes on it: its ink, its boxes typed in place, its brush
/// switch, under the tool in hand.
///
/// 🗣️I-127 (유저 2026-10-25): 「셀 출력의 타임시트나 컷봉투에도 타임시트
/// 용지패널/컷봉투 용지패널이랑 동일하게 잉크 사용이라던가, 눌러서 원화 이름
/// 텍스트편집이라던가 동등하게 가능하도록. 법 통일하면서 … 동일하게 선택중인
/// 도구로 편집하는느낌」. The paper is the panels' ([TimesheetPaper],
/// [CutEnvelopePaper]) on the panels' shell ([SheetCanvasPanel]), over the
/// panels' own ink and switches ([PaperEditing]); what is the window's is
/// which page, the paper it is written on and the file it is written to.
/// ↩️The window showed the page as a picture of its file.
class ExportPaperPanel extends StatefulWidget {
  const ExportPaperPanel({
    super.key,
    required this.session,
    required this.editing,
    required this.paper,
    this.fileName,
    this.fileAbsent = false,
    this.enabled = true,
  });

  final EditorSessionManager session;

  /// The workspace's ink, switches and pictures, and the tool in hand.
  final PaperEditing editing;

  final ExportPaper paper;

  /// The file the page is written to ([SheetCanvasPanel.documentName]).
  final String? fileName;
  final bool fileAbsent;

  /// False while an export runs: the page takes no stroke, no typing and no
  /// flip of its switch — the run is writing it — and is still framed as
  /// the window likes.
  final bool enabled;

  @override
  State<ExportPaperPanel> createState() => _ExportPaperPanelState();
}

class _ExportPaperPanelState extends State<ExportPaperPanel> {
  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => widget.session.setBrushInputActive(live),
  );

  /// Commit sink required by the panel API; the sheets' ink invalidations
  /// stay local, as on their panels.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  @override
  void dispose() {
    _strokeHold.dispose();
    super.dispose();
  }

  /// The switch of the sheet [paper] is a page of — its panel's.
  ValueNotifier<bool> _switchOf(ExportPaper paper) => switch (paper) {
    ExportTimesheetPage() => widget.editing.timesheetBrushAllowed,
    ExportEnvelopePage() => widget.editing.envelopeBrushAllowed,
  };

  @override
  Widget build(BuildContext context) {
    final allowed = _switchOf(widget.paper);
    return ValueListenableBuilder<bool>(
      valueListenable: allowed,
      builder: (context, brushAllowed, _) => switch (widget.paper) {
        final ExportTimesheetPage page => _timesheet(
          page,
          allowed,
          drawing: widget.enabled && brushAllowed,
        ),
        final ExportEnvelopePage page => _envelope(
          page,
          allowed,
          drawing: widget.enabled && brushAllowed,
        ),
      },
    );
  }

  /// The brush switch, its panel's — standing off while a run writes.
  ({bool allowed, ValueChanged<bool>? onChanged, String keyPrefix})
  _brushSwitch(ValueNotifier<bool> allowed, String keyPrefix) => (
    allowed: allowed.value,
    onChanged: widget.enabled ? (value) => allowed.value = value : null,
    keyPrefix: keyPrefix,
  );

  /// [paper] as the window takes presses on it: none while a run writes.
  Widget _takesPresses(Widget paper) =>
      AbsorbPointer(absorbing: !widget.enabled, child: paper);

  Widget _timesheet(
    ExportTimesheetPage page,
    ValueNotifier<bool> allowed, {
    required bool drawing,
  }) {
    final editing = widget.editing;
    final layout = page.layout;
    editing.timesheetInk.syncGeometry(layout);
    // The page's file is the page alone: the view stops at its paper.
    final paper = layout.pageRect(page.page);
    return SheetCanvasPanel(
      // Another page is a view not framed yet.
      key: ValueKey<(CutId, int)>((page.cutId, page.page)),
      cacheInvalidationSink: _cacheInvalidationSink,
      sheetSize: layout.documentSize,
      paperScale: layout.paperScale,
      viewport: null,
      unframedFit: paper,
      fitFocusRect: paper,
      viewLimit: paper,
      brushSwitch: _brushSwitch(allowed, 'export-timesheet'),
      documentName: widget.fileName,
      documentAbsent: widget.fileAbsent,
      oneToOneOnPill: true,
      drawingOn: drawing,
      brushToolState: editing.tool,
      strokeHold: _strokeHold,
      content: (context, viewport) => _takesPresses(
        TimesheetPaper(
          session: widget.session,
          layout: layout,
          cutId: page.cutId,
          viewport: viewport,
          strokeHold: _strokeHold,
          cacheInvalidationSink: _cacheInvalidationSink,
          inkController: editing.timesheetInk,
          inkTool: drawing ? editing.tool : null,
          imageFor: editing.imageFor,
          imageRepaint: editing.imageRepaint,
        ),
      ),
    );
  }

  Widget _envelope(
    ExportEnvelopePage page,
    ValueNotifier<bool> allowed, {
    required bool drawing,
  }) {
    final editing = widget.editing;
    final layout = page.layout;
    // Ink is measured against the form, so this paper — the export's, of
    // another size than the panel's — writes where the panel does.
    editing.envelopeInk.syncGeometry(aspectRatio: layout.form.aspectRatio);
    final paper = Offset.zero & Size(layout.paperWidth, layout.paperHeight);
    return SheetCanvasPanel(
      key: ValueKey<(CutId, Size)>((page.owner, paper.size)),
      cacheInvalidationSink: _cacheInvalidationSink,
      // The form is ruled straight onto the paper's pixels, so a unit here
      // IS a pixel — the panel's case.
      sheetSize: paper.size,
      viewport: null,
      unframedFit: paper,
      fitFocusRect: paper,
      viewLimit: paper,
      brushSwitch: _brushSwitch(allowed, 'export-envelope'),
      documentName: widget.fileName,
      documentAbsent: widget.fileAbsent,
      oneToOneOnPill: true,
      drawingOn: drawing,
      brushToolState: editing.tool,
      strokeHold: _strokeHold,
      content: (context, viewport) => _takesPresses(
        CutEnvelopePaper(
          session: widget.session,
          layout: layout,
          source: page.source,
          owner: page.owner,
          viewport: viewport,
          strokeHold: _strokeHold,
          cacheInvalidationSink: _cacheInvalidationSink,
          inkController: editing.envelopeInk,
          inkTool: drawing ? editing.tool : null,
          imageFor: editing.imageFor,
          imageRepaint: editing.imageRepaint,
        ),
      ),
    );
  }
}
