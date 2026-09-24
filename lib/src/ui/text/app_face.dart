import 'package:flutter/painting.dart';

/// The app's FACE out of the ambient text style — its family and its
/// fallback, and nothing else of it.
///
/// 🚨「앱은 한 글꼴」(유저 2026-08-28). A `TextStyle` built from scratch names
/// no face, and a painter that lays one out draws in the OS's: the koma, the
/// rulers, the run glyphs, the guides' names and the flip window's names
/// did, beside names in the app's. The theme picks the face per language
/// (`AppTypography`), and a painter reaches it the way a `Text` does — the
/// ambient `DefaultTextStyle`.
///
/// ⚠️The face ALONE: the ambient line height grew the SE dialogue's glyph
/// boxes past the cells they are spread into, and a painter's size, weight
/// and ink are its own. A block word that wants the ambient look whole goes
/// through `timelineBlockWordStyle` instead.
TextStyle appFaceOf(TextStyle ambient) => TextStyle(
  fontFamily: ambient.fontFamily,
  fontFamilyFallback: ambient.fontFamilyFallback,
);
