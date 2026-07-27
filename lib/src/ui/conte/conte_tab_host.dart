import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../../models/layer_kind.dart';
import '../editor_session_manager.dart';
import '../storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver;
import '../text/app_strings.dart';
import 'conte_page_painter.dart';
import 'conte_sheet_builder.dart';

/// The conte PANEL: the sheet as paper, not as a table.
///
/// It draws the very renderer the export does ([ContePagePainter]), so what
/// is on screen is the page — there is no preview approximation to drift
/// from the output. Clicking a cell selects that cut, its storyboard row
/// and the cell's frame, which is how the other panels follow along.
class ConteTabHost extends StatefulWidget {
  const ConteTabHost({
    super.key,
    required this.session,
    required this.thumbnailFor,
  });

  final EditorSessionManager session;

  /// The panels' picture resolver — the SAME store the storyboard strip
  /// draws from, so a cell and its strip panel are one render.
  final StoryboardThumbnailResolver? thumbnailFor;

  @override
  State<ConteTabHost> createState() => _ConteTabHostState();
}

class _ConteTabHostState extends State<ConteTabHost> {
  EditorSessionManager get _session => widget.session;

  int _page = 0;
  final TextEditingController _action = TextEditingController();

  /// The cell under edit, as `(cutId, cellIndex)`.
  (String, int)? _selected;

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  ConteSheetSource _source() =>
      buildConteSheetSource(_session.repository.requireProject());

  /// A cell press: the cut, its storyboard row and the frame — the design's
  /// "칸 클릭 = selectCut + selectLayer + selectFrameIndex", which is what
  /// makes the canvas and the timeline follow the sheet.
  void _selectCell(ContePlacedCell cell) {
    final cutId = CutId(cell.cutId);
    if (_session.activeCutOrNull?.id != cutId) {
      _session.selectCut(cutId);
    }
    for (final layer in _session.layers) {
      if (layer.kind == LayerKind.storyboard) {
        _session.selectLayer(layer.id);
        break;
      }
    }
    _session.selectFrameIndex(cell.source.startFrame);
    setState(() {
      _selected = (cell.cutId, cell.cellIndex);
      _action.text = cell.source.action;
    });
  }

  /// ACTION text lands on the exposure that opens the cell — the memo is
  /// block-owned, so it travels with every move and copy for free.
  void _commitAction() {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    _session.setStoryboardCellAction(
      cutId: CutId(selected.$1),
      cellIndex: selected.$2,
      action: _action.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source();
    final pages = layoutConteSheet(
      source,
      metrics: ConteSheetMetrics(cameraAspect: _session.cameraFrameAspect),
    );
    final page = pages.isEmpty ? null : pages[_page.clamp(0, pages.length - 1)];

    return ColoredBox(
      key: const ValueKey<String>('conte-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageBar(pages.length),
          Expanded(
            child: page == null
                ? const SizedBox.shrink()
                : _paper(context, page, source),
          ),
          if (_selected != null) _actionEditor(context),
        ],
      ),
    );
  }

  Widget _pageBar(int pageCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey<String>('conte-previous-page-button'),
            tooltip: AppText.strings.cnPreviousPage,
            onPressed: _page <= 0 ? null : () => setState(() => _page -= 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${pageCount == 0 ? 0 : _page + 1} / $pageCount',
            key: const ValueKey<String>('conte-page-readout'),
          ),
          IconButton(
            key: const ValueKey<String>('conte-next-page-button'),
            tooltip: AppText.strings.cnNextPage,
            onPressed: _page >= pageCount - 1
                ? null
                : () => setState(() => _page += 1),
            icon: const Icon(Icons.chevron_right, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _paper(
    BuildContext context,
    ContePageLayout page,
    ConteSheetSource source,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = page.metrics;
        final scale = (constraints.maxHeight / metrics.pageHeight).clamp(
          0.0,
          constraints.maxWidth / metrics.pageWidth,
        );
        final size = Size(
          metrics.pageWidth * scale,
          metrics.pageHeight * scale,
        );
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (scale <= 0) {
                return;
              }
              final point = details.localPosition / scale;
              for (final cell in page.cells) {
                if (cell.pictureRect.contains(point)) {
                  _selectCell(cell);
                  return;
                }
              }
            },
            child: CustomPaint(
              key: const ValueKey<String>('conte-page'),
              size: size,
              painter: ContePagePainter(
                page: page,
                source: source,
                selectedCell: _selected,
                pictureFor: (cutId, frame) => _pictureFor(cutId, frame),
              ),
            ),
          ),
        );
      },
    );
  }

  ui.Image? _pictureFor(String cutId, int frame) {
    final resolver = widget.thumbnailFor;
    if (resolver == null) {
      return null;
    }
    for (final track in _session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id.value == cutId) {
          return resolver(cut, frame);
        }
      }
    }
    return null;
  }

  Widget _actionEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: TextField(
        key: const ValueKey<String>('conte-action-field'),
        controller: _action,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: AppText.strings.cnActionColumn,
        ),
        onSubmitted: (_) => _commitAction(),
        onTapOutside: (_) => _commitAction(),
      ),
    );
  }
}
