import 'package:flutter/material.dart';

import '../../models/conte/conte_camera_room.dart';
import '../../models/conte/conte_sheet_form.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'dialog_verb.dart';

/// What the 「콘티 용지 서식」 window answers: the form the sheet is printed
/// in and whether its pictures stand in the black, the front the conte
/// book is printed with — its cover, and the blank page behind it —
/// whether a cell writes what its camera does (I-93), and how much of the
/// sheet a cell whose camera moves takes (I-82).
typedef ConteFormat = ({
  ConteSheetForm form,
  bool outlined,
  bool cover,
  bool blankPage,
  bool fixedText,
  ConteCameraRoom cameraRoom,
});

/// The cuts the window's 컷 설정 row is about: the [words] that say which,
/// and the room the first of them keeps (null for the format's), as the
/// cut button shows the first addressed cut's.
typedef ConteFormatCuts = ({String words, ConteCameraRoom? room});

/// What the window's 저장 gives: the work's [format], and the room picked
/// for the cuts it is about ([cutCameraRoom] — null where none was picked,
/// its `to` null for the format's; I-82).
typedef ConteFormatSave = ({
  ConteFormat format,
  ({ConteCameraRoom? to})? cutCameraRoom,
});

/// The words [room] is picked by — the whole work's two, and the third of
/// the 컷 설정 row for a cut that takes the format's (null).
String conteCameraRoomName(ConteCameraRoom? room) => switch (room) {
  ConteCameraRoom.grows => AppText.strings.conteCameraRoomGrows,
  ConteCameraRoom.inCell => AppText.strings.conteCameraRoomInCell,
  null => AppText.strings.conteCameraRoomAsSheet,
};

/// 「콘티 용지 서식」: the conte sheet's settings, in a window of their own
/// as the timesheet's are (`TimesheetFormatWindow`). Pops the edited
/// [ConteFormat], or null when cancelled.
///
/// 🗣️유저 2026-10-12 (I-93): 「타임시트처럼 전용 설정창 만들어서 거기다 표지
/// 빈용지체크 이런거 다 넣고 … 캔버스 베이스 패널은 무언가 설정할게 있다면
/// 설정버튼만들어서 누르면 창 열려서 거기서 설정하도록」. ↩️The two switches
/// were rows of the panel's settings list from I-59 (10-07) until this
/// window, each a row a key pressed (I-40); a button in a window takes no
/// key (I-40-Q1), so the key is the one that opens the window.
///
/// The form is picked from a list, as the envelope's is (I-93: 「이런 프리셋
/// 변경은 특히 앱 통틀어서 리스트 팝오버로」), and the outline is either
/// form's (유저 2026-10-21, I-118: 「서식 옵션으로 공통적용되게 화면에 검은
/// 외곽선 적용/미적용 버튼」). The camera's room is the whole work's and,
/// under it, the [cuts]' own (I-82-Q1 「서식 전체 + 컷마다 덮어쓰기」).
///
/// 🗣️I-82 (유저 2026-10-31): 「컷별 카메라움직임 설정은 콘티용지서식에
/// 넣자. 카메라 움직임항목에서 전체 설정이랑 컷 설정 두고, 컷 설정에선
/// 현재컷(컷이름) 이런식으로 텍스트 보여주고 해당 항목안에 버튼있는느낌.
/// 기본값은 정해진대로 서식따름.」 ↩️A cut's own stood in 컷 설정.
class ConteFormatWindow extends StatefulWidget {
  const ConteFormatWindow({
    super.key,
    required this.initial,
    required this.cuts,
  });

  final ConteFormat initial;

  /// Null in the gap: no cut to set one for, so the row refuses.
  final ConteFormatCuts? cuts;

  @override
  State<ConteFormatWindow> createState() => _ConteFormatWindowState();
}

class _ConteFormatWindowState extends State<ConteFormatWindow> {
  late ConteSheetForm _form = widget.initial.form;
  late bool _outlined = widget.initial.outlined;
  late bool _cover = widget.initial.cover;
  late bool _blankPage = widget.initial.blankPage;
  late bool _fixedText = widget.initial.fixedText;
  late ConteCameraRoom _cameraRoom = widget.initial.cameraRoom;

  /// The room picked for the cuts — null until one is, so a range whose
  /// cuts differ keeps each one's own until then.
  ({ConteCameraRoom? to})? _cutCameraRoom;

  ConteCameraRoom? get _shownCutCameraRoom => switch (_cutCameraRoom) {
    (:final to) => to,
    null => widget.cuts?.room,
  };

  static String _formName(ConteSheetForm form) => switch (form) {
    ConteSheetForm.analog => AppText.strings.conteFormAnalog,
    ConteSheetForm.digital => AppText.strings.conteFormDigital,
  };

