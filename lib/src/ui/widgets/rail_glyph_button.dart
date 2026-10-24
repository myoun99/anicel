import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/lru.dart';
import '../input/control_press_claim.dart';
import 'app_icon_button.dart';
import 'app_tooltip.dart';
import 'named.dart';
import 'press_face.dart';

/// What a rail glyph draws: a glyph of an icon font ([RailIconGlyph]), or a
/// word set in type ([RailTextGlyph] — the fx switch's `fx`).
sealed class RailGlyph {
  const RailGlyph();
}

/// An [Icon]'s glyph — drawn as [Icon] draws it, in the button's ink unless
/// [color] says otherwise (the eye's off colour, a soloed speaker).
final class RailIconGlyph extends RailGlyph {
  const RailIconGlyph(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is RailIconGlyph && other.icon == icon && other.color == color;

  @override
  int get hashCode => Object.hash(icon, color);
}

/// A word set in [style] over the ambient text style, as a [Text] with no
/// text scaling sets it — an icon does not follow the OS text size.
final class RailTextGlyph extends RailGlyph {
  const RailTextGlyph(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) =>
      other is RailTextGlyph && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);
}

/// THE RAIL'S BUTTON — what a rail's toggles and doors are made of (the eye,
/// the speaker, the fx switch, the sheet toggle, the twirls), drawn by ONE
/// render object each.
///
/// 🚨WHY (I-57 ①, 유저 10-09 「가볍기만하면 레일전용버튼해도 상관없어 …
/// 통일할거 알아서 통일하고」): a cut switch mounts every visible rail row
/// anew — their keys are the layers', and the layers are another cut's — and
/// one row was ~400 elements, most of them its buttons: each an
/// [AppIconButton] of ~35 (the claim, a stateful face, a semantics node, a
/// tooltip of nine, focus, actions, a mouse region, a listener, three boxes,
/// two builders and an [Icon] of six). Measured in a profile build on the
/// user's project: the frame after a cut switch spent ~45% of its time on
/// the rail. This is the claim and ONE leaf: the leaf paints the box, the
/// state layer and the glyph (laid out once for the whole app), says the
/// semantics, shows the cursor, and summons the one tooltip window the
/// rail's buttons share ([SummonedTooltip]).
///
/// ⛔THE PRESS IS UNTOUCHED: [ControlPressClaim] fires it, as it fires an
/// [AppIconButton]'s, and [PressFireScope] says when — the leaf only enters
/// the do-nothing tap every light face enters ([PressFace]), so an
/// ancestor's tap still loses to a press on a button.
///
/// ⛔ONE INK, ONE SHAPE: [IconButtonInk] and [appIconButtonShape] are the
/// [AppIconButton]'s own, so the rail looks exactly as it did.
///
/// ⚠️What a rail button no longer has is KEYBOARD FOCUS — the Tab key's
/// stop and the focus ring. Its Enter/Space were already silent by 유저's
/// call (2026-09-10: 「탭은 다른 숏컷 쓸수도있어서 굳이 필요없을거같고」), so
/// focus led nowhere. A screen reader still finds and presses it.
/// ⚠️That premise fell on 2026-10-23 (board `F-450-Q1`: every other icon
/// button now answers Enter/Space); whether the rail takes its focus back,
/// at the cost the leaf was built to shed, is board `F-450-Q2`.
class RailGlyphButton extends StatelessWidget {
  const RailGlyphButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
    required this.size,
    this.isSelected = false,
    this.danger = false,
    this.semanticLabel,
  });

  /// What a finder calls the [RailGlyphFace], the box the user sees and
  /// presses — the tests' handle, a [Named] and never a key: a rail row
  /// shows one layer and then another in the same elements (I-57, 10-13),
  /// and a key spelled from the layer remade every button of every row on
  /// every cut switch.
  final String name;

  /// Empty is no tooltip at all, as an [AppTooltip]'s empty message is.
  final String tooltip;
  final RailGlyph glyph;
  final VoidCallback? onPressed;

  /// What a screen reader calls a button whose glyph says what it is and
  /// that shows no tooltip — the type button's kind.
  final String? semanticLabel;

  /// The box: the rail's slot as an [AppIconButtonBox] the parent promised,
  /// or a token where the button stands outside a rail.
  final AppIconButtonMetrics size;

  /// The ON state — accent ink only ([AppIconButton.isSelected]).
  final bool isSelected;

  /// Something is wrong with what this button is about ([AppIconButton.
  /// danger]).
  final bool danger;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onPressed,
    child: Named(
      name,
      child: RailGlyphFace(
        tooltip: tooltip,
        glyph: glyph,
        // 🚨A screen reader is not a pointer: its activation arrives as
        // SemanticsAction.tap, which the claim never hears, so the node
        // gets the REAL callback — as an [AppIconButton]'s does.
        onSemanticTap: onPressed,
        semanticLabel: semanticLabel,
        isSelected: isSelected,
        danger: danger,
        size: size,
      ),
    ),
  );
}

