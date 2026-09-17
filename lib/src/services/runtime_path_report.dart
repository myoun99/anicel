import 'dart:io';

import '../native/qa_audio_decoder.dart';
import '../native/qa_audio_native.dart';
import '../native/qa_engine_abi.dart';
import '../native/qa_native_engine.dart';
import '../native/qa_tablet_bridge.dart';
import '../core/sync_image_upload.dart';
import '../native/qa_video_encoder.dart';
import 'pdf/pdf_render_service.dart';

/// One runtime-selected implementation path, reported to the user
/// (Preferences > System).
///
/// The app resolves several subsystems at runtime — native C engine vs
/// the Dart reference, OS codec stacks vs the ffmpeg fallback, the
/// Wintab sidecar vs plain OS pointer events. Each resolution is
/// GRACEFUL (absence falls back, never crashes), which also means it is
/// SILENT — this report is where the silence becomes visible, with
/// searchable technology names so a curious user can look them up.
///
/// Adding a future switchable path = adding one entry in
/// [collectRuntimePathReport]. Keep every entry honest: report what IS
/// loaded right now, not what the build hoped for.
class RuntimePathEntry {
  const RuntimePathEntry({
    required this.subsystem,
    required this.active,
    required this.isPrimary,
    required this.detail,
  });

  /// What part of the app this path serves ('Raster engine').
  final String subsystem;

  /// The implementation in use RIGHT NOW ('Native C — qa_engine, ABI 22').
  final String active;

  /// False when a fallback path is engaged — the UI tints these so a
  /// packaging problem is a visible state, not a mystery slowdown.
  final bool isPrimary;

  /// One or two sentences of context with searchable terms (what the
  /// subsystem does, what the alternative path is).
  final String detail;
}

