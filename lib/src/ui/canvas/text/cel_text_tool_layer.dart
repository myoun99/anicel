import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/app_input_settings.dart';
import '../../../models/canvas_point.dart';
import '../../../models/cel_text.dart';
import '../../../services/history_manager.dart' show HistoryMark;
import '../../input/value_control_pointers.dart' show controlOwnsTap;
import '../../text/canvas_letter_faces.dart';
import '../../theme/app_theme.dart';
import '../canvas_press.dart';
import 'cel_text_chrome.dart';
import 'cel_text_field.dart';
import 'cel_text_press.dart';
import 'cel_text_stage.dart';
import 'cel_text_tool.dart';

/// THE TEXT TOOL ON THE CANVAS (R9-rest): the layer that owns every press
/// while the tool is in hand, the box and the caret it draws over the text
/// it holds ([CelTextChromePainter]), and the field the keyboard types into
/// ([CelTextField]).
///
/// 🗣️유저 2026-10-02: 「텍스트툴로 캔버스에 클릭하면 텍스트 박스가 생김.
/// 거기서 입력」 · 「텍스트박스는 텍스트툴 선택해서만 보이거나 조작가능」.
/// What each press means is the press table ([celTextPressAt]).
///
/// It is OPAQUE — the tool in hand owns the canvas, and a press it does
/// nothing with must not fall through to the stroke below (the law the
/// guide tool's layer states) — and it hides only what is under it in the
/// panel's deck: panning, zooming and the flip live in an ancestor.
class CelTextToolLayer extends StatefulWidget {
  const CelTextToolLayer({
    super.key,
    required this.tool,
    required this.stage,
    required this.cel,
    required this.onPressNeedsCel,
    required this.onDragActive,
    this.oneFingerAction,
  });

  final CelTextTool tool;
  final CelTextStage stage;

  /// The cel a press sets a text on or takes one from — null where there
  /// is none under the playhead, or its row takes no marks.
  final CelTextCel? cel;

  /// A press with no cel under it asks for one; true when one was made, and
  /// [cel] then arrives a frame later (`MainCanvasBrushHost`'s door — the
  /// one a stroke's press takes). The press goes on meanwhile: on an empty
  /// frame a click and a drag are the click and the drag they are anywhere
  /// else.
  final bool Function()? onPressNeedsCel;

  /// A press began or ended: the panel holds its pans and zooms meanwhile.
  final ValueChanged<bool> onDragActive;

  final CanvasTouchDragAction? oneFingerAction;

  @override
  State<CelTextToolLayer> createState() => _CelTextToolLayerState();
}