/// The part of a [RailGlyphButton] you can see and hear, as one render
/// object. Public because it is what [RailGlyphButton.name] names.
class RailGlyphFace extends LeafRenderObjectWidget {
  const RailGlyphFace({
    super.key,
    required this.tooltip,
    required this.glyph,
    required this.onSemanticTap,
    required this.isSelected,
    required this.danger,
    required this.size,
    this.semanticLabel,
  });

  final String tooltip;
  final RailGlyph glyph;

  /// What a screen reader's activation calls; null is a dead button.
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final bool isSelected;
  final bool danger;
  final AppIconButtonMetrics size;

  bool get enabled => onSemanticTap != null;

  @override
  RenderRailGlyphFace createRenderObject(BuildContext context) =>
      RenderRailGlyphFace(spec: _specIn(context), tooltipContext: context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRailGlyphFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context;
  }

  RailGlyphSpec _specIn(BuildContext context) {
    final ambient = IconTheme.of(context);
    final box = appIconButtonBoxOnGrid(context, size);
    return RailGlyphSpec(
      tooltip: tooltip,
      glyph: glyph,
      onSemanticTap: onSemanticTap,
      semanticLabel: semanticLabel,
      isSelected: isSelected,
      ink: IconButtonInk.of(context, isSelected: isSelected, danger: danger),
      shape: appIconButtonShape(
        size.height,
        outlined: false,
        danger: danger,
        isSelected: isSelected,
      ),
      minWidth: box.minWidth,
      maxWidth: box.maxWidth,
      height: box.height,
      // The face's own `IconTheme.merge(color: ink, size: iconSize)` over
      // the ambient one — its fill, weight, grade, optical size, opacity and
      // shadows stay the ambient's.
      iconTheme: ambient.copyWith(size: size.iconSize),
      textStyle: DefaultTextStyle.of(context).style,
      textDirection: Directionality.of(context),
      triggerMode:
          TooltipTheme.of(context).triggerMode ?? TooltipTriggerMode.longPress,
    );
  }
}

/// Everything a [RenderRailGlyphFace] draws and says, resolved from the
/// context by its widget. Equal while nothing it shows would change.
@immutable
final class RailGlyphSpec implements FaceSpec<RailGlyphSpec> {
  const RailGlyphSpec({
    required this.tooltip,
    required this.glyph,
    required this.onSemanticTap,
    required this.semanticLabel,
    required this.isSelected,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconTheme,
    required this.textStyle,
    required this.textDirection,
    required this.triggerMode,
  });

  final String tooltip;
  final RailGlyph glyph;
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final bool isSelected;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;
  final double height;
  final IconThemeData iconTheme;
  final TextStyle textStyle;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  bool get enabled => onSemanticTap != null;

  @override
  bool laysOutAs(RailGlyphSpec other) =>
      other.glyph == glyph &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.height == height &&
      other.iconTheme == iconTheme &&
      other.textStyle == textStyle &&
      other.textDirection == textDirection;

  /// A host that hands down a fresh closure every build changes what a
  /// screen reader's activation calls, never a pixel.
  @override
  bool paintsAs(RailGlyphSpec other) =>
      laysOutAs(other) &&
      other.enabled == enabled &&
      other.isSelected == isSelected &&
      other.ink == ink &&
      other.shape == shape;

  @override
  bool operator ==(Object other) =>
      other is RailGlyphSpec &&
      paintsAs(other) &&
      other.tooltip == tooltip &&
      other.onSemanticTap == onSemanticTap &&
      other.semanticLabel == semanticLabel &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    glyph,
    onSemanticTap,
    semanticLabel,
    isSelected,
    ink,
    shape,
    minWidth,
    maxWidth,
    height,
    iconTheme,
    textStyle,
    textDirection,
    triggerMode,
  );
}

