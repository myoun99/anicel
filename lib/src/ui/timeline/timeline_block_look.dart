import 'package:flutter/widgets.dart' show BuildContext, Color;

import '../../models/app_accents.dart' show AppColorMode;
import '../../models/layer.dart';
import '../theme/app_theme.dart' show AppColors;
import 'layer_label_controls.dart' show layerMarkColor;
import 'memo_token.dart' show ByMap;
import 'rail_eyes.dart';
import 'timeline_beat_lines.dart' show TimelineGridLaw, timelineGridGroundOver;
import 'timeline_cel_content_source.dart';
import 'timeline_cell_style.dart'
    show
        timelineDrawingHeldColor,
        timelineDrawingInkColor,
        timelineInBlockInk,
        timelineUnreadableCelPaperColor;

/// What a BLOCK shows of its row and of what it holds — a frame block and a
/// lane's key alike.
///
/// 🗣️I-129 (유저 2026-10-25): 「레이어 비지블 껐을때, 블록도 그걸
/// 표시하고싶음. 같은 비활성화색으로」 · 「그림 없는 빈 블록이면 출력의 셀
/// 탭에서 그림이 없는블록을 표시하는것처럼 회색 외곽선, 빈 바탕 … 텍스트는
/// … 외곽선이랑 동일한 회색으로」 · 「이 비지블시 비활성화색은 키던
/// 프레임블록이던 동일하게 법통일해서 … 빈 블록 법칙도 통일하고」.
enum TimelineBlockState {
  /// Its row is shown and it holds a picture.
  shown,

  /// Its row is hidden — its own eye off, or a folder above it hiding it.
  hidden,

  /// It holds no picture.
  empty,
}

/// The state a block is drawn in.
///
/// 🗣️I-129: 「꺼진 행의 빈블록은 말한 빈블록이랑 동일하게」 — an empty block
/// on a hidden row is an empty block.
TimelineBlockState timelineBlockStateOf({
  required bool shown,
  required bool drawn,
}) => !drawn
    ? TimelineBlockState.empty
    : shown
    ? TimelineBlockState.shown
    : TimelineBlockState.hidden;

/// The grey an EMPTY block's outline and words are drawn in — the export
/// Cels tab's hollow block's outline (I-129: 「출력의 셀 탭에서 그림이
/// 없는블록을 표시하는것처럼」), its words in the same grey (「너무 흰색이면 …
/// 주장이 강해지니 회색으로. 외곽선이랑 동일한 회색으로」). On the light
/// palette the paper's white would vanish into the ground, so the grey is
/// the ink's instead (the mockup's, I-143-Q3).
Color get timelineEmptyBlockGrey => switch (AppColors.mode) {
  AppColorMode.dark => timelineDrawingHeldColor.withValues(alpha: 0.28),
  AppColorMode.light => timelineDrawingInkColor.withValues(alpha: 0.5),
};

/// How wide a block's outline ([TimelineBlockLook.line]) is drawn inside
/// it — the export Cels tab's hollow block's, a box border's own width.
const double timelineBlockLineWidth = 1.0;

/// How a block in [state] is drawn, made of [paper] with words in [ink],
/// over [ground] — what stands behind it (null over the artwork).
///
/// [paper]: its fill — null for none. [line]: its outline — null for none.
/// [ink]: its words. Each is laid ONTO what is under it here, so a baker
/// paints them opaque wherever [ground] is known.
///
/// - [TimelineBlockState.hidden]: the rail's switched-off look — the alpha a
///   hidden row's label plate and name wear ([AppColors.offAlpha]) — on the
///   paper and on the words.
/// - [TimelineBlockState.empty]: the ground behind it, not see-through — 「구워야
///   성능좋고 블록느낌은 나야하니 투명말고 뒤의 바탕색으로 칠함. 그러면 투명느낌도
///   나고 2코마 3코마여도 연결된 블록 느낌 남」 — with an outline and words in
///   [timelineEmptyBlockGrey]. ↩️R26 #44 laid the paper at a low alpha
///   (「흰색에서 그냥 불투명도 낮추는 느낌」) with the block's own ink.
typedef TimelineBlockLook = ({Color? paper, Color? line, Color ink});

/// The look of a block in [state] — see [TimelineBlockLook].
TimelineBlockLook timelineBlockLook(
  TimelineBlockState state, {
  required Color paper,
  required Color ink,
  Color? ground,
}) {
  switch (state) {
    case TimelineBlockState.shown:
      return (paper: paper, line: null, ink: ink);
    case TimelineBlockState.hidden:
      final dimmed = timelineGridGroundOver(
        under: ground,
        painted: paper.withValues(alpha: paper.a * AppColors.offAlpha),
      );
      return (
        paper: dimmed,
        line: null,
        // None seen over nothing known is none at all.
        ink:
            timelineGridGroundOver(
              under: dimmed,
              painted: ink.withValues(alpha: ink.a * AppColors.offAlpha),
            ) ??
            const Color(0x00000000),
      );
    case TimelineBlockState.empty:
      final grey = timelineGridGroundOver(
        under: ground,
        painted: timelineEmptyBlockGrey,
      )!;
      return (paper: ground, line: grey, ink: grey);
  }
}

