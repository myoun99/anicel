import 'package:flutter/material.dart';

import '../../models/project_background.dart';
import '../editor_session_manager.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// File > Project Background… — the STAGE's colors (R3b, four planes:
/// backdrop → pasteboard → paper → pictures). Paper keeps its preset
/// radios and gains an alpha; the pasteboard (RGBA) and the backdrop
/// (opaque by contract) join it as project data. One undo step per plane
/// actually changed on Apply.
class ProjectBackgroundDialog extends StatefulWidget {
  const ProjectBackgroundDialog({super.key, required this.session});

  final EditorSessionManager session;

  @override
  State<ProjectBackgroundDialog> createState() =>
      _ProjectBackgroundDialogState();
}

enum _BackgroundChoice { defaultPaper, white, black, transparent, custom }

class _ProjectBackgroundDialogState extends State<ProjectBackgroundDialog> {
  late _BackgroundChoice _choice;
  late final TextEditingController _hexController;
  late double _paperAlpha;
  late final TextEditingController _pasteboardHexController;
  late double _pasteboardAlpha;
  late final TextEditingController _backdropHexController;

  @override
  void initState() {
    super.initState();
    final background = widget.session.projectBackground;
    _choice = background.transparent
        ? _BackgroundChoice.transparent
        : background == ProjectBackground.defaultBackground
        ? _BackgroundChoice.defaultPaper
        : background == ProjectBackground.white
        ? _BackgroundChoice.white
        : background == ProjectBackground.black
        ? _BackgroundChoice.black
        : _BackgroundChoice.custom;
    _hexController = TextEditingController(
      text: _rgbText(background.argb),
    );
    _paperAlpha = (background.argb >>> 24).toDouble();
    final project = widget.session.repository.requireProject();
    _pasteboardHexController = TextEditingController(
      text: _rgbText(project.pasteboardArgb),
    );
    _pasteboardAlpha = (project.pasteboardArgb >>> 24).toDouble();
    _backdropHexController = TextEditingController(
      text: _rgbText(project.backdropArgb),
    );
  }

  static String _rgbText(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void dispose() {
    _hexController.dispose();
    _pasteboardHexController.dispose();
    _backdropHexController.dispose();
    super.dispose();
  }

  int? _parsedRgb(TextEditingController controller) {
    final text = controller.text.trim();
    final parsed = int.tryParse(text, radix: 16);
    return parsed == null || text.length != 6 ? null : parsed;
  }

  /// The paper's RGB from the choice; alpha rides the slider (the
  /// transparent preset just parks the slider at 0).
  int? _resolvedPaperRgb() {
    switch (_choice) {
      case _BackgroundChoice.defaultPaper:
        return ProjectBackground.defaultPaperArgb & 0xFFFFFF;
      case _BackgroundChoice.white:
      case _BackgroundChoice.transparent:
        return 0xFFFFFF;
      case _BackgroundChoice.black:
        return 0x000000;
      case _BackgroundChoice.custom:
        return _parsedRgb(_hexController);
    }
  }

  void _apply() {
    final paperRgb = _resolvedPaperRgb();
    final pasteboardRgb = _parsedRgb(_pasteboardHexController);
    final backdropRgb = _parsedRgb(_backdropHexController);
    if (paperRgb == null || pasteboardRgb == null || backdropRgb == null) {
      return;
    }
    final session = widget.session;
    final project = session.repository.requireProject();
    final paper = ProjectBackground.color(
      (_paperAlpha.round() << 24) | paperRgb,
    );
    if (paper != session.projectBackground) {
      session.setProjectBackground(paper);
    }
    final pasteboard = (_pasteboardAlpha.round() << 24) | pasteboardRgb;
    if (pasteboard != project.pasteboardArgb) {
      session.setPasteboardColor(pasteboard);
    }
    final backdrop = 0xFF000000 | backdropRgb;
    if (backdrop != project.backdropArgb) {
      session.setProjectBackdrop(backdrop);
    }
    Navigator.of(context).pop();
  }

  Widget _option(
    _BackgroundChoice choice,
    String label, {
    Widget? trailing,
    Key? key,
  }) {
    return RadioListTile<_BackgroundChoice>(
      key: key,
      dense: true,
      title: trailing == null
          ? Text(label)
          : Row(
              children: [
                Text(label),
                const SizedBox(width: 8),
                Expanded(child: trailing),
              ],
            ),
      value: choice,
    );
  }

  Widget _sectionHeader(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }

  Widget _hexField(TextEditingController controller, {required Key key}) {
    return TextField(
      key: key,
      controller: controller,
      decoration: const InputDecoration(prefixText: '#', isDense: true),
      maxLength: 6,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _alphaRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required Key key,
  }) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: Slider(
            key: key,
            value: value,
            max: 255,
            onChanged: (next) => setState(() => onChanged(next)),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${(value / 255 * 100).round()}%',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('project-background-dialog'),
      title: strings.backgroundTitle,
      titleIcon: Icons.wallpaper_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 400,
      body: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionHeader(strings.stagePaperSection),
            RadioGroup<_BackgroundChoice>(
              groupValue: _choice,
              onChanged: (next) => setState(() {
                _choice = next!;
                // The transparent preset IS "alpha 0 paper" now — the
                // radio parks the slider; every other preset restores an
                // opaque sheet.
                _paperAlpha = next == _BackgroundChoice.transparent
                    ? 0
                    : _paperAlpha == 0
                    ? 255
                    : _paperAlpha;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _option(
                    _BackgroundChoice.defaultPaper,
                    strings.backgroundPaper,
                    key: const ValueKey<String>('background-default'),
                  ),
                  _option(
                    _BackgroundChoice.white,
                    strings.backgroundWhite,
                    key: const ValueKey<String>('background-white'),
                  ),
                  _option(
                    _BackgroundChoice.black,
                    strings.backgroundBlack,
                    key: const ValueKey<String>('background-black'),
                  ),
                  _option(
                    _BackgroundChoice.transparent,
                    strings.backgroundTransparent,
                    key: const ValueKey<String>('background-transparent'),
                  ),
                  _option(
                    _BackgroundChoice.custom,
                    strings.backgroundCustom,
                    key: const ValueKey<String>('background-custom'),
                    trailing: TextField(
                      key: const ValueKey<String>('background-custom-hex'),
                      controller: _hexController,
                      decoration: const InputDecoration(
                        prefixText: '#',
                        isDense: true,
                      ),
                      maxLength: 6,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      // Touching the hex field IS choosing "custom".
                      onTap: () =>
                          setState(() => _choice = _BackgroundChoice.custom),
                      onChanged: (_) =>
                          setState(() => _choice = _BackgroundChoice.custom),
                    ),
                  ),
                ],
              ),
            ),
            _alphaRow(
              label: strings.stageAlphaLabel,
              value: _paperAlpha,
              onChanged: (next) => _paperAlpha = next,
              key: const ValueKey<String>('background-paper-alpha'),
            ),
            _sectionHeader(strings.stagePasteboardSection),
            _hexField(
              _pasteboardHexController,
              key: const ValueKey<String>('background-pasteboard-hex'),
            ),
            _alphaRow(
              label: strings.stageAlphaLabel,
              value: _pasteboardAlpha,
              onChanged: (next) => _pasteboardAlpha = next,
              key: const ValueKey<String>('background-pasteboard-alpha'),
            ),
            _sectionHeader(strings.stageBackdropSection),
            _hexField(
              _backdropHexController,
              key: const ValueKey<String>('background-backdrop-hex'),
            ),
            const SizedBox(height: 8),
            Text(
              strings.backgroundHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('background-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('background-apply-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _apply,
        ),
      ],
    );
  }
}