class _CelTextToolLayerState extends State<CelTextToolLayer> {
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'cel-text-field');

  /// The press in flight, and the scene it went down on.
  ({CelTextPress press, CelTextScene scene})? _following;

  /// A text whose press came up before the cel it had asked for arrived:
  /// it begins when the cel does ([_celChanged]).
  ({CanvasPoint anchor, double? wrapWidth})? _textAwaitingCel;

  /// Where history stood when a press made the cel its text is to be set
  /// on — until that text begins, and the two land as one step
  /// ([CelTextTool.beginText]).
  HistoryMark? _celMadeSince;

  /// The box an empty drag is tracing, on the artwork.
  Rect? _tracedBox;

  /// Whether the caret is in the lit half of its blink.
  final ValueNotifier<bool> _caretLit = ValueNotifier<bool>(true);
  Timer? _caretBlink;

  /// The texts the cel under the tool carried when this was last built —
  /// what a build is measured against, to say when they are others
  /// ([_tellOfTextsChanged]).
  List<CelText> _textsSeen = const [];

  CelTextTool get _tool => widget.tool;

  @override
  void initState() {
    super.initState();
    _tool.addListener(_toolChanged);
    CanvasLetterFaces.changes.addListener(_facesChanged);
    _syncField();
  }

  @override
  void didUpdateWidget(covariant CelTextToolLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tool, widget.tool)) {
      oldWidget.tool.removeListener(_toolChanged);
      widget.tool.addListener(_toolChanged);
    }
    if (oldWidget.cel?.key != widget.cel?.key) {
      _celChanged();
    }
  }

  /// Another cel is under the tool: what was in hand is the cel's it was
  /// set on (유저 2026-10-06: 「주인은 셀임」), and it lands there. After the
  /// frame — a landing tells listeners, and this is a build.
  void _celChanged() {
    final awaited = _textAwaitingCel;
    _textAwaitingCel = null;
    if (_following?.scene.cel != null) {
      // The press in flight was on the cel that left. ⚠️Not the press that
      // ASKED for a cel, which went down on none: that one goes on, and
      // its text begins on the cel that came ([_beginText]).
      _following = null;
      _tracedBox = null;
      widget.onDragActive(false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _tool.confirm();
      if (awaited != null && widget.cel != null) {
        // The press that made this cel came up before it was here.
        _beginText(awaited.anchor, wrapWidth: awaited.wrapWidth);
      }
    });
  }

  /// A press on nothing came up: its text begins on the cel under the tool
  /// — or, where the press made that cel and it is not here yet, when it
  /// comes ([_celChanged]).
  void _beginText(CanvasPoint anchor, {double? wrapWidth}) {
    final cel = widget.cel;
    if (cel == null) {
      _textAwaitingCel = (anchor: anchor, wrapWidth: wrapWidth);
      return;
    }
    final celMadeSince = _celMadeSince;
    _celMadeSince = null;
    _tool.beginText(
      cel,
      anchor,
      wrapWidth: wrapWidth,
      celMadeSince: celMadeSince,
    );
  }

  @override
  void dispose() {
    _tool.removeListener(_toolChanged);
    CanvasLetterFaces.changes.removeListener(_facesChanged);
    _caretBlink?.cancel();
    _caretLit.dispose();
    _fieldFocus.dispose();
    // Another tool is in hand: what this one held lands. After the frame —
    // a landing tells listeners, and this tree is being torn down.
    final tool = _tool;
    WidgetsBinding.instance.addPostFrameCallback((_) => tool.confirm());
    super.dispose();
  }

  void _toolChanged() {
    if (mounted) {
      setState(_syncField);
    }
  }

  /// The faces letters are set in are others — one arrived in the engine,
  /// one left the device: which texts the tool can reach, and where their
  /// boxes stand, is read again, here and by whoever lists them
  /// ([celTextsInReach]).
  void _facesChanged() => _tool.celTextsChanged();

  /// The keyboard is the text's while its letters are held, and the caret
  /// blinks only then.
  void _syncField() {
    if (_tool.letters == null) {
      _caretBlink?.cancel();
      _caretBlink = null;
      return;
    }
    _caretLit.value = true;
    _caretBlink ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _caretLit.value = !_caretLit.value,
    );
    if (!_fieldFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tool.letters != null) {
          _fieldFocus.requestFocus();
        }
      });
    }
  }

  // ── presses ─────────────────────────────────────────────────────────

  void _pointerDown(PointerDownEvent event) {
    // A press that landed on a control floating over the canvas is that
    // control's (`control_press_claim.dart`, 유저 2026-09-22).
    if (controlOwnsTap(event.pointer)) {
      return;
    }
    if (_following != null) {
      // A second finger is the view's: what the first was doing goes back
      // to where it began, and the pair pans or zooms.
      if (event.kind == PointerDeviceKind.touch) {
        _cancelPress();
      }
      return;
    }
    // The two doors every tool's layer asks, as the selection layer asks
    // them: a finger drives a tool only while the one-finger slot says draw
    // (TS9), and the press is the tool's own — the plain primary contact,
    // not a mapped button's and not a pen's tail (no pen's tail holds the
    // text tool).
    if (!AppInput.toolAcceptsPointer(
          event.kind,
          oneFinger: widget.oneFingerAction,
        ) ||
        !canvasPressIsTheTools(event, tailsToolInHand: (_) => false)) {
      return;
    }
    final artwork = widget.stage.artworkAt(event.localPosition);
    if (artwork == null) {
      return;
    }
    final cel = widget.cel;
    if (cel == null) {
      // Nothing to set a text on: ask for a cel, as a stroke's press does
      // (`_BrushEditCelPress`). The press then goes on as the press on
      // nothing it is, and its text begins on the cel once both are here
      // ([_beginText]). ⚠️History is read AFTER the asking — the door
      // settles a cel an earlier press left unclaimed before it makes
      // this one.
      if (!(widget.onPressNeedsCel?.call() ?? false)) {
        return;
      }
      _celMadeSince = _tool.historyMark;
    }
    final scene = CelTextScene(
      tool: _tool,
      stage: widget.stage,
      cel: cel,
      onTraced: (box) => setState(() => _tracedBox = box),
      onBegin: _beginText,
    );
    final press = celTextPressAt(scene, event, artwork);
    if (press == null) {
      return;
    }
    _following = (press: press, scene: scene);
    widget.onDragActive(true);
  }

  void _pointerMove(PointerMoveEvent event) {
    final following = _following;
    final artwork = widget.stage.artworkAt(event.localPosition);
    if (following == null ||
        following.press.pointer != event.pointer ||
        artwork == null) {
      return;
    }
    following.press.moveTo(following.scene, event.localPosition, artwork);
  }

  void _pointerUp(PointerUpEvent event) {
    final following = _following;
    if (following == null || following.press.pointer != event.pointer) {
      return;
    }
    _endPress();
    following.press.up(following.scene, event.localPosition);
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (_following?.press.pointer == event.pointer) {
      _cancelPress();
    }
  }

  void _cancelPress() {
    final following = _following;
    if (following == null) {
      return;
    }
    _endPress();
    following.press.cancel(following.scene);
  }

  void _endPress() {
    setState(() {
      _following = null;
      _tracedBox = null;
    });
    widget.onDragActive(false);
  }

  // ── the tree ────────────────────────────────────────────────────────

  /// The cel under the tool carries other texts than at the last build — a
  /// step of history, another frame: the tool tells whoever lists them
  /// ([CelTextTool.celTextsChanged]). After the frame — this is a build.
  ///
  /// ⚠️A cel's picture reaches the canvas by the panel being built again,
  /// and tells nobody else; this build is where that is seen.
  void _tellOfTextsChanged(List<CelText> texts) {
    if (listEquals(texts, _textsSeen)) {
      return;
    }
    _textsSeen = texts;
    final tool = _tool;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => tool.celTextsChanged(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _tool.session;
    final letters = _tool.letters;
    final cel = widget.cel;
    final picture = cel?.coordinator.currentSurfaceOf(cel.key);
    _tellOfTextsChanged(picture?.texts ?? const []);
    return Stack(
      children: [
        Positioned.fill(
          child: MouseRegion(
            // The caret's own cursor where a press would set letters; a
            // text held by its box is moved and sized, as a row's box is.
            cursor: session == null || letters != null
                ? SystemMouseCursors.text
                : MouseCursor.defer,
            child: Listener(
              key: const ValueKey<String>('cel-text-tool-layer'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerCancel,
              child: CustomPaint(
                painter: CelTextChromePainter(
                  tool: _tool,
                  stage: widget.stage,
                  restingBoxes: cel == null || picture == null
                      ? const []
                      : _tool.restingBoxesOn(cel.key, picture),
                  tracedBox: _tracedBox,
                  caretLit: _caretLit,
                  color: AppColors.accent,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        if (session != null && letters != null)
          Positioned(
            left: 0,
            top: 0,
            child: CelTextField(
              letters: letters,
              focusNode: _fieldFocus,
              stage: widget.stage,
              shown: session.shown.layout,
              onEscape: _tool.stopTyping,
            ),
          ),
      ],
    );
  }
}