/// Collects the live report. Each check reads the SAME singletons the
/// app's hot paths use, so what this says is what actually runs.
List<RuntimePathEntry> collectRuntimePathReport() {
  final entries = <RuntimePathEntry>[];

  // --- Raster engine (qa_engine): brush strokes, flood fill, the
  // stroke blend, tile composite, bounds scans.
  final raster = QaNativeEngine.instance;
  entries.add(
    RuntimePathEntry(
      subsystem: 'Raster engine',
      active: raster != null
          ? 'Native C (qa_engine, ABI $kQaEngineAbiVersion) — '
                'worker-pool parallel'
          : 'Dart fallback (no native binary loaded)',
      isPrimary: raster != null,
      detail:
          'Brush strokes, flood fill, brush blend modes and tile '
          'composites, called through dart:ffi. The pure-Dart reference '
          'produces byte-identical pixels but runs many times slower; '
          'it engaging outside tests usually means a packaging problem.',
    ),
  );

  // --- Audio engine (same binary): playback mixer + sinc resampler.
  final audio = QaAudioNative.instance;
  entries.add(
    RuntimePathEntry(
      subsystem: 'Audio engine',
      active: audio != null
          ? 'Native C (qa_engine, ABI $kQaEngineAbiVersion)'
          : 'Dart fallback (no native binary loaded)',
      isPrimary: audio != null,
      detail:
          'Realtime playback mixing and windowed-sinc sample-rate '
          'conversion. The Dart reference keeps sound working without '
          'the native binary, at higher CPU cost.',
    ),
  );

  // --- Audio import decoder: bundled decoders + the OS codec stack.
  //
  // 🪦This used to say absence "drops the importer to the ffmpeg conform
  // fallback", and print `ffmpeg fallback` on the panel. There is no such
  // path: the EXPORT-AUDIO round took ffmpeg out of every audio path, and
  // the only two places in `lib/` that start a process are both video
  // export. Naming a fallback that is gone is worse than naming none — it
  // reads as "something still works".
  final decoder = QaAudioDecoder.instance;
  entries.add(
    RuntimePathEntry(
      subsystem: 'Audio import decoder',
      active: decoder != null
          ? 'Native (dr_libs WAV/FLAC/MP3, stb_vorbis OGG, '
                '${_HostOs.current.audioCodec} for AAC/M4A)'
          : 'none — audio does not conform',
      isPrimary: decoder != null,
      detail:
          'Audio files decode ONCE at import (conform). Bundled '
          'decoders read WAV/FLAC/MP3/OGG; AAC goes through the '
          'operating system codec stack. Without the native core there '
          'is no second decoder: waveforms stay blank and clips are '
          'silent.',
    ),
  );

  // --- Video export encoder: the OS encoder is the primary path since
  // AUDIO-PRO R7; ffmpeg is fallback-only.
  final video = QaVideoEncoder.instance;
  final videoSupported = video != null && video.isSupported;
  entries.add(
    RuntimePathEntry(
      subsystem: 'Video export encoder',
      active: videoSupported
          ? '${_HostOs.current.videoEncoder} (H.264/AAC MP4)'
          : 'ffmpeg fallback',
      isPrimary: videoSupported,
      detail:
          'MP4 export renders through the operating system\'s own '
          'hardware-capable encoder; ffmpeg is the fallback for '
          'platforms without one (e.g. Linux).',
    ),
  );

  // --- PDF renderer: PDFium via pdfrx's native assets. UNLIKE the rows
  // above there is no fallback implementation at all — absence means PDF
  // import/viewing are disabled outright, which is exactly why it must
  // be visible here.
  final pdfAvailable = PdfRenderService.availability;
  entries.add(
    RuntimePathEntry(
      subsystem: 'PDF renderer',
      active: pdfAvailable ?? false
          ? 'PDFium (pdfrx, chromium prebuilt)'
          : 'Not loaded — PDF import and viewing are disabled',
      isPrimary: pdfAvailable ?? false,
      detail:
          'PDF pages rasterize through PDFium (Chromium\'s PDF engine), '
          'bundled at build time. There is no substitute path: without '
          'it the importer and the media viewer state the absence '
          'instead of degrading.',
    ),
  );

  // --- Tile picture upload: which road a tile's bytes take to become its
  // picture INSIDE the frame that needs it — they always do, on either.
  entries.add(
    RuntimePathEntry(
      subsystem: 'Tile picture upload',
      active: pictureOfUploads
          ? 'Synchronous upload (Impeller, decodeImageFromPixelsSync)'
          : 'Synchronous draw (Skia, a picture rasterized in the call)',
      isPrimary: pictureOfUploads,
      detail:
          'An edit produces new tile pixels, and the canvas can only '
          'draw a picture of them. Impeller uploads the bytes as they '
          'are; Skia draws them into a picture instead — the same bytes '
          'either way, inside the same frame. Impeller is the default '
          'everywhere as of Flutter 3.47, so the draw road is the test '
          'runner\'s, and this row says which one the engine took.',
    ),
  );

  // --- Pen tablet driver (Windows-only sidecar): pressure/tilt straight
  // from the Wintab driver; everywhere else the OS pointer stream
  // carries pen input.
  final tablet = QaTabletBridge.instanceOrNull;
  final tabletAvailable = tablet != null && tablet.available;
  entries.add(
    RuntimePathEntry(
      subsystem: 'Pen tablet driver',
      active: tabletAvailable
          ? 'Wintab sidecar (qa_tablet) + OS pointer events'
          : Platform.isWindows
          ? 'OS pointer events only (Windows Ink) — no Wintab driver '
                'detected'
          : 'OS pointer events (platform standard)',
      // Off-Windows there IS no sidecar to miss — the OS stream is the
      // primary path there, not a degraded one.
      isPrimary: tabletAvailable || !Platform.isWindows,
      detail:
          'On Windows a Wacom-style Wintab driver can report pressure '
          'the pointer stream misses (hover barrel buttons, finer '
          'pressure curves); whether it is USED follows Preferences > '
          'Input > Tablet service.',
    ),
  );

  return entries;
}

/// The host operating system as the report classifies it, with the names
/// of the codec stack and the video encoder it hands the two OS-named rows.
///
/// ONE classification for both rows: the audio codec and the video
/// encoder used to each carry their own copy of this ladder, which is
/// where a Linux arm could have been added to one and not the other.
enum _HostOs {
  windows(audioCodec: 'Media Foundation', videoEncoder: 'Media Foundation'),
  apple(audioCodec: 'AudioToolbox', videoEncoder: 'AVAssetWriter'),
  android(audioCodec: 'MediaCodec', videoEncoder: 'MediaCodec (NDK)'),
  other(audioCodec: 'OS codecs', videoEncoder: 'OS encoder');

  const _HostOs({required this.audioCodec, required this.videoEncoder});

  final String audioCodec;
  final String videoEncoder;

  static _HostOs get current {
    if (Platform.isWindows) {
      return windows;
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return apple;
    }
    if (Platform.isAndroid) {
      return android;
    }
    return other;
  }
}