/// The rail button's face: its box, its state layer and its glyph, as one
/// render object, on the press every light face is ([PressFace]).
class RenderRailGlyphFace extends RenderBox with PressFace {
  RenderRailGlyphFace({
    required RailGlyphSpec spec,
    required BuildContext tooltipContext,
  }) : _spec = spec {
    this.tooltipContext = tooltipContext;
  }

  RailGlyphSpec _spec;
  RailGlyphSpec get spec => _spec;
  set spec(RailGlyphSpec value) {
    final old = _spec;
    _spec = value;
    respec(old, value);
  }

  @override
  bool get pressEnabled => _spec.enabled;

  @override
  bool get pressSelected => _spec.isSelected;

  @override
  String? get pressSemanticLabel => _spec.semanticLabel;

  @override
  VoidCallback? get pressSemanticTap => _spec.onSemanticTap;

  @override
  TextDirection get pressTextDirection => _spec.textDirection;

  @override
  TooltipTriggerMode get pressTriggerMode => _spec.triggerMode;

  @override
  String get tooltipMessage => _spec.tooltip;

  @override
  void pressLookChanged() => markNeedsPaint();

  /// The colour the glyph is painted in right now — for tests.
  @visibleForTesting
  Color? get debugGlyphInk =>
      _glyphPainter(_spec.ink.foreground(pressStates)).text?.style?.color;

  // ── layout ──────────────────────────────────────────────────────────

  /// Where the glyph is painted inside the face — [Icon]'s square of its
  /// size centred and the glyph centred in it, or the word's paragraph
  /// centred — summed as the widgets summed their offsets.
  Offset _glyphOffset = Offset.zero;

  @override
  void performLayout() {
    final painter = _glyphPainter(_spec.ink.foreground(pressStates));
    var inGlyph = Offset.zero;
    final box = layOutIconButtonBox(
      constraints,
      BoxConstraints(
        minWidth: _spec.minWidth,
        maxWidth: _spec.maxWidth,
        minHeight: _spec.height,
        maxHeight: _spec.height,
      ),
      (loose) {
        switch (_spec.glyph) {
          case RailIconGlyph():
            final square = _spec.iconTheme.size!;
            final glyph = loose.constrain(Size(square, square));
            // [Icon]'s `Center` inside its square.
            inGlyph = Alignment.center.alongOffset(
              glyph - painter.size as Offset,
            );
            return glyph;
          case RailTextGlyph():
            return loose.constrain(painter.size);
        }
      },
    );
    size = box.size;
    _glyphOffset = box.glyphOffset + inGlyph;
  }

  @override
  bool get sizedByParent => false;

  // ── paint ──────────────────────────────────────────────────────────

  late final IconButtonLayer _layer = IconButtonLayer(markNeedsPaint);

  @override
  void paint(PaintingContext context, Offset offset) {
    final states = pressStates;
    _layer.paint(
      context.canvas,
      offset & size,
      ShapeDecoration(shape: _spec.shape, color: _spec.ink.overlay(states)),
      _spec.textDirection,
    );
    _glyphPainter(_spec.ink.foreground(states)).paint(
      context.canvas,
      offset + _glyphOffset,
    );
  }

  /// The glyph laid out in [ink] — or in its own colour where it has one —
  /// from the app's one cache: a glyph is laid out once however many rows
  /// show it.
  TextPainter _glyphPainter(Color ink) => switch (_spec.glyph) {
    RailIconGlyph(:final icon, :final color) => _GlyphCache.icon(
      icon,
      color: color ?? ink,
      theme: _spec.iconTheme,
      textDirection: _spec.textDirection,
    ),
    RailTextGlyph(:final text, :final style) => _GlyphCache.text(
      text,
      // `DefaultTextStyle.merge(color: ink)` under the word's own style.
      style: _spec.textStyle.merge(TextStyle(color: ink)).merge(style),
      textDirection: _spec.textDirection,
      maxWidth: _spec.maxWidth,
    ),
  };

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}

