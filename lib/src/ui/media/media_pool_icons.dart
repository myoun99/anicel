import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
import '../audio/waveform_painter.dart';
import '../input/pen_friendly_scroll_controller.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_grid_metrics.dart' show timelineLayerRowHeightIn;
import 'media_asset_kind_icon.dart';
import 'media_pool_pictures.dart';

/// THE POOL AS BIG PICTURES (🗣️asset-placement-presets Q4 · Q6, 유저
/// 2026-11-17 「아이콘보기는 큰 썸네일」 · 「프리미어처럼」): a box a file,
/// its picture 16:10 with what the file is at its top left and how long it
/// runs at its bottom right, and under it the line's own name cell — the
/// list's ([MediaPoolList]), so the two views say one thing.
///
/// 🗣️Q6: 「비디오같은 연속된 재생되는 미디어파일은 프리미어처럼 호버된
/// 마우스커서대로 플립」 — over a movie or a GIF, the cursor's place across
/// the box is the place in the file: the left edge its first frame, the
/// right its last. Off the box, it draws its first again.
class MediaPoolIcons extends StatefulWidget {
  const MediaPoolIcons({
    super.key,
    required this.assets,
    required this.pictures,
    required this.markOf,
    required this.badgeOf,
    required this.captionOf,
    required this.tileOf,
    required this.soundOf,
    required this.frameRate,
  });

  /// The narrowest a box is drawn: the pool fits as many across as are at
  /// least this wide.
  static const double narrowest = 150;

  /// Between two boxes, and around them all.
  static const double gap = 8;

  final List<MediaAsset> assets;

  /// Where a box's picture comes from — none draws each box by its kind.
  final MediaPoolPictures? pictures;

  /// What the file is — or that it is missing — as the line's first mark.
  final Widget Function(MediaAsset asset) markOf;

  /// How long the file runs, as the line's length column says it.
  final String Function(MediaAsset asset) badgeOf;

  /// The line's name cell, under the picture.
  final Widget Function(BuildContext context, MediaAsset asset) captionOf;

  /// [tile] as the thing a hand drags out — the line's own drag source.
  final Widget Function(MediaAsset asset, Widget tile) tileOf;

  /// A sound's waveform, where its conform is held — its picture.
  final AudioPeaks? Function(String path) soundOf;

  /// What a waveform is laid out in.
  final ProjectFrameRate frameRate;

  @override
  State<MediaPoolIcons> createState() => _MediaPoolIconsState();
}

class _MediaPoolIconsState extends State<MediaPoolIcons> {
  final ScrollController _down = PenFriendlyScrollController();

  @override
  void dispose() {
    _down.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = MediaPoolIcons.gap;
    final captionHeight = timelineLayerRowHeightIn(context);
    return LayoutBuilder(
      builder: (context, room) {
        final across = math.max(
          1,
          ((room.maxWidth - gap) / (MediaPoolIcons.narrowest + gap)).floor(),
        );
        final boxHeight =
            math.max(1.0, (room.maxWidth - gap * (across + 1)) / across) /
            MediaPoolPictures.aspect;
        // Its bar is the scroll behaviour's, as every bar is.
        return GridView.builder(
          controller: _down,
          padding: const EdgeInsets.all(gap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: across,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: boxHeight + captionHeight,
          ),
          itemCount: widget.assets.length,
          itemBuilder: (context, index) =>
              _tile(context, widget.assets[index], boxHeight, captionHeight),
        );
      },
    );
  }

  /// [asset]'s box over its name cell, dragged out as its line is.
  Widget _tile(
    BuildContext context,
    MediaAsset asset,
    double boxHeight,
    double captionHeight,
  ) => widget.tileOf(
    asset,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: boxHeight,
          child: _MediaPoolBox(
            key: ValueKey<String>('media-pool-box-${asset.path}'),
            asset: asset,
            pictures: widget.pictures,
            mark: widget.markOf(asset),
            badge: widget.badgeOf(asset),
            sound: asset.kind == MediaAssetKind.audio
                ? widget.soundOf(asset.path)
                : null,
            frameRate: widget.frameRate,
          ),
        ),
        SizedBox(
          height: captionHeight,
          child: widget.captionOf(context, asset),
        ),
      ],
    ),
  );
}

/// One file's picture box, and the frame under the cursor while it crosses.
class _MediaPoolBox extends StatefulWidget {
  const _MediaPoolBox({
    super.key,
    required this.asset,
    required this.pictures,
    required this.mark,
    required this.badge,
    required this.sound,
    required this.frameRate,
  });

  final MediaAsset asset;
  final MediaPoolPictures? pictures;
  final Widget mark;
  final String badge;
  final AudioPeaks? sound;
  final ProjectFrameRate frameRate;

