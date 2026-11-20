import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/import/cut_folder_edits.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/se_take_placement.dart' show placedSoundBlockOf;
import '../../services/import/raster_cel_import.dart' show fitPose;
import '../dialogs/instance_edit_dialog.dart';
import '../dialogs/instance_edit_preview.dart';
import '../import/fit_flyout_button.dart';
import '../text/app_strings.dart';
import '../text/typed_text.dart';
import '../theme/app_theme.dart';
import '../timeline/layer_label_controls.dart'
    show layerKindDisplayName, layerKindIcon;
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import 'media_asset_kind_icon.dart';
import 'media_pool_pictures.dart';

/// What the preset window answers: the entry's name — the name a picture's
/// layer is born with — and the preset a placement copies.
typedef MediaPresetAnswer = ({String name, MediaPreset preset});

/// The span editor the window shows a file's start and end in: the import
/// window's IN/OUT over the file (`ImportPreview`) — handed in, since it
/// plays through the session.
typedef MediaSpanEditor =
    Widget Function(
      int inFrame,
      int? outFrame,
      void Function(int inFrame, int? outFrame) onChanged,
    );

/// THE 배치 프리셋 WINDOW (🗣️asset-placement-presets Q4 · Q6, 유저
/// 2026-11-17 「시안대로」): what a placement of [asset] copies, edited where
/// the 「SE 편집」 window edits a block — its frame, fields, then a preview,
/// then 취소 · 확인 ([InstanceEditDialogShell]).
///
/// A sound sets its block's name tag and words; a picture its layer's name,
/// its fit, and — one picture — whether it is an image or an animation
/// (Q4 「그림한장은 … 타입을 애니메이션으로할지 이미지로할지」, the import
/// window's own pick, F-429). Start and end are the import window's IN/OUT
/// over the file ([spanEditor]): inside the file, counted as a placement
/// counts it (Q4 「아웃을 원래파일보다 크게 허용할 이유가없어보이는데」).
///
/// ⛔What a placed block keeps for itself — gain, fades, the words' offset
/// and koma, its delivery — is not a preset's ([MediaPreset]).
class MediaPresetWindow extends StatefulWidget {
  const MediaPresetWindow({
    super.key,
    required this.asset,
    required this.canvas,
    this.picture,
    this.pictures,
    this.spanEditor,
    this.soundFrames,
  });

  final MediaAsset asset;

  /// The canvas a picture is fitted to in the preview — the cut on screen's.
  final CanvasSize canvas;

  /// The picture's own size, where it has been read; null draws the canvas
  /// alone.
  final CanvasSize? picture;

  /// Where the fit preview's picture comes from.
  final MediaPoolPictures? pictures;

  /// Null leaves start and end out — a test, or a host with nothing to
  /// play the file through.
  final MediaSpanEditor? spanEditor;

  /// How many project frames the sound lasts, where its conform is held —
  /// how long the preview's block runs.
  final int? soundFrames;

  @override
  State<MediaPresetWindow> createState() => _MediaPresetWindowState();
}

class _MediaPresetWindowState extends State<MediaPresetWindow> {
  late MediaPreset _preset = widget.asset.preset;
  late final TextEditingController _name;
  late final TextEditingController _words;

  bool get _sound => widget.asset.kind == MediaAssetKind.audio;