/// A rail PLATE that is pressed — the mark's and the take's ([RailPlateFace]).
/// What it shows is its child's own: the plate paints itself, opaque, so no
/// state layer would show over it — and the [InkWell] the plate used to wear
/// drew its ink UNDER it, unseen. Everything else is the press every light
/// face is ([PressFace]).
///
/// A CLEAR plate — an edge and a word, the blend chip's — let that ink show:
/// the hover, the one ink the app keeps (its theme turns the splash and the
/// held fill off, F-132 · F-138). Such a face paints it, UNDER the plate as
/// the [InkWell] drew it ([RailPlateSpec.hoverShape]).
class RenderRailPlateFace extends RenderProxyBox with PressFace {
  RenderRailPlateFace({
    required RailPlateSpec spec,
    required BuildContext tooltipContext,
  }) : _spec = spec {
    this.tooltipContext = tooltipContext;
  }

  RailPlateSpec _spec;
  RailPlateSpec get spec => _spec;
  set spec(RailPlateSpec value) {
    final old = _spec;
    _spec = value;
    respec(old, value);
  }

  @override
  void pressLookChanged() {
    if (_spec.hoverShape != null) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_spec.hoverShape case final shape? when hovered && _spec.enabled) {
      context.canvas.drawPath(
        shape.getOuterPath(offset & size, textDirection: _spec.textDirection),
        Paint()..color = _spec.hoverInk,
      );
    }
    super.paint(context, offset);
  }

  @override
  bool get pressEnabled => _spec.enabled;

  @override
  bool get pressSelected => false;

  @override
  String? get pressSemanticLabel => _spec.semanticLabel;

  @override
  VoidCallback? get pressSemanticTap => _spec.onSemanticTap;

  @override
  TextDirection get pressTextDirection => _spec.textDirection;

  @override
  TooltipTriggerMode get pressTriggerMode => _spec.triggerMode;

  @override
  String get tooltipMessage => _spec.tooltip;
}

/// Everything a [RenderRailPlateFace] says, resolved from the context by
/// its widget.
@immutable
final class RailPlateSpec implements FaceSpec<RailPlateSpec> {
  const RailPlateSpec({
    required this.tooltip,
    required this.onSemanticTap,
    required this.semanticLabel,
    required this.textDirection,
    required this.triggerMode,
    required this.hoverShape,
    required this.hoverInk,
  });

  final String tooltip;
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  /// A clear plate's hover, in this shape — null for an opaque plate, whose
  /// ink nobody saw ([RailPlateFace.hoverShape]).
  final ShapeBorder? hoverShape;

  /// The hover's colour: the theme's, as an [InkWell] with none of its own
  /// takes it.
  final Color hoverInk;

  bool get enabled => onSemanticTap != null;

  /// The plate lays itself out — the face is its size.
  @override
  bool laysOutAs(RailPlateSpec other) => true;

  /// Whether [other] paints the same hover.
  @override
  bool paintsAs(RailPlateSpec other) =>
      other.hoverShape == hoverShape &&
      other.hoverInk == hoverInk &&
      other.enabled == enabled &&
      other.textDirection == textDirection;

  @override
  bool operator ==(Object other) =>
      other is RailPlateSpec &&
      paintsAs(other) &&
      other.tooltip == tooltip &&
      other.onSemanticTap == onSemanticTap &&
      other.semanticLabel == semanticLabel &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    onSemanticTap,
    semanticLabel,
    textDirection,
    triggerMode,
    hoverShape,
    hoverInk,
  );
}

/// The face of a pressed rail plate: [child] is the plate, and this one
/// render object around it is the button — cursor, tooltip, semantics and
/// the arena's tap. The press itself is its [ControlPressClaim]'s, as a
/// [RailGlyphButton]'s is ([RailFlyoutTrigger]).
class RailPlateFace extends SingleChildRenderObjectWidget {
  const RailPlateFace({
    super.key,
    required this.tooltip,
    required this.onSemanticTap,
    this.semanticLabel,
    this.hoverShape,
    required super.child,
  });

  final String tooltip;

  /// What a screen reader's activation calls; null is a dead plate.
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;

  /// A CLEAR plate's hover, painted under it in this shape — the ink an
  /// [InkWell] drew where the plate let it show ([RenderRailPlateFace]).
  /// Null for an opaque plate.
  final ShapeBorder? hoverShape;

  @override
  RenderRailPlateFace createRenderObject(BuildContext context) =>
      RenderRailPlateFace(spec: _specIn(context), tooltipContext: context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRailPlateFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context;
  }

