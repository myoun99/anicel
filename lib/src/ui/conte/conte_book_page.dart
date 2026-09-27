import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_page_marks.dart'
    show conteCellTextSize, conteInkArgb;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../brush/sheet_canvas_panel.dart' show SheetStrokeHold;
import '../editor_session_manager.dart';
import '../effective_device_pixel_ratio.dart';
import '../input/control_press_claim.dart';
import '../sheet/sheet_strata.dart';
import '../sheet/sheet_text_edit_layer.dart';
import '../sheet_painting.dart' show SheetPictureLookup;
import '../timeline/timeline_drag_preview.dart'
    show CutTrimDragPreview, TimelineDragPreview;
import 'conte_fonts.dart';
import 'conte_ink.dart';
import 'conte_page_painter.dart';
import 'conte_picture_ink.dart';
import 'conte_picture_live.dart';
import 'conte_words_in.dart';

/// One page of the conte's book on the panel — every layer in the page's
/// own space under [viewport], the panel's view moved to where the page
/// lies in the stack (F-201): its printed strata, its cells' presses, its
/// ACTION editing and the pictures drawing live.
///
/// ⛔The pen is not here. One ink layer lies over every page on screen
/// (`ConteInkLayer`), its windows moved to their pages — a layer per page
/// would take every press for the page on top.
class ConteBookPage extends StatelessWidget {
  const ConteBookPage({
    super.key,
    required this.page,
    required this.source,
    required this.viewport,
    required this.session,
    required this.pictureFor,
    required this.onSelectCell,
    required this.drawing,
    required this.strokeHold,
    this.imageFor,
    this.imageRepaint,
    this.picturesLanded,
    this.inkController,
    this.pictures = const [],
    this.cels,
  });

  final ContePageLayout page;
  final ConteSheetSource source;

  /// The panel's view, moved to where this page lies.
  final CanvasViewport viewport;
  final EditorSessionManager session;

  /// A cell's picture at the size its window shows it.
  final SheetPictureLookup pictureFor;

  /// A cell's press: its cut, its storyboard row and its frame.
  final ValueChanged<ContePlacedCell> onSelectCell;

  /// Whether the sheet takes ink now — the live windows' keys stand down
  /// in the printed ink while it does.
  final bool drawing;

  /// Raised while the pen is down on the sheet: the ink stratum stands down
  /// from its bake for the stroke.
  final SheetStrokeHold strokeHold;

  /// A media image by its asset path — the logo, the cover's picture.
  final ui.Image? Function(String assetPath)? imageFor;

  /// Says a media image [imageFor] had no answer for has landed.
  final Listenable? imageRepaint;

  /// Says a cell's picture has landed.
  final Listenable? picturesLanded;

  /// The sheet's saved ink; null prints none.
  final ConteInkController? inkController;

  /// The pictures of this page the brush draws into, drawn live while it
  /// is on — each in this page's own space.
  final List<ContePicture> pictures;

