import 'package:flutter/material.dart';

import '../../core/point_bounds.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cel_photo.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/transform_pose.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/layer_pose_matrix.dart'
    show picturePlacement, placedCorners;
import '../canvas/canvas_press.dart' show canvasPressIsTheTools;
import '../canvas/canvas_target_pill.dart';
import '../canvas/canvas_viewport_offset.dart';
import '../canvas/row_transform_box.dart';
import '../input/hit_gate.dart';
import '../session/sheet_photo_hold.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';

/// A window of a sheet's ink as its photos' boxes see it (I-97): which ink
/// it shows and the photos on it NOW — read when asked, as its brush view
/// reads its cel — how its view lays that ink on the layer (the viewport
/// its brush view draws through and the map the layer lays the view by),
/// and whether a press at a point of the layer is its own.
typedef SheetPhotoWindow = ({
  String id,
  BrushFrameKey key,
  List<CelPhoto> Function() photosNow,
  CanvasSize canvasSize,
  CanvasViewport viewport,
  Matrix4? laid,
  bool Function(Offset position) owns,
});

/// Whether [event] is a press of the tool in hand — what takes a photo, and
/// what lets go of one past its cell (I-97-Q3 · Q4): the two doors every
/// tool's layer asks — a device a tool may take ([AppInput.toolAcceptsPointer]
/// — the sheet's drawing is on, so a finger asks the user's slot) and the
/// plain primary contact ([canvasPressIsTheTools]) — whichever tool is in
/// hand, the tail's too. A finger the view takes and a mapped button are
/// the view's and the button's.
bool sheetPhotoPress(PointerDownEvent event) =>
    AppInput.toolAcceptsPointer(event.kind) &&
    canvasPressIsTheTools(event, tailsToolInHand: (_) => true);

/// The photos on a sheet's ink layer as boxes a press takes (I-97), the one
/// held wearing the transform tool's chrome and the shared pill under it,
/// with the delete.
///
/// 🗣️I-97-Q3 (유저 2026-10-15): 「브러시 허용이면 어느 도구든 사진을 누르면
/// 집는다」 — 「사진 누르면 변형도구 상자 뜨고, 아래에 알약 공용화되있는거
/// 재사용해서 삭제버튼 추가」. I-97-Q4: 「그 칸 안은 회전, 칸 밖은 해제」 —
/// past its cell a press lets go of it and is the tool's as ever.
///
/// THE PRESS TABLE is the text tool's (`celTextPressAt`, taken by 유저 on
/// 2026-10-06), said of a photo. Nothing held: on a photo where its cell
/// shows it → take it, and the same press drags it. A photo held: its
/// corners and the middles of its edges → scale · inside → move · outside →
/// another photo if one is there, else in its cell the turn, else let go.
/// The box every box on the canvas wears answers it ([RowTransformBox],
/// [boxPressAt]'s one order) — the held one on top, so its own grabs come
/// first, the rest in the order the photos are drawn, the newest on top.
class SheetPhotoBoxes extends StatelessWidget {
  const SheetPhotoBoxes({
    super.key,
    required this.hold,
    required this.keyPrefix,
    required this.windows,
  });

  final SheetPhotoHold hold;

  /// The layer's own (`timesheet`, `conte`, `envelope`): a photo's box is
  /// `<prefix>-photo-<window id>-<photo id>`, its pill `<prefix>-photo-pill`
  /// and the pill's delete `<prefix>-photo-delete`.
  final String keyPrefix;

  /// The windows the layer shows, bottom of the stack first.
  final List<SheetPhotoWindow> windows;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hold,
    builder: (context, _) {
      final held = hold.held;
      final boxes = <Widget>[];
      Widget? inHand;
      Widget? pill;
      for (final window in windows) {
        final photos = hold.shownOn(window.key, window.photosNow());
        for (final photo in photos) {
          final at = (key: window.key, id: photo.id);
          final box = _PhotoBox(
            key: ValueKey<String>('$keyPrefix-photo-${window.id}-${photo.id}'),
            hold: hold,
            at: at,
            window: window,
            photo: photo,
            others: [
              for (final other in photos)
                if (other.id != photo.id) other,
            ],
            held: held == at,
          );
          if (held == at) {
            inHand = box;
            pill = _pill(window, photo);
          } else {
            boxes.add(box);
          }
        }
      }
      return Stack(
        children: [
          ...boxes,
          ?inHand,
          ?pill,
        ],
      );
    },
  );

  /// The shared pill under the photo held, with its one verb: the delete
  /// Delete reaches too.
  Widget _pill(SheetPhotoWindow window, CelPhoto photo) => Positioned.fill(
    key: ValueKey<String>('$keyPrefix-photo-pill-slot'),
    child: CanvasTargetPill(
      keyValue: '$keyPrefix-photo-pill',
      target: pointsBounds([
        for (final corner in sheetPhotoCorners(photo))
          _onLayer(window, corner),
      ]),
      children: [
        AppIconButton(
          keyValue: '$keyPrefix-photo-delete',
          tooltip: editorActionLabel(EditorActionIds.editDelete),
          shortcuts: const [EditorActionIds.editDelete],
          icon: Icon(
            Icons.delete_outline,
            color: AppColors.deleteGlyph(enabled: true),
          ),
          onPressed: hold.delete,
        ),
      ],
    ),
  );
}