  @override
  State<_MediaPoolBox> createState() => _MediaPoolBoxState();
}

class _MediaPoolBoxState extends State<_MediaPoolBox> {
  /// The page the box draws — its first, or the one under the cursor.
  int _page = 0;

  /// Between the box's edge and its picture: the box's rounded corners are
  /// filled, not clipped — the pool is drawn as a still region, which is
  /// not clipped (`SuperellipseClip`) — so the picture keeps off them.
  static const double _inset = 2;

  /// How many frames a cursor crosses — a movie's or a GIF's, a file that
  /// plays (Q6); none for a still, a PDF's pages or a sound.
  int get _frames {
    final asset = widget.asset;
    final pictures = asset.pictures ?? 0;
    return switch (asset.kind) {
      MediaAssetKind.video || MediaAssetKind.image => pictures,
      MediaAssetKind.pdf || MediaAssetKind.audio => 0,
    };
  }

  void _follow(Offset at, double width) {
    final frames = _frames;
    if (frames < 2 || width <= 0) {
      return;
    }
    final page = (at.dx / width * frames).floor().clamp(0, frames - 1);
    if (page != _page) {
      setState(() => _page = page);
    }
  }

  void _leave() {
    if (_page != 0) {
      setState(() => _page = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ground = Theme.of(context).colorScheme.surfaceContainerHighest;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, room) => MouseRegion(
        onHover: (event) => _follow(event.localPosition, room.maxWidth),
        onExit: (_) => _leave(),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: ground,
            shape: AppShapes.container(AppShapes.wellRadius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Icon(
                  mediaAssetKindIcon(
                    widget.asset.kind,
                    path: widget.asset.path,
                  ),
                  size: 32,
                  color: AppColors.textDim,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(_inset),
                child: _face(
                  ground,
                  devicePixelRatio,
                  room.maxWidth - 2 * _inset,
                ),
              ),
              Positioned(left: 4, top: 4, child: _chip(widget.mark)),
              Positioned(right: 4, bottom: 4, child: _badge()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge() => _chip(
    Text(
      widget.badge,
      style: const TextStyle(
        fontSize: 10.5,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );

  /// The file's picture over the kind it is — drawn when it is in.
  Widget _face(Color ground, double devicePixelRatio, double width) {
    final sound = widget.sound;
    if (widget.asset.kind == MediaAssetKind.audio) {
      final frames = sound?.durationFrames(widget.frameRate) ?? 0;
      if (sound == null || frames <= 0) {
        return const SizedBox.shrink();
      }
      return ColoredBox(
        color: ground,
        child: CustomPaint(
          painter: WaveformPainter(
            peaks: sound,
            frameRate: widget.frameRate,
            pixelsPerFrame: width / frames,
            color: AppColors.text,
            devicePixelRatio: devicePixelRatio,
          ),
        ),
      );
    }
    final pictures = widget.pictures;
    if (pictures == null) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _PicturePainter(
        pictures: pictures,
        asset: widget.asset,
        page: _page,
        devicePixelRatio: devicePixelRatio,
        ground: ground,
      ),
    );
  }

  Widget _chip(Widget child) => DecoratedBox(
    decoration: ShapeDecoration(
      color: AppColors.surface.withValues(alpha: 0.85),
      shape: AppShapes.container(AppShapes.wellRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    ),
  );
}

/// A file's [page] contained in the box, asked of [pictures] as it paints.
///
/// 🚨ASKED AT PAINT, NEVER KEPT: a held picture is let go — disposed — the
/// moment it is the one over the budget ([MediaPoolPictures]), and one kept
/// in a widget would be drawn after. Every paint asks again, and a landing
/// repaints ([repaint]).
class _PicturePainter extends CustomPainter {
  _PicturePainter({
    required this.pictures,
    required this.asset,
    required this.page,
    required this.devicePixelRatio,
    required this.ground,
  }) : super(repaint: pictures);

  final MediaPoolPictures pictures;
  final MediaAsset asset;
  final int page;
  final double devicePixelRatio;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final image = pictures.pictureOf(
      asset,
      page: page,
      width: math.max(1, (size.width * devicePixelRatio).round()),
    );
    if (image == null) {
      return;
    }
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = ground);
    final source = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, size);
    paintPoolPicture(
      canvas,
      image,
      Alignment.center.inscribe(fitted.destination, box),
    );
  }

  @override
  bool shouldRepaint(_PicturePainter old) =>
      old.pictures != pictures ||
      old.asset.path != asset.path ||
      old.asset.carry != asset.carry ||
      old.page != page ||
      old.devicePixelRatio != devicePixelRatio ||
      old.ground != ground;
}