/// What a row tells of its blocks' look: its [layer], whether it is [shown]
/// (its rail's eye), what its cels hold ([content] — null reads every block
/// as drawn) and what stands behind it ([ground] — null over the artwork).
typedef TimelineBlockRow = ({
  Layer layer,
  bool shown,
  TimelineCelContentSource? content,
  Color? ground,
});

/// What of [row] its blocks' look reads, as a painter compares it between
/// two paints: which cel its layer shows where (its id and its timeline),
/// its eye, what its cels hold and its ground — or nothing, for a row that
/// hands none. By VALUE: a rebuilt row with an equal layer is the same
/// input (the edit chrome's law — `a changed face repaints the run glyphs`).
Object? timelineBlockRowFacts(TimelineBlockRow? row) => row == null
    ? null
    : (
        row.layer.id,
        ByMap(row.layer.timeline),
        row.shown,
        row.content?.hasContent,
        row.content?.cannotRead,
        row.content?.revision.value,
        row.ground,
      );

/// What a block IS, for whatever is laid on it: the [state] it is drawn
/// in, its [paper], and what stands behind it ([ground] — null over the
/// artwork). Its words are read off it ([timelineBlockLookOn]), and so are
/// its grips (`timelineBlockGripColor`).
typedef TimelineBlockFace = ({
  TimelineBlockState state,
  Color paper,
  Color? ground,
});

/// The look of a block that is [face], with words in [ink]
/// ([timelineBlockLook]).
TimelineBlockLook timelineBlockLookOn(
  TimelineBlockFace face, {
  required Color ink,
}) => timelineBlockLook(
  face.state,
  paper: face.paper,
  ink: ink,
  ground: face.ground,
);

/// What [row]'s FRAME block over [frameIndex] is, made of [paper] — the ONE
/// answer its paper, its cel name, its 코마 number and its grips are drawn
/// from.
///
/// A cel whose picture could not be read is a fault: its block is red
/// ([timelineUnreadableCelPaperColor], frame-picture-indicator-Q1 b) and
/// never taken for empty.
TimelineBlockFace timelineFrameBlockFace(
  TimelineBlockRow row,
  int frameIndex, {
  required Color paper,
}) {
  final content = row.content;
  final unreadable = content?.cannotRead(row.layer, frameIndex) ?? false;
  final drawn =
      unreadable || (content?.hasContent(row.layer, frameIndex) ?? true);
  return (
    state: timelineBlockStateOf(shown: row.shown, drawn: drawn),
    paper: _paperOf(paper, unreadable: unreadable),
    ground: row.ground,
  );
}

/// The look of [row]'s FRAME block over [frameIndex], made of [paper] with
/// words in [ink] ([timelineFrameBlockFace]).
TimelineBlockLook timelineFrameBlockLook(
  TimelineBlockRow row,
  int frameIndex, {
  required Color paper,
  required Color ink,
}) => timelineBlockLookOn(
  timelineFrameBlockFace(row, frameIndex, paper: paper),
  ink: ink,
);

/// A block's [paper] — red where what it holds cannot be read or played.
Color _paperOf(Color paper, {required bool unreadable}) =>
    unreadable ? timelineUnreadableCelPaperColor : paper;

/// The state of what [layer]'s row draws, as its rail's eye shows the row
/// ([RailEyes]): what it draws holds its value, so it is never an empty
/// block.
TimelineBlockState timelineRowStateOf(BuildContext context, Layer layer) =>
    timelineBlockStateOf(shown: RailEyes.of(context, layer).shown, drawn: true);

/// What a block [layer]'s row draws in its colour label is — its keys, the
/// marks and words laid over its blocks, the blocks a row with no cells
/// under it paints for itself (the storyboard's S and transition rows) and
/// the grips on them — in [timelineRowStateOf], onto the host's ground
/// ([TimelineGridLaw]): 🗣️I-129 「이 비지블시 비활성화색은 키던
/// 프레임블록이던 동일하게 법통일해서」. One that is [unreadable] is red, as
/// [timelineFrameBlockFace]'s is.
TimelineBlockFace timelineRowFaceOf(
  BuildContext context,
  Layer layer, {
  bool unreadable = false,
}) => (
  state: timelineRowStateOf(context, layer),
  paper: _paperOf(layerMarkColor(layer.mark), unreadable: unreadable),
  ground: TimelineGridLaw.maybeOf(context)?.ground,
);

/// The look of what [layer]'s row draws in its colour label
/// ([timelineRowFaceOf]), with words in [ink] — the block's own by default.
///
/// 🗣️I-143 (유저 2026-10-30): 「색라벨 진하게한거면 너무 진하니까 그냥
/// 기존이랑 똑같이」 — on the light palette too the label is worn as it is,
/// where it is drawn straight on the ground as well. ↩️-Q7 darkened those
/// marks (keys, the line between them, the word over it) to stand 3:1
/// there, as the accent does.
TimelineBlockLook timelineRowLookOf(
  BuildContext context,
  Layer layer, {
  Color? ink,
  bool unreadable = false,
}) => timelineBlockLookOn(
  timelineRowFaceOf(context, layer, unreadable: unreadable),
  ink: ink ?? timelineInBlockInk(),
);
