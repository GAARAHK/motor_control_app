import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiSettings extends ChangeNotifier {
  static const _kTopBarColor = 'ui_top_bar_color';
  static const _kTopBarBorderColor = 'ui_top_bar_border_color';
  static const _kSideBarColor = 'ui_side_bar_color';
  static const _kSideBarDividerColor = 'ui_side_bar_divider_color';
  static const _kSelectedColor = 'ui_selected_color';
  static const _kInactiveColor = 'ui_inactive_color';
  static const _kSelectedBgColor = 'ui_selected_bg_color';
  static const _kPageBgColor = 'ui_page_bg_color';
  static const _kAppIconCodePoint = 'ui_app_icon_codepoint';
  static const _kAppIconLocalPath = 'ui_app_icon_local_path';

  Color topBarColor = const Color(0xFF243042);
  Color topBarBorderColor = const Color(0xFF374D65);
  Color sideBarColor = const Color(0xFF243042);
  Color sideBarDividerColor = const Color(0xFF374D65);
  Color selectedColor = const Color(0xFF60A5FA);
  Color inactiveColor = const Color(0xFF7A8FA8);
  Color selectedBgColor = const Color(0x2260A5FA);
  Color pageBgColor = const Color(0xFFF4F6F9);

  int appIconCodePoint = Icons.developer_board_rounded.codePoint;
  String? appIconLocalPath;

  IconData get appIcon =>
      IconData(appIconCodePoint, fontFamily: 'MaterialIcons');

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    topBarColor = Color(
      prefs.getInt(_kTopBarColor) ?? topBarColor.toARGB32(),
    );
    topBarBorderColor = Color(
      prefs.getInt(_kTopBarBorderColor) ?? topBarBorderColor.toARGB32(),
    );
    sideBarColor = Color(
      prefs.getInt(_kSideBarColor) ?? sideBarColor.toARGB32(),
    );
    sideBarDividerColor = Color(
      prefs.getInt(_kSideBarDividerColor) ?? sideBarDividerColor.toARGB32(),
    );
    selectedColor = Color(
      prefs.getInt(_kSelectedColor) ?? selectedColor.toARGB32(),
    );
    inactiveColor = Color(
      prefs.getInt(_kInactiveColor) ?? inactiveColor.toARGB32(),
    );
    selectedBgColor = Color(
      prefs.getInt(_kSelectedBgColor) ?? selectedBgColor.toARGB32(),
    );
    pageBgColor = Color(
      prefs.getInt(_kPageBgColor) ?? pageBgColor.toARGB32(),
    );
    appIconCodePoint = prefs.getInt(_kAppIconCodePoint) ?? appIconCodePoint;
    appIconLocalPath = prefs.getString(_kAppIconLocalPath);

    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTopBarColor, topBarColor.toARGB32());
    await prefs.setInt(_kTopBarBorderColor, topBarBorderColor.toARGB32());
    await prefs.setInt(_kSideBarColor, sideBarColor.toARGB32());
    await prefs.setInt(_kSideBarDividerColor, sideBarDividerColor.toARGB32());
    await prefs.setInt(_kSelectedColor, selectedColor.toARGB32());
    await prefs.setInt(_kInactiveColor, inactiveColor.toARGB32());
    await prefs.setInt(_kSelectedBgColor, selectedBgColor.toARGB32());
    await prefs.setInt(_kPageBgColor, pageBgColor.toARGB32());
    await prefs.setInt(_kAppIconCodePoint, appIconCodePoint);
    if (appIconLocalPath == null || appIconLocalPath!.isEmpty) {
      await prefs.remove(_kAppIconLocalPath);
    } else {
      await prefs.setString(_kAppIconLocalPath, appIconLocalPath!);
    }
  }

  void applyPreset(UiPreset preset) {
    topBarColor = preset.topBarColor;
    topBarBorderColor = preset.topBarBorderColor;
    sideBarColor = preset.sideBarColor;
    sideBarDividerColor = preset.sideBarDividerColor;
    selectedBgColor = preset.selectedBgColor;
    pageBgColor = preset.pageBgColor;
    notifyListeners();
    _saveToPrefs();
  }

  void setSelectedColor(Color color) {
    selectedColor = color;
    notifyListeners();
    _saveToPrefs();
  }

  void setInactiveColor(Color color) {
    inactiveColor = color;
    notifyListeners();
    _saveToPrefs();
  }

  void setAppIcon(IconData icon) {
    appIconCodePoint = icon.codePoint;
    appIconLocalPath = null;
    notifyListeners();
    _saveToPrefs();
  }

  void setLocalAppIconPath(String path) {
    appIconLocalPath = path;
    notifyListeners();
    _saveToPrefs();
  }

  void clearLocalAppIconPath() {
    appIconLocalPath = null;
    notifyListeners();
    _saveToPrefs();
  }
}

class UiPreset {
  final String name;
  final Color topBarColor;
  final Color topBarBorderColor;
  final Color sideBarColor;
  final Color sideBarDividerColor;
  final Color selectedBgColor;
  final Color pageBgColor;

  const UiPreset({
    required this.name,
    required this.topBarColor,
    required this.topBarBorderColor,
    required this.sideBarColor,
    required this.sideBarDividerColor,
    required this.selectedBgColor,
    required this.pageBgColor,
  });
}

const uiPresets = [
  UiPreset(
    name: '石板蓝',
    topBarColor: Color(0xFF243042),
    topBarBorderColor: Color(0xFF374D65),
    sideBarColor: Color(0xFF243042),
    sideBarDividerColor: Color(0xFF374D65),
    selectedBgColor: Color(0x2260A5FA),
    pageBgColor: Color(0xFFF4F6F9),
  ),
  UiPreset(
    name: '墨绿灰',
    topBarColor: Color(0xFF1F2E2B),
    topBarBorderColor: Color(0xFF39504A),
    sideBarColor: Color(0xFF1F2E2B),
    sideBarDividerColor: Color(0xFF39504A),
    selectedBgColor: Color(0x2257D3A0),
    pageBgColor: Color(0xFFF3F6F5),
  ),
  UiPreset(
    name: '深空灰',
    topBarColor: Color(0xFF2A2F3A),
    topBarBorderColor: Color(0xFF464E5F),
    sideBarColor: Color(0xFF2A2F3A),
    sideBarDividerColor: Color(0xFF464E5F),
    selectedBgColor: Color(0x22A78BFA),
    pageBgColor: Color(0xFFF5F6FA),
  ),
];