/// The four corners of [photo] on its picture's grid, where its reference
/// stands it — the outline its box draws and a press is asked of.
List<CanvasPoint> sheetPhotoCorners(CelPhoto photo) {
  final reference = photo.reference;
  final size = reference.pictureSize;
  return placedCorners(
    picturePlacement(reference.pose, size),
    Offset.zero & Size(size.width.toDouble(), size.height.toDouble()),
  );
}

/// [pixel], a point of [window]'s ink, where the layer shows it.
Offset _onLayer(SheetPhotoWindow window, CanvasPoint pixel) {
  final onView = window.viewport.canvasToViewportOffset(pixel);
  return switch (window.laid) {
    final laid? => MatrixUtils.transformPoint(laid, onView),
    null => onView,
  };
}

/// One photo's box — the same box held or not, under the same key, so the
/// press that takes a photo goes on to drag it: the grab it began is the
/// box's, and the box is still the one it began on.
class _PhotoBox extends StatefulWidget {
  const _PhotoBox({
    super.key,
    required this.hold,
    required this.at,
    required this.window,
    required this.photo,
    required this.others,
    required this.held,
  });

  final SheetPhotoHold hold;
  final SheetPhotoAt at;
  final SheetPhotoWindow window;

  /// As it is shown — mid-grab where the grab has it.
  final CelPhoto photo;

  /// The other photos of its window, as they are shown.
  final List<CelPhoto> others;

  final bool held;

  @override
  State<_PhotoBox> createState() => _PhotoBoxState();
}

class _PhotoBoxState extends State<_PhotoBox> {
  @override
  void dispose() {
    // A sheet that stops showing the photo held lets go of it — the brush
    // switched off, the photo undone, its page off the screen. Once the
    // tree settles: a notifier told while it is torn down is told too soon.
    final hold = widget.hold;
    final at = widget.at;
    WidgetsBinding.instance.addPostFrameCallback((_) => hold.letGoOf(at));
    super.dispose();
  }

  /// Whether, held, it turns at [point] of its ink: outside its box, where
  /// its window shows its ink and no other photo of the window is — on one,
  /// that one is taken (the text tool's 「another text if one is there,
  /// else the turn」).
  bool _turnsAt(CanvasPoint point) {
    final window = widget.window;
    bool covers(CelPhoto other) =>
        CanvasSelectionShape(sheetPhotoCorners(other)).containsPoint(point);
    return window.owns(_onLayer(window, point)) && !widget.others.any(covers);
  }

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    final at = widget.at;
    final window = widget.window;
    final held = widget.held;
    final pose = widget.photo.reference.pose;
    RowBoxLanding<T> landing<T>(TransformPose Function(T value) poseOf) => (
      changed: (value) => hold.show(at, poseOf(value)),
      committed: (value) => hold.land(at, poseOf(value)),
    );
    final box = RowTransformBox(
      corners: sheetPhotoCorners(widget.photo),
      pose: pose,
      pasteboard: _sheetWall(window.canvasSize),
      viewport: window.viewport,
      presses: RowBoxPresses.taken,
      onCancelled: () => hold.dropShowing(at),
      outlined: held,
      move: landing<CanvasPoint>((center) => pose.copyWith(center: center)),
      scale: held
          ? RowBoxTwoScales(
              landing<CanvasPoint>(
                (scale) => pose.copyWith(scaleX: scale.x, scaleY: scale.y),
              ),
            )
          : null,
      turn: held
          ? landing<double>(
              (degrees) => pose.copyWith(rotationDegrees: degrees),
            )
          : null,
      stage: held ? _turnsAt : null,
      onPressedPast: held
          ? (event) {
              if (sheetPhotoPress(event)) {
                hold.letGoOf(at);
              }
            }
          : null,
    );
    // Not held, it is only where its cell shows it: a press past the cell
    // is on a photo nobody sees.
    return HitGate(
      admits: held ? _anywhere : window.owns,
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: held
            ? null
            : (event) {
                if (sheetPhotoPress(event)) {
                  hold.take(at);
                }
              },
        child: switch (window.laid) {
          final laid? => Transform(transform: laid, child: box),
          null => box,
        },
      ),
    );
  }
}

bool _anywhere(Offset position) => true;

/// A sheet's wall: a sheet sets no pasteboard size — it has no pasteboard
/// plane and no colour window of its own (F-179 · F-272) — so its photos
/// stand behind the whole one (I-109 ⓑ).
PasteboardWall _sheetWall(CanvasSize canvas) =>
    canvas.pasteboardAt(PasteboardReach.whole);