  /// One row of the window: [label], and what sets it.
  static Widget _field(String label, Widget child) => AppWindowField(
    label: label,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  /// The forms, the one picked lit.
  List<PanelFlyoutEntry> _forms() => ConteSheetForm.values.asFlyoutChoices(
    current: _form,
    keyPrefix: 'conte-format-form-',
    labelOf: _formName,
    onPicked: (form) => setState(() => _form = form),
  );

  /// How much a moving camera's cell takes, the one picked lit — a list, as
  /// the form is (I-93 「리스트 팝오버로」).
  Widget _cameraRoomButton() => PanelFlyoutButton(
    key: const ValueKey<String>('conte-format-camera-room'),
    label: conteCameraRoomName(_cameraRoom),
    entriesBuilder: () => ConteCameraRoom.values.asFlyoutChoices(
      current: _cameraRoom,
      keyPrefix: 'conte-format-camera-room-',
      labelOf: conteCameraRoomName,
      onPicked: (room) => setState(() => _cameraRoom = room),
    ),
  );

  /// The cuts' own room beside the words that say which cuts — the
  /// format's (null) or one of their own, the one picked lit.
  Widget _cutCameraRoomRow() {
    final cuts = widget.cuts;
    const rooms = <ConteCameraRoom?>[null, ...ConteCameraRoom.values];
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Flexible(
          child: Text(
            cuts?.words ?? AppText.strings.noCutSelected,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        PanelFlyoutButton(
          key: const ValueKey<String>('conte-format-cut-camera-room'),
          label: conteCameraRoomName(_shownCutCameraRoom),
          enabled: cuts != null,
          entriesBuilder: () => rooms.asFlyoutValueChoices(
            current: _shownCutCameraRoom,
            choiceOf: (room) => PanelFlyoutChoice(
              key: 'conte-format-cut-camera-room-${room?.name ?? 'format'}',
              label: conteCameraRoomName(room),
            ),
            onPicked: (room) => setState(() => _cutCameraRoom = (to: room)),
          ),
        ),
      ],
    );
  }

  /// How much a moving camera's cell takes: the whole work's and the cuts'.
  Widget _cameraRoomField() {
    final strings = AppText.strings;
    return AppWindowField(
      label: strings.conteCameraRoom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _field(strings.conteCameraRoomAll, _cameraRoomButton()),
          _field(strings.cutSettingsTitle, _cutCameraRoomRow()),
        ],
      ),
    );
  }

  /// One page of the front, put in or left out.
  Widget _page(String keyValue, bool on, ValueChanged<bool> onChanged) {
    final strings = AppText.strings;
    return TogglePill(
      keyValue: keyValue,
      on: on,
      words: (on: strings.conteFrontIn, off: strings.conteFrontOut),
      onChanged: onChanged,
    );
  }

  /// Whether each cell writes what its camera does over its ACTION words
  /// (🗣️I-93, 유저 2026-10-12: 「고정텍스트 표기할지 안할지 콘티용지패널에
  /// 설정할수있도록」).
  Widget _fixedTextSwitch() {
    final strings = AppText.strings;
    return TogglePill(
      keyValue: 'conte-format-fixed-text',
      on: _fixedText,
      // ⚠️Mine: the outline's words — a plain on and off in every language.
      words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
      onChanged: (on) => setState(() => _fixedText = on),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('conte-format-window'),
      title: strings.conteFormatTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      body: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _field(
              strings.conteForm,
              PanelFlyoutButton(
                key: const ValueKey<String>('conte-format-form'),
                label: _formName(_form),
                entriesBuilder: _forms,
              ),
            ),
            _field(
              strings.conteOutline,
              TogglePill(
                keyValue: 'conte-format-outline',
                on: _outlined,
                words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
                onChanged: (on) => setState(() => _outlined = on),
              ),
            ),
            _field(
              strings.conteCoverPage,
              _page(
                'conte-format-cover',
                _cover,
                (on) => setState(() => _cover = on),
              ),
            ),
            _field(
              strings.conteBlankPage,
              _page(
                'conte-format-blank-page',
                _blankPage,
                (on) => setState(() => _blankPage = on),
              ),
            ),
            _field(strings.conteFixedText, _fixedTextSwitch()),
            _cameraRoomField(),
          ],
        ),
      ),
      actions: saveActions(
        context,
        prefix: 'conte-format',
        onSave: () => Navigator.of(context).pop<ConteFormatSave>((
          format: _edited,
          cutCameraRoom: _cutCameraRoom,
        )),
      ),
    );
  }

  ConteFormat get _edited => (
    form: _form,
    outlined: _outlined,
    cover: _cover,
    blankPage: _blankPage,
    fixedText: _fixedText,
    cameraRoom: _cameraRoom,
  );
}
