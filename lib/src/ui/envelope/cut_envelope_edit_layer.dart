import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/envelope/cut_envelope_form.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../models/layer_mark.dart';
import '../sheet/sheet_text_edit_layer.dart';
import '../text/app_face.dart';
import 'cut_envelope_painter.dart';

/// Tap-to-edit on the envelope: each box that prints a stage's worker
/// (`{staff.<label>.name}`) — the envelope's targets for
/// [SheetTextEditLayer], the one in-place editor the sheets share.
///
/// 🗣️I-127-Q1 (유저 2026-10-25): 「봉투 용지 패널에도 넣고, 셀 출력은 그대로
/// 부른다」 — the boxes are typed into as the timesheet's name box is, and
/// what is typed is that stage's worker on the cut, the name 컷 설정 shows.
/// ↩️The envelope printed its staff and took only ink.
class CutEnvelopeEditLayer extends StatelessWidget {
  const CutEnvelopeEditLayer({
    super.key,
    required this.layout,
    required this.source,
    required this.viewport,
    required this.onStaffNamed,
  });

  /// The form ruled onto the paper shown.
  final CutEnvelopeLayout layout;

  /// What the envelope prints of its cut.
  final CutEnvelopeSource source;

  /// The live panel viewport (the same transform the painter applies).
  final CanvasViewport viewport;

  /// Where a name typed into a stage's box lands.
  final void Function(LayerMark stage, String name) onStaffNamed;

  @override
  Widget build(BuildContext context) {
    // The face the envelope prints in — the painter reads the same ambient
    // style.
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    return SheetTextEditLayer(
      viewport: viewport,
      fieldKey: 'cut-envelope-edit-field',
      barrierKey: 'cut-envelope-edit-barrier',
      targets: [
        for (final placed in layout.placedBoxes)
          if (placed.box.contentKind == EnvelopeContentKind.text)
            if (envelopeStaffMarkOf(placed.box.binding!) case final stage?)
              ?_target(placed, stage, face),
      ],
    );
  }

  /// [placed]'s words as the painter prints them, typed into [stage]'s
  /// worker — or null where no line can be set: on a paper so small its
  /// words come out a fraction of a pixel tall, a line measures NaN
  /// (measured 2026-10-27 on an 8px cut's paper, 0.12px words), and a
  /// field laid there fails to build.
  SheetTextTarget? _target(
    PlacedEnvelopeBox placed,
    LayerMark stage,
    TextStyle face,
  ) {
    final text = resolveEnvelopeText(placed.box.binding!, source) ?? '';
    final style = envelopeWordsStyle(
      face,
      layout,
      size: placed.box.contentSize,
      color: envelopeValueInk,
    );
    final line = envelopeLine(text, style, layout, placed);
    final align = placed.box.contentAlign;
    final textRect = envelopeLineSlot(
      layout,
      placed,
      line.height,
      align: align,
    );
    line.dispose();
    if (!textRect.isFinite) {
      return null;
    }
    return SheetTextTarget(
      keyValue: 'cut-envelope-${placed.box.id}-edit',
      box: Rect.fromLTWH(placed.x, placed.y, placed.width, placed.height),
      textRect: textRect,
      text: text,
      style: style,
      form: switch (align) {
        EnvelopeAlign.left => SheetTextForm.leftLine,
        EnvelopeAlign.center => SheetTextForm.centredLine,
        EnvelopeAlign.right => SheetTextForm.rightLine,
      },
      onCommitted: (name) => onStaffNamed(stage, name),
    );
  }
}
