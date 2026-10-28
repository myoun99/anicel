import 'dart:ui' as ui;

import 'package:anicel/src/ui/canvas/image_pieces.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

/// The one image of a picture inside the side a test's engine stands at
/// (`flutter_test_config.dart`) — what every picture a test makes is, but
/// the pins that ask a picture past the side for its pieces
/// (`a_picture_past_the_side_is_held_in_pieces_test.dart`).
extension OnePiece on List<ImagePiece> {
  ui.Image get image => single.image;
}

/// [OnePiece] of a compose.
extension OnePieceComposed on PositionedSurfaceImage {
  ui.Image get image => pieces.image;
}
