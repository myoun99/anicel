import '../../models/canvas_size.dart';
import '../../models/import/cut_folder_edits.dart' show CutFolderEdits;
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show MovieClock, ProjectClock;
import '../audio/audio_conform_runner.dart' show openAudioSource;
import '../pdf/pdf_render_service.dart';
import 'held_viewer_document.dart';
import 'image_viewer_document.dart';
import 'media_byte_source.dart';
import 'movie_bytes.dart';
import 'video_decode_worker.dart' show videoDecodeBackend;
import 'viewer_document.dart' show pagePixelSize;

/// What a list of files says of each without opening it for good: the size
/// it lands at 1:1, how many pictures it holds — a picture file's frames
/// (a still is one), a movie's frames, a PDF's pages — and a movie's own
/// rate as its decoder names it ([MovieClock.movieRate]; null for every
/// other file), which its frames are counted in the project's by
/// ([placedPicturesOf]).
typedef MediaFacts = ({
  CanvasSize size,
  int pictures,
  ({int numerator, int denominator})? rate,
});

/// [path]'s [MediaFacts] — the size a picture's own pixels, a movie's
/// frame, a PDF's first page as the renderer draws it 1:1 ([pagePixelSize])
/// — read from the bytes [hold] answers for it, the project's own copy
/// first. Null for a sound, which has neither, and for a file that cannot
/// be read.
///
/// 🚨CHEAP ENOUGH TO ASK OF EVERY ROW of a list (the import window's
/// resolution column, F-375, and its one-picture rows, F-429): a picture is
/// read from its header and never decoded ([ImageViewerDocument.factsOf]),
/// a movie's decoder is opened and shut ([readHeldMovieInfo]), a PDF's
/// document opened and closed.
Future<MediaFacts?> readMediaFacts(
  MediaAssetKind kind,
  String path,
  HoldMediaBytes hold,
) async {
  try {
    switch (kind) {
      case MediaAssetKind.image:
        final picture = await readOnHeldBytes(
          hold,
          path,
          ImageViewerDocument.factsOf,
        );
        return (size: picture.size, pictures: picture.pictures, rate: null);
      case MediaAssetKind.video:
        final info = await readHeldMovieInfo(videoDecodeBackend, hold, path);
        return info == null
            ? null
            : (
                size: CanvasSize(width: info.width, height: info.height),
                pictures: info.frameCount,
                rate: (
                  numerator: info.fpsNumerator,
                  denominator: info.fpsDenominator,
                ),
              );
      case MediaAssetKind.pdf:
        final document = await openHeldViewerDocument(
          hold,
          path,
          PdfRenderService.open,
        );
        if (document == null) {
          return null;
        }
        try {
          return (
            size: pagePixelSize(document, 0),
            pictures: document.pageCount,
            rate: null,
          );
        } finally {
          await document.dispose();
        }
      case MediaAssetKind.audio:
        return null;
    }
  } on Object {
    return null;
  }
}

/// How much of [asset] a placement places when it places the file whole,
/// counted as the placement counts it — the length its preset's span is
/// kept from ([MediaPreset.spanOf]), the ONE count the pool's lengths, the
/// drag's silhouette and the sync window say a file's span in: a movie's
/// PROJECT frames on the sound's clock ([MovieClock.projectFramesCovering]
/// — the count the door that places a movie keeps it by), a GIF's frames,
/// a PDF's pages, a still's one ([MediaAsset.pictures]).
///
/// Null for a sound, and for a movie whose rate is not read yet ([facts]):
/// ⛔never the movie's own frame count, which is another clock's — a 30
/// fps take holds 300 frames where a 24 fps project places 240 of them.
int? placedPicturesOf(
  MediaAsset asset,
  MediaFacts? facts,
  ProjectClock clock,
) {
  if (asset.kind != MediaAssetKind.video) {
    return asset.pictures;
  }
  if (facts case (:final pictures, rate: final rate?, size: _)) {
    return MovieClock(
      projectRate: clock.rate,
      audioSpeed: clock.speed,
      movieRate: rate,
    ).projectFramesCovering(pictures);
  }
  return null;
}

/// How many of [asset]'s pictures its preset keeps ([MediaPreset.spanOf])
/// — one where the pool does not know how many it holds.
int keptPicturesOf(MediaAsset asset) {
  final pictures = asset.pictures;
  return pictures == null ? 1 : asset.preset.spanOf(pictures).count;
}

/// The kind of row [asset]'s preset places it as: a sound's SE block, and
/// a picture's kind as far as the pictures it keeps allow — the import
/// window's answer for the same file ([CutFolderEdits.holding], F-429).
///
/// ⛔ONE answer for the pool's kind column and the sync window's kind
/// (card 「파일마다 배치 기본값」-Q8): the column spelled it in the pool's
/// words until the sync asked the same of a placed row.
LayerKind placedKindOf(MediaAsset asset) => asset.kind == MediaAssetKind.audio
    ? LayerKind.se
    : CutFolderEdits.holding(asset.preset.pictureKind, keptPicturesOf(asset));

/// What a list says of a file's SOUND without decoding it: the rate it was
/// made at and how many channels it has — a sound's own, or a movie's
/// soundtrack (the media pool's 오디오 정보, asset-placement-presets Q4).
typedef SoundFacts = ({int sampleRate, int channels});

/// What the media pool has read of a file beyond its entry — its picture's
/// [MediaFacts] and its [SoundFacts], each null where it has none.
typedef MediaPoolFacts = ({MediaFacts? picture, SoundFacts? sound});

/// [path]'s [SoundFacts], off the decoder opened on the bytes [hold] answers
/// for it and let go at once — the door a conform is made through
/// ([openAudioSource]), so a sound says here what its conform will read.
/// Null for a file with no sound this build can open.
Future<SoundFacts?> readSoundFacts(String path, HoldMediaBytes hold) async {
  try {
    return await readOnHeldBytes(hold, path, (source) async {
      final sound = openAudioSource(source);
      if (sound == null) {
        return null;
      }
      try {
        return (sampleRate: sound.sampleRate, channels: sound.channels);
      } finally {
        sound.close();
      }
    });
  } on Object {
    return null;
  }
}