  /// One picture — a still, a PDF of one page — which asks its kind and
  /// has no span.
  bool get _onePicture => !_sound && widget.asset.pictures == 1;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    final block = placedSoundBlockOf(asset, named: asset.name);
    _name = TextEditingController(text: _sound ? block.seName : asset.name)
      ..addListener(_changed);
    _words = TextEditingController(text: block.words)..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _words.dispose();
    super.dispose();
  }

  /// What the window answers. A sound's tag and words equal to what its
  /// block is born with stay unset: the words follow the entry's name
  /// until someone writes others ([MediaPreset.dialogue]).
  MediaPresetAnswer get _answer {
    final asset = widget.asset;
    if (!_sound) {
      final name = _name.text.trim();
      return (name: name.isEmpty ? asset.name : name, preset: _preset);
    }
    final born = placedSoundBlockOf(
      asset.copyWith(preset: const MediaPreset()),
      named: asset.name,
    );
    final tag = _name.text.trim();
    final words = _words.text.trim();
    return (
      name: asset.name,
      preset: _preset.copyWith(
        seName: tag == born.seName ? null : tag,
        dialogue: words == born.words ? null : words,
      ),
    );
  }

  void _submit() => Navigator.of(context).pop<MediaPresetAnswer>(_answer);

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    return InstanceEditDialogShell(
      title: AppText.strings.mediaPresetTitle(asset.name),
      titleIcon: mediaAssetKindIcon(asset.kind, path: asset.path),
      body: _fields(AppText.strings),
      preview: _sound
          ? InstanceEditPreview.se(
              axis: Axis.horizontal,
              dialogue: _words.text.trim(),
              seName: _name.text.trim(),
              blockFrames: switch (widget.soundFrames) {
                final frames? => _preset.spanOf(frames).count,
                null => null,
              },
            )
          : _FitPreview(
              asset: asset,
              canvas: widget.canvas,
              picture: widget.picture,
              fit: _preset.fit,
              page: _preset.inFrame,
              pictures: widget.pictures,
            ),
      onSubmit: _submit,
    );
  }

  /// The window's fields: the name — a sound's tag — then a sound's words
  /// or a picture's kind and fit, then the span.
  Widget _fields(AppStrings strings) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppWindowField(
        label: _sound ? strings.seNameLabel : strings.commonNameField,
        child: TextField(
          key: const ValueKey<String>('media-preset-name'),
          controller: _name,
          onSubmitted: (_) => _submit(),
          inputFormatters: typedText(),
        ),
      ),
      const SizedBox(height: 12),
      if (_sound)
        AppWindowField(
          label: strings.seDialogueLabel,
          emphasized: true,
          child: TextField(
            key: const ValueKey<String>('media-preset-words'),
            controller: _words,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            inputFormatters: typedText(),
          ),
        )
      else
        Row(
          children: [
            if (_onePicture) ...[
              Expanded(child: _kindField(strings)),
              const SizedBox(width: 12),
            ],
            Expanded(child: _fitField(strings)),
          ],
        ),
      ?_spanField(strings),
    ],
  );

  /// Start and end, where the file has a span — the import window's IN/OUT
  /// over it ([MediaPresetWindow.spanEditor]).
  Widget? _spanField(AppStrings strings) {
    final spanEditor = widget.spanEditor;
    if (spanEditor == null || _onePicture) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppWindowField(
        label: strings.mediaPresetSpan,
        child: SizedBox(
          height: 220,
          child: spanEditor(
            _preset.inFrame,
            _preset.outFrame,
            (inFrame, outFrame) => setState(
              () => _preset = _preset.copyWith(
                inFrame: inFrame,
                outFrame: outFrame,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 이미지 · 애니메이션 — the import window's pick for one picture
  /// (F-429), its kinds offered as that pick offers them.
  Widget _kindField(AppStrings strings) {
    final kind = CutFolderEdits.holding(_preset.pictureKind, 1);
    return AppWindowField(
      label: strings.mediaKindOfLayer,
      child: PanelFlyoutButton(
        key: const ValueKey<String>('media-preset-kind'),
        label: layerKindDisplayName(kind),
        icon: layerKindIcon(kind),
        expand: true,
        entriesBuilder: () => const [LayerKind.image, LayerKind.animation]
            .asFlyoutValueChoices(
              current: kind,
              choiceOf: (choice) => PanelFlyoutChoice(
                key: 'media-preset-kind-${choice.jsonValue}',
                label: layerKindDisplayName(choice),
                icon: layerKindIcon(choice),
                enabled: CutFolderEdits.holds(choice, 1),
              ),
              onPicked: (choice) => setState(
                () => _preset = _preset.copyWith(pictureKind: choice),
              ),
            ),
      ),
    );
  }

  Widget _fitField(AppStrings strings) => AppWindowField(
    label: strings.imFit,
    child: FitFlyoutButton(
      keyPrefix: 'media-preset-fit',
      fit: _preset.fit,
      expand: true,
      onPicked: (fit) => setState(() => _preset = _preset.copyWith(fit: fit)),
    ),
  );
}

/// The canvas with [picture] laid on it by [fit] — the pose a placement
/// starts its reference at ([fitPose]) — and the pasteboard round it, where
/// what overflows the canvas stays.
class _FitPreview extends StatelessWidget {
  const _FitPreview({
    required this.asset,
    required this.canvas,
    required this.picture,
    required this.fit,
    required this.page,
    required this.pictures,
  });

  final MediaAsset asset;
  final CanvasSize canvas;
  final CanvasSize? picture;
  final MediaFitMode fit;
  final int page;
  final MediaPoolPictures? pictures;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('media-preset-fit-preview'),
    height: 140,
    child: CustomPaint(
      painter: _FitPainter(
        asset: asset,
        canvas: canvas,
        picture: picture,
        fit: fit,
        page: page,
        pictures: pictures,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
    ),
  );
}

class _FitPainter extends CustomPainter {
  _FitPainter({
    required this.asset,
    required this.canvas,
    required this.picture,
    required this.fit,
    required this.page,
    required this.pictures,
    required this.devicePixelRatio,
  }) : super(repaint: pictures);

  final MediaAsset asset;
  final CanvasSize canvas;
  final CanvasSize? picture;
  final MediaFitMode fit;
  final int page;
  final MediaPoolPictures? pictures;
  final double devicePixelRatio;

  /// How much of the box round the canvas is pasteboard, each side.
  static const double _reach = 0.2;

  @override
  void paint(Canvas paper, Size size) {
    if (canvas.width <= 0 || canvas.height <= 0) {
      return;
    }
    final scale = math.min(
      size.width / (canvas.width * (1 + 2 * _reach)),
      size.height / (canvas.height * (1 + 2 * _reach)),
    );
    final board = Offset.zero & size;
    final sheet = Rect.fromCenter(
      center: board.center,
      width: canvas.width * scale,
      height: canvas.height * scale,
    );
    paper.drawRect(board, Paint()..color = AppColors.backdrop);
    paper.drawRect(sheet, Paint()..color = AppColors.surfaceHigh);
    final shown = picture;
    if (shown != null && shown.width > 0 && shown.height > 0) {
      final pose = fitPose(picture: shown, canvas: canvas, fit: fit);
      final laid = Rect.fromCenter(
        center: sheet.topLeft + Offset(pose.center.x, pose.center.y) * scale,
        width: shown.width * pose.scaleX * scale,
        height: shown.height * pose.scaleY * scale,
      );
      // What lies past the canvas stays on the pasteboard, dimmed.
      _paintPicture(paper, laid, opacity: 0.35);
      paper.save();
      paper.clipRect(sheet);
      _paintPicture(paper, laid, opacity: 1);
      paper.restore();
    }
    paper.drawRect(
      sheet,
      Paint()
        ..color = AppColors.hairlineStrong
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintPicture(Canvas paper, Rect laid, {required double opacity}) {
    final image = pictures?.pictureOf(
      asset,
      page: page,
      width: math.max(1, (laid.width * devicePixelRatio).round()),
    );
    if (image == null) {
      paper.drawRect(
        laid,
        Paint()..color = AppColors.accent.withValues(alpha: 0.3 * opacity),
      );
      return;
    }
    paintPoolPicture(paper, image, laid, opacity: opacity);
  }

  @override
  bool shouldRepaint(_FitPainter old) =>
      old.asset.path != asset.path ||
      old.canvas != canvas ||
      old.picture != picture ||
      old.fit != fit ||
      old.page != page ||
      old.pictures != pictures ||
      old.devicePixelRatio != devicePixelRatio;
}