  /// The cels those pictures draw into.
  final ContePictureInkController? cels;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _strata(context),
        // Under the ink window: reachable exactly when the brush is off
        // (the switch doubles as the edit-mode switch, the timesheet's
        // header-edit rule).
        _cellTaps(),
        Positioned.fill(
          child: SheetTextEditLayer(
            targets: _actionTargets(),
            viewport: viewport,
            fieldKey: 'conte-action-field',
            barrierKey: 'conte-action-edit-barrier',
          ),
        ),
        // Under the pen, over the page: the pictures the brush draws into,
        // composited live while it is on.
        if (pictures.isNotEmpty)
          Positioned.fill(child: _livePictures(context)),
      ],
    );
  }

  Widget _livePictures(BuildContext context) => ContePictureLive(
    // A picture that refuses the pen shows what it prints.
    pictures: [
      for (final picture in pictures)
        if (picture.window.refusal == null) picture,
    ],
    session: session,
    surfaceOf: (picture) => cels!
        .sessionStateFor(
          picture.window.plane! as CanvasSize,
          picture.window.key,
        )
        .canvasState
        .currentSurface,
    viewport: viewport,
    effectiveRatio: EffectiveDevicePixelRatio.of(context),
    paper: ui.Size(page.metrics.pageWidth, page.metrics.pageHeight),
  );

  /// The ACTION column's in-place targets: a tap on a cell's ACTION edits it
  /// on the paper (유저 2026-09-25: 「액션은 콘티프리뷰에서 해당 칸 누르면
  /// 텍스트 편집할수있게하고, 데이터는 … 해당 콘티블록에 저장」).
  ///
  /// The words land on the exposure that opens the cell — the memo is
  /// block-owned, so it travels with every move and copy, and a linked or
  /// same-named block keeps its own (「같은 이름의 콘티블록이랑 링크된다고
  /// 해도 내용물은 독립」: a link shares the drawing, never the timeline's
  /// entries). A cell with no block has nowhere to keep them and offers no
  /// target.
  List<SheetTextTarget> _actionTargets() {
    final m = page.metrics;
    return [
      for (final cell in page.cells)
        if (cell.source.frameId != null)
          SheetTextTarget(
            keyValue: 'conte-action-edit-${cell.cutId}-${cell.cellIndex}',
            // The cell's own rows of the column — its words flow past them
            // on paper, but a tap below belongs to the cell there.
            box: Rect.fromLTRB(
              cell.actionRect.left,
              m.rowTop(cell.rowOnPage),
              cell.actionRect.right,
              m.rowTop(cell.rowOnPage + cell.source.rowSpan),
            ),
            textRect: Rect.fromLTRB(
              cell.actionRect.left + 4,
              m.rowTop(cell.rowOnPage) + 4,
              cell.actionRect.right - 4,
              m.rowTop(cell.rowOnPage + cell.source.rowSpan) - 4,
            ),
            text: cell.source.action,
            style: conteTextStyle(
              conteCellTextSize,
              color: const Color(conteInkArgb),
            ),
            onCommitted: (text) =>
                session.storyboardCursor.setStoryboardCellAction(
                  cutId: CutId(cell.cutId),
                  cellIndex: cell.cellIndex,
                  action: text,
                ),
          ),
    ];
  }

  /// Each cell's picture, a claimed press of its own.
  ///
  /// 🚨H24 (2026-09-15): the canvas surface under the sheet takes the arena
  /// on the first movement, and one tap recogniser over the whole page lost
  /// its tap to it the moment a finger wobbled. A cell fires from its claim
  /// instead — the timesheet's header boxes' law — and not for a press the
  /// canvas turned into a pan or a pinch.
  ///
  /// ⚠️REVERSED, so where two pictures overlap (a cell that encroaches with a
  /// horizontal camera move) the EARLIER cell is on top and takes the press,
  /// as the page-wide layer's first-match loop gave it.
  Positioned _cellTaps() {
    return Positioned.fill(
      child: Stack(
        key: const ValueKey<String>('conte-cell-tap-layer'),
        children: [
          for (final cell in page.cells.reversed)
            Positioned.fromRect(
              rect: _onScreen(cell.pictureRect),
              child: ControlPressClaim(
                onPressed: () => onSelectCell(cell),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: silentPress(() => onSelectCell(cell)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [documentRect] where [viewport] puts it on screen.
  Rect _onScreen(Rect documentRect) {
    final topLeft = viewport.canvasToViewport(
      CanvasPoint(x: documentRect.left, y: documentRect.top),
    );
    final bottomRight = viewport.canvasToViewport(
      CanvasPoint(x: documentRect.right, y: documentRect.bottom),
    );
    return Rect.fromPoints(
      Offset(topLeft.x, topLeft.y),
      Offset(bottomRight.x, bottomRight.y),
    );
  }

  Positioned _strata(BuildContext context) {
    final ink = inkController;
    ContePagePainter painterOf(
      SheetStratum stratum, {
      ValueListenable<TimelineDragPreview?>? dragPreview,
      Set<BrushFrameKey> liveInkKeys = const {},
      List<Listenable?> repaint = const [],
    }) => ContePagePainter(
      page: page,
      source: source,
      // The printed words follow the notation language, as the timesheet's
      // do.
      words: conteWordsIn(session.languageSettings.value.notationLanguage),
      // No outline marks the cell being worked on (유저 2026-09-25:
      // 「포커스기능 없애자 … 해당 칸 강조색 실루엣한다던가」) — the sheet
      // is paper, and paper shows no focus.
      pictureFor: pictureFor,
      imageFor: imageFor,
      viewport: viewport,
      effectiveRatio: EffectiveDevicePixelRatio.of(context),
      layers: stratum.layers,
      // Saved sheet ink shows whatever the ink mode says (R5); a live input
      // window's key stands down so translucent ink never composites twice.
      inkImageFor: ink == null
          ? null
          : (key) => ink.displayImageFor(null, key),
      liveInkKeys: liveInkKeys,
      dragPreview: dragPreview,
      repaint: repaint.isEmpty ? null : Listenable.merge(repaint),
    );
    return Positioned.fill(
      // The sheet page is the timesheet's answer applied to its sibling. A
      // `RepaintBoundary` here stopped the page being re-RECORDED, which was
      // never the cost — the raster thread still replayed the whole display
      // list every frame the app produced, for any reason, including the pen
      // moving over the canvas in another panel.
      //
      // The surrounding `Stack` already clips `Clip.hardEdge`, so each bake's
      // own clip is a no-op and the pixels do not move.
      child: SheetStrata(
        sheet: 'conte',
        painters: {
          SheetStratum.form: painterOf(SheetStratum.form),
          // F-88: the numbers this page prints follow a cut-length drag, so
          // the channel is both a VALUE the paint reads and a reason to
          // repaint. A landed logo — nothing the painter compares changes
          // for it.
          SheetStratum.content: painterOf(
            SheetStratum.content,
            dragPreview: session.dragPreview,
            repaint: [session.dragPreview, imageRepaint],
          ),
          // A landed thumbnail or cover picture, likewise.
          SheetStratum.picture: painterOf(
            SheetStratum.picture,
            repaint: [picturesLanded, imageRepaint],
          ),
          if (ink != null)
            SheetStratum.ink: painterOf(
              SheetStratum.ink,
              liveInkKeys: drawing
                  ? {for (final window in conteInkWindows(page)) window.key}
                  : const {},
              repaint: [ink],
            ),
        },
        // ⚠️A stratum stands down while it changes on every step — the ink
        // while the pen is down, the numbers while a cut-length drag
        // re-prints them (F-88): capturing costs a full paint PLUS a full
        // copy a step.
        liveNow: (stratum) => switch (stratum) {
          SheetStratum.ink => strokeHold.value,
          SheetStratum.content =>
            session.dragPreview.value is CutTrimDragPreview,
          SheetStratum.form || SheetStratum.picture => false,
        },
        liveChanges: Listenable.merge([strokeHold, session.dragPreview]),
      ),
    );
  }
}
