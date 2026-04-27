import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../models/ui_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _pickLocalIcon(BuildContext context) async {
    final settings = context.read<UiSettings>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      dialogTitle: '选择本地图标',
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    settings.setLocalAppIconPath(path);
  }

  static const _selectedColorOptions = [
    Color(0xFF60A5FA),
    Color(0xFF34D399),
    Color(0xFFF59E0B),
    Color(0xFFF43F5E),
    Color(0xFFA78BFA),
  ];

  static const _inactiveColorOptions = [
    Color(0xFF7A8FA8),
    Color(0xFF8B9AA5),
    Color(0xFF7E8798),
    Color(0xFF8C8C9A),
  ];

  static const _iconOptions = [
    Icons.developer_board_rounded,
    Icons.memory_rounded,
    Icons.settings_suggest_rounded,
    Icons.precision_manufacturing_rounded,
    Icons.hub_rounded,
    Icons.miscellaneous_services_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UiSettings>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            '界面主题与系统信息',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主题预设', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: uiPresets.map((preset) {
                      final selected = settings.topBarColor == preset.topBarColor &&
                          settings.sideBarColor == preset.sideBarColor;
                      return ChoiceChip(
                        label: Text(preset.name),
                        selected: selected,
                        onSelected: (_) => settings.applyPreset(preset),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('选中高亮色', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _selectedColorOptions.map((c) {
                      return _ColorChip(
                        color: c,
                        selected: settings.selectedColor.toARGB32() == c.toARGB32(),
                        onTap: () => settings.setSelectedColor(c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('未选中文字/图标色', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _inactiveColorOptions.map((c) {
                      return _ColorChip(
                        color: c,
                        selected: settings.inactiveColor.toARGB32() == c.toARGB32(),
                        onTap: () => settings.setInactiveColor(c),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主页面图标', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _iconOptions.map((icon) {
                      final selected = settings.appIconCodePoint == icon.codePoint;
                      return InkWell(
                        onTap: () => settings.setAppIcon(icon),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: selected
                                ? settings.selectedColor.withValues(alpha: 0.2)
                                : Colors.grey.shade100,
                            border: Border.all(
                              color: selected ? settings.selectedColor : Colors.grey.shade300,
                            ),
                          ),
                          child: Icon(icon, size: 22),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  const Text('已支持顶部标题图标自定义。', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickLocalIcon(context),
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('从本地选择图标'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: settings.appIconLocalPath == null
                            ? null
                            : () => settings.clearLocalAppIconPath(),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('恢复内置图标'),
                      ),
                    ],
                  ),
                  if (settings.appIconLocalPath != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '当前本地图标: ${settings.appIconLocalPath!.split('\\').last}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('版本信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('产品: 多路电机群控与数据采集系统'),
                  Text('版本: v1.0.0'),
                  Text('通信: RS-485 / Modbus RTU'),
                  Text('平台: Flutter Windows'),
                  Text('作者: GAARAHK'),
                  Text('联系: 840530912@qq.com'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black87 : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}
