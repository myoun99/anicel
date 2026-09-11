import 'package:flutter/material.dart';

import '../../models/media_asset.dart';

/// The one picture of a file's KIND — on the pool row and on the chip a
/// drag carries (유저 2026-09-11, 미디어 배치 라운드: 「아이콘은 파일 종류를
/// 따른다」).
///
/// The chip used to show a note for every file, whatever it was: the row
/// had its own inline switch and the chip had a constant, so the two could
/// only ever agree by accident.
IconData mediaAssetKindIcon(MediaAssetKind kind) => switch (kind) {
  MediaAssetKind.audio => Icons.music_note_outlined,
  MediaAssetKind.image => Icons.image_outlined,
  MediaAssetKind.video => Icons.movie_outlined,
  MediaAssetKind.pdf => Icons.picture_as_pdf_outlined,
};
