import 'dart:typed_data';
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// What a stand-in canvas with no transform of its own answers the paper's
/// cut (`cutOnThePixelGrid`): it stands on its pixels. A bare `noSuchMethod`
/// answers null, and the cut throws.
mixin CanvasOnItsPixels implements Canvas {
  @override
  Float64List getTransform() => Matrix4.identity().storage;
}
