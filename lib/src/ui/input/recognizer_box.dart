import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [RawGestureDetector] of ONE recognizer, as one render object.
///
/// 🪶WHY (card frame-panels-build-in-one-frame, 2026-10-25): a
/// [RawGestureDetector] is three elements and two render objects — its
/// state, its semantics, its listener — and a timeline row's body held two
/// of them, made again for every row a tab reopens. This box offers the
/// down to its recognizer as [RawGestureDetector] does, and says to a
/// screen reader what it says, and is nothing else.
///
/// ⛔Not a second gesture system: the recognizer and its arena are
/// Flutter's, and only the holder is light. Like [RawGestureDetector] — and
/// unlike `GestureDetector` — it hands the recognizer no device gesture
/// settings.
abstract class RecognizerBox<T extends GestureRecognizer>
    extends SingleChildRenderObjectWidget {
  const RecognizerBox({super.key, super.child});

  /// A new recognizer for a box that [offers] one.
  T makeRecognizer();

  /// Hands the recognizer this build's callbacks — a
  /// [GestureRecognizerFactoryWithHandlers]' initializer.
  void configure(T recognizer);

  /// Whether a press is offered to the recognizer at all. False holds
  /// nothing, and the box is the child's box only.
  bool get offers => true;

  /// Whether [recognizer], made for an earlier build, is still the kind
  /// this build offers. False makes a new one, as [RawGestureDetector] does
  /// when the type its factory is keyed by changes.
  bool fits(T recognizer) => true;

  /// Where the box takes a press its child does not — a
  /// [RawGestureDetector]'s `behavior`.
  HitTestBehavior get behavior => HitTestBehavior.deferToChild;

  /// The tap a screen reader's activation runs — what [RawGestureDetector]
  /// gives a tap recognizer — or null for none.
  VoidCallback? get semanticTap => null;

  @override
  RenderRecognizerBox<T> createRenderObject(BuildContext context) =>
      RenderRecognizerBox<T>()..wear(this);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRecognizerBox<T> renderObject,
  ) => renderObject.wear(this);
}

/// [RecognizerBox]'s render object: the press offered on the down, as the
/// listener of a [RawGestureDetector] offers it, and the screen reader's tap.
class RenderRecognizerBox<T extends GestureRecognizer>
    extends RenderProxyBoxWithHitTestBehavior {
  T? _recognizer;
  VoidCallback? _semanticTap;

  /// The recognizer the box holds now — null while it offers none.
  @protected
  T? get recognizer => _recognizer;

  void wear(RecognizerBox<T> box) {
    behavior = box.behavior;
    if (_recognizer case final kept? when !box.offers || !box.fits(kept)) {
      kept.dispose();
      _recognizer = null;
    }
    if (box.offers) {
      box.configure(_recognizer ??= box.makeRecognizer());
    }
    final semanticTap = box.offers ? box.semanticTap : null;
    final hadTap = _semanticTap != null;
    // ⚠️Set before it is marked: marking reads the configuration at once.
    _semanticTap = semanticTap;
    if ((semanticTap != null) != hadTap) {
      markNeedsSemanticsUpdate();
    }
  }

  /// A box with no child takes all the room it is given, as the listener of
  /// a [RawGestureDetector] with none does — the box IS the press area.
  @override
  Size computeSizeForNoChild(BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    final recognizer = _recognizer;
    if (recognizer == null) {
      return;
    }
    if (event is PointerDownEvent) {
      recognizer.addPointer(event);
    } else if (event is PointerPanZoomStartEvent) {
      recognizer.addPointerPanZoom(event);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_semanticTap case final tap?) {
      config.onTap = tap;
    }
  }

  @override
  void dispose() {
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }
}
