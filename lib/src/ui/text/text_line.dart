import 'package:flutter/widgets.dart';

/// What a `Text` of [style] would be set in where [context] shows it — over
/// the ambient [DefaultTextStyle], at the context's text scale, in its
/// direction and locale. A line a box sets itself (a label plate's word laid
/// across) is set in this, so it reads as a `Text` would.
///
/// ↩️It was the frame counter's line's (`TickText`, I-57 10-14), a line that
/// heard its tick and painted itself alone, until F-463 took the counter
/// off.
TextLineType textLineTypeIn(BuildContext context, TextStyle style) {
  final ambient = DefaultTextStyle.of(context);
  var merged = ambient.style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    merged = merged.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  return (
    style: merged,
    scaler: MediaQuery.textScalerOf(context),
    direction: Directionality.of(context),
    locale: Localizations.maybeLocaleOf(context),
    heightBehavior:
        ambient.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
  );
}

/// Everything a line is set in ([textLineTypeIn]) — equal while nothing
/// that sets it would change.
typedef TextLineType = ({
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
  Locale? locale,
  TextHeightBehavior? heightBehavior,
});

/// [text] set as one line in [type], not yet laid out.
TextPainter textLineIn(String text, TextLineType type) => TextPainter(
  text: TextSpan(text: text, style: type.style),
  textScaler: type.scaler,
  textDirection: type.direction,
  locale: type.locale,
  textHeightBehavior: type.heightBehavior,
);