  RailPlateSpec _specIn(BuildContext context) => RailPlateSpec(
    tooltip: tooltip,
    onSemanticTap: onSemanticTap,
    semanticLabel: semanticLabel,
    textDirection: Directionality.of(context),
    triggerMode:
        TooltipTheme.of(context).triggerMode ?? TooltipTriggerMode.longPress,
    hoverShape: hoverShape,
    hoverInk: Theme.of(context).hoverColor,
  );
}

/// THE RAIL'S PLATE BUTTON — [child] painted as it paints itself, and the
/// claim and ONE face ([RailPlateFace]) around it: what a pressed plate of
/// a rail is, whatever the press does. A list's door is this with the list
/// as its press ([RailFlyoutTrigger]); the legend's headings are this, on
/// the legend's plate (`TimelineLayerControlsHeader`). Null [onPressed] is a
/// dead plate that still shows its tooltip, as a dead [RailGlyphButton]
/// does.
class RailPlateButton extends StatelessWidget {
  const RailPlateButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
    this.hoverShape,
  });

  /// What a finder calls the [RailPlateFace] — a [Named], as a
  /// [RailGlyphButton.name] is and for its reason.
  final String name;
  final String tooltip;
  final VoidCallback? onPressed;

  /// The plate.
  final Widget child;

  /// What a screen reader calls it.
  final String? semanticLabel;

  /// [RailPlateFace.hoverShape].
  final ShapeBorder? hoverShape;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onPressed,
    child: Named(
      name,
      child: RailPlateFace(
        tooltip: tooltip,
        // The REAL callback, for a screen reader's activation — the claim
        // never hears it ([RailGlyphButton]).
        onSemanticTap: onPressed,
        semanticLabel: semanticLabel,
        hoverShape: hoverShape,
        child: child,
      ),
    ),
  );
}

/// The glyphs the rail buttons draw, each laid out ONCE for the app — six
/// rows wear one eye, and a cut switch lays out none of them again.
abstract final class _GlyphCache {
  /// Enough for every glyph × ink × size the rails show, with room; the
  /// least recently drawn goes first past it.
  static const int _capacity = 256;
  static final Lru<Object, TextPainter> _painters = Lru(
    limit: () => _capacity,
    letGo: (_, painter) => painter.dispose(),
  );

  static TextPainter icon(
    IconData icon, {
    required Color color,
    required IconThemeData theme,
    required TextDirection textDirection,
  }) {
    final size = theme.size!;
    // [Icon]'s opacity: the theme's, on top of the colour's own.
    final opacity = theme.opacity ?? 1.0;
    final ink = opacity == 1.0
        ? color
        : color.withValues(alpha: color.a * opacity);
    final key = (
      icon,
      ink,
      size,
      theme.fill,
      theme.weight,
      theme.grade,
      theme.opticalSize,
      theme.shadows,
      textDirection,
    );
    return _painters.resolve(
      key,
      () => TextPainter(
        textDirection: textDirection,
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          // [Icon]'s own style, field for field.
          style: TextStyle(
            fontVariations: <FontVariation>[
              if (theme.fill != null) FontVariation('FILL', theme.fill!),
              if (theme.weight != null) FontVariation('wght', theme.weight!),
              if (theme.grade != null) FontVariation('GRAD', theme.grade!),
              if (theme.opticalSize != null)
                FontVariation('opsz', theme.opticalSize!),
            ],
            inherit: false,
            color: ink,
            fontSize: size,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontFamilyFallback: icon.fontFamilyFallback,
            shadows: theme.shadows,
            height: 1.0,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      )..layout(),
    );
  }

  static TextPainter text(
    String text, {
    required TextStyle style,
    required TextDirection textDirection,
    required double maxWidth,
  }) => _painters.resolve(
    (text, style, textDirection, maxWidth),
    () => TextPainter(
      textDirection: textDirection,
      text: TextSpan(text: text, style: style),
    )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity),
  );
}

/// The rail glyphs' painter for [text] in [style] — the cache a pin asks to
/// see keep and let go ([_GlyphCache]).
@visibleForTesting
TextPainter debugRailTextGlyph(String text, TextStyle style) =>
    _GlyphCache.text(
      text,
      style: style,
      textDirection: TextDirection.ltr,
      maxWidth: double.infinity,
    );
