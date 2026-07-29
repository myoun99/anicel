import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show FontWeight, TextStyle;
import 'package:flutter/services.dart' show FontLoader, rootBundle;

/// The conte's embedded faces (OFL, THIRD_PARTY.md): M PLUS 1p carries
/// Latin + kana + kanji, IBM Plex Sans KR the Hangul fallback.
///
/// ONE pair of sources serves both surfaces: the PDF embeds these bytes,
/// and [ensureConteFontsLoaded] registers the same bytes into the Flutter
/// engine so the PANEL sets its type in them too. Shared faces are what
/// make the shared wrap (`conteWrappedLines`) one truth — the panel's
/// break positions ARE the PDF's, on every OS.
const String conteJpFontFamily = 'M PLUS 1p';
const String conteKrFontFamily = 'IBM Plex Sans KR';

const String conteJpRegularAsset = 'assets/fonts/MPLUS1p-Regular.ttf';
const String conteJpBoldAsset = 'assets/fonts/MPLUS1p-Bold.ttf';
const String conteKrRegularAsset = 'assets/fonts/IBMPlexSansKR-Regular.ttf';

/// The conte's one text style: the sheet's ink, the shared faces, the
/// 1.25 line the PDF's `_lineHeight` mirrors. The panel colours it; the
/// PDF only measures with it, so [color] stays optional.
TextStyle conteTextStyle(double size, {bool bold = false, Color? color}) =>
    TextStyle(
      color: color,
      fontSize: size,
      height: 1.25,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontFamily: conteJpFontFamily,
      fontFamilyFallback: const [conteKrFontFamily],
    );

Future<void>? _conteFontsLoad;

/// Idempotent engine registration of the embedded faces. The workspace
/// kicks it at startup so the conte opens ready; anything that lays conte
/// text out awaits it too (cheap once loaded), so a cold path cannot
/// measure in a fallback face and quietly wrap differently.
Future<void> ensureConteFontsLoaded() {
  return _conteFontsLoad ??= () async {
    final jp = FontLoader(conteJpFontFamily)
      ..addFont(rootBundle.load(conteJpRegularAsset))
      ..addFont(rootBundle.load(conteJpBoldAsset));
    final kr = FontLoader(conteKrFontFamily)
      ..addFont(rootBundle.load(conteKrRegularAsset));
    await Future.wait([jp.load(), kr.load()]);
  }();
}
