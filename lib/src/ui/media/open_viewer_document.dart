import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show ProjectClock;
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/image_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/movie_bytes.dart';
import '../../services/media/project_clock_document.dart';
import '../../services/media/video_decode_worker.dart' show videoDecodeBackend;
import '../../services/media/video_viewer_document.dart';
import '../../services/media/viewer_document.dart';
import '../../services/pdf/pdf_render_service.dart';
import 'audio_viewer_document.dart';

/// Opens whatever [kind] at [path] names, or null when this medium has
/// nothing to show — the one place that knows which document a kind makes,
/// for every surface that shows one: the media viewer, and the import
/// window's preview (import-preview-plays-silent, 2026-09-29: 「뷰어패널이랑
/// 통일할거하면서」 — it used to open each kind a way of its own).
///
/// 🚨★★★**WHERE THE BYTES ARE IS ASKED ONCE, NOT PER KIND** (유저
/// 2026-09-11: 「막힌부분 파일 뭐든 관계없이 법 하나로 통일해서
/// 해결하도록」). An arm here names only how its medium DECODES; where the
/// bytes are is [ProjectFile.holdMediaBytes]'s one question, asked through
/// [openOnHeldBytes] for every kind that reads them.
///
/// 🚨★★★**THE CARRIED COPY WINS OVER THE ORIGINAL, FOR EVERY KIND.**
/// Carrying means 「품은 순간 데이터를 가지고있고 불변이었으면좋겠어서」
/// (유저 2026-08-30), so an original edited or deleted after the import
/// changes nothing the viewer shows. One exception, the cost 유저 accepted
/// on board `carried-movie-compressed-Q1`: a movie kept compressed, on a
/// device whose decoder cannot be fed one (Android below 9), reads its
/// original while there is one ([movieBytesToDecode]).
/// 🪦Images and PDFs used to read the ORIGINAL only, so a carried one
/// whose original was gone — or a project opened on another machine —
/// could not be viewed at all (card `carried-image-pdf-cannot-be-viewed`).
/// 🪦And a movie read the original whenever it was still there: 「⛔The
/// original wins whenever it is still there: an OS opening a file for
/// itself beats any range wrapped around one」. It does, and it showed the
/// EDITED file for a carried movie whose original had changed since.
///
/// [hold] is where the bytes are asked for — the project, or, for a
/// document following its bytes, those same bytes again
/// ([HeldViewerDocument.again]). [soundPeaks] is where a sound's picture
/// comes from. A movie's pages are its own frames — or, given
/// [projectClock], the PROJECT's ([ProjectClockDocument]): the frames a
/// placement counts, for a surface that shows a movie as it will land.
Future<ViewerDocument?> openViewerDocument(
  MediaAssetKind kind,
  String path, {
  required HoldMediaBytes hold,
  required Future<AudioPeaks?> Function(String path) soundPeaks,
  ProjectClock? projectClock,
}) async {
  Future<ViewerDocument?> held(
    Future<ViewerDocument?> Function(MediaByteSource source) open,
  ) => openHeldViewerDocument(hold, path, open);
  switch (kind) {
    case MediaAssetKind.image:
      return held(ImageViewerDocument.open);
    case MediaAssetKind.pdf:
      return held(PdfRenderService.open);
    case MediaAssetKind.video:
      return held((source) async {
        final movie = await VideoViewerDocument.open(
          movieBytesToDecode(source, path, videoDecodeBackend),
        );
        return movie == null || projectClock == null
            ? movie
            : ProjectClockDocument.of(movie, projectClock);
      });
    case MediaAssetKind.audio:
      // 🪦This used to read 「Sound has no picture — the one medium that
      // stays absent」. 유저 2026-09-08: 「오디오파일도 열려야하고 …
      // 오디오는 그래서 파형을 보이게한다던가」. The picture of a sound is
      // its waveform, and the conform that draws one is the same conform
      // playback already builds — so this asks for it rather than making
      // anything.
      final peaks = await soundPeaks(path);
      return peaks == null
          ? null
          : AudioViewerDocument(peaks: peaks, color: AudioViewerDocument.ink);
  }
}
