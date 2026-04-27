import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/database_helper.dart';
import 'models/motor_state.dart';
import 'models/ui_settings.dart';
import 'ui/dashboard_page.dart';
import 'ui/config_page.dart';
import 'ui/history_page.dart';
import 'ui/db_manager_page.dart';
import 'ui/settings_page.dart';
import 'ui/light_control_page.dart';

void main() async {
  // 确保 Flutter Binding 初始化完成
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化窗口管理
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1024, 768),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // 隐藏系统标题栏
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 初始化 Windows SQLite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // 初始化创建数据库结构
  await DatabaseHelper.instance.database;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MotorState()),
        ChangeNotifierProvider(create: (_) => UiSettings()..loadFromPrefs()),
      ],
      child: const MotorControlApp(),
    ),
  );
}

class MotorControlApp extends StatelessWidget {
  const MotorControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '多路电机群控系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      home: const MainNavigator(),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with WindowListener {
  int _currentIndex = 0;
  int _prevIndex = 0; // 用于判断动画方向

  // DB 管理页密码（仅限本地访问控制，防止误操作）
  static const _kDbPassword = '1234567890';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final shouldClose = await _showExitDialog();
    if (shouldClose) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  /// 退出确认对话框
  Future<bool> _showExitDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.red),
            SizedBox(width: 8),
            Text('确认退出'),
          ],
        ),
        content: const Text('确定要退出程序吗？当前正在运行的电机将被停止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出程序'),
          ),
        ],
      ),
    );
    return result == true;
  }

  final List<Widget> _pages = [
    const DashboardPage(),
    const ConfigPage(),
    const HistoryPage(),
    const DbManagerPage(),
    const LightControlPage(),
    const SettingsPage(),
  ];

  /// 弹出密码输入对话框，返回是否验证通过
  Future<bool> _showPasswordDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PasswordDialog(password: _kDbPassword),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: DragToMoveArea(
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ui.selectedColor, ui.selectedColor.withValues(alpha: 0.72)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: _AppLogoWidget(
                  localPath: ui.appIconLocalPath,
                  icon: ui.appIcon,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '多路电机群控与数据采集系统',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: Color(0xFFE2E8F0),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ui.selectedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ui.selectedColor.withValues(alpha: 0.35), width: 1),
                ),
                child: Text(
                  'RS-485',
                  style: TextStyle(
                    fontSize: 10,
                    color: ui.selectedColor.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        titleSpacing: 16,
        flexibleSpace: DragToMoveArea(
          child: Container(
            decoration: BoxDecoration(
              color: ui.topBarColor,
              border: Border(
                bottom: BorderSide(color: ui.topBarBorderColor, width: 1),
              ),
            ),
          ),
        ),
        actions: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WindowCaptionButton.minimize(
                brightness: Brightness.dark,
                onPressed: () async => await windowManager.minimize(),
              ),
              WindowCaptionButton.maximize(
                brightness: Brightness.dark,
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
              ),
              WindowCaptionButton.close(
                brightness: Brightness.dark,
                onPressed: () async {
                  final shouldClose = await _showExitDialog();
                  if (shouldClose) {
                    await windowManager.setPreventClose(false);
                    await windowManager.close();
                  }
                },
              ),
            ],
          )
        ],
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      body: Row(
        children: [
          _AnimatedNavRail(
            selectedIndex: _currentIndex,
            sideBarColor: ui.sideBarColor,
            sideBarDividerColor: ui.sideBarDividerColor,
            selectedColor: ui.selectedColor,
            selectedBgColor: ui.selectedBgColor,
            inactiveColor: ui.inactiveColor,
            appIcon: ui.appIcon,
            appIconLocalPath: ui.appIconLocalPath,
            onTap: (int index) async {
              if (index == 3) {
                if (_currentIndex == 3) return;
                final ok = await _showPasswordDialog();
                if (ok) setState(() { _prevIndex = _currentIndex; _currentIndex = 3; });
              } else {
                setState(() { _prevIndex = _currentIndex; _currentIndex = index; });
              }
            },
          ),
          VerticalDivider(thickness: 1, width: 1, color: ui.sideBarDividerColor.withValues(alpha: 0.5)),
          Expanded(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  final isEntering = child.key == ValueKey(_currentIndex);
                  final dir = _currentIndex >= _prevIndex ? 1.0 : -1.0;
                  // 进入：快启慢停；退出：快速淡出
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                    reverseCurve: const Cubic(0.3, 0, 0.8, 0.15),
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: isEntering
                            ? Offset(0.05 * dir, 0)
                            : Offset(-0.05 * dir, 0),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: ValueKey(_currentIndex),
                  color: ui.pageBgColor,
                  child: _pages[_currentIndex],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 独立对话框 Widget，确保 TextEditingController 由 State.dispose() 释放 ──

class _PasswordDialog extends StatefulWidget {
  final String password;
  const _PasswordDialog({required this.password});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  late final TextEditingController _controller;
  bool _obscure = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == widget.password) {
      Navigator.pop(context, true);
    } else {
      setState(() => _errorText = '密码错误，请重新输入');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text('数据库管理 — 访问验证'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '此页面涉及数据清理等高危操作，请输入管理密码以继续。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '管理密码',
                border: const OutlineInputBorder(),
                errorText: _errorText,
                prefixIcon: const Icon(Icons.password),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

// ── 导航项数据 ────────────────────────────────────────────────────────────────

class _NavItem {
  final IconData outIcon;
  final IconData selIcon;
  final String label;
  const _NavItem(this.outIcon, this.selIcon, this.label);
}

// ── 自定义侧边导航栏（带滑动选中指示器） ────────────────────────────────────

class _AnimatedNavRail extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;
  final Color sideBarColor;
  final Color sideBarDividerColor;
  final Color selectedColor;
  final Color selectedBgColor;
  final Color inactiveColor;
  final IconData appIcon;
  final String? appIconLocalPath;

  static const double _kW     = 100;
  static const double _kItemH = 84;

  static const _items = [
    _NavItem(Icons.grid_view_rounded,  Icons.grid_view_rounded,  '主控看板'),
    _NavItem(Icons.tune_rounded,       Icons.tune_rounded,       '工况配置'),
    _NavItem(Icons.bar_chart_rounded,  Icons.bar_chart_rounded,  '数据追溯'),
    _NavItem(Icons.storage_rounded,    Icons.storage_rounded,    '数据库管理'),
    _NavItem(Icons.lightbulb_rounded,  Icons.lightbulb_rounded,  '灯光控制'),
    _NavItem(Icons.palette_rounded,    Icons.palette_rounded,    '设置'),
  ];

  // ignore: prefer_const_constructors_in_immutables
  _AnimatedNavRail({
    required this.selectedIndex,
    required this.onTap,
    required this.sideBarColor,
    required this.sideBarDividerColor,
    required this.selectedColor,
    required this.selectedBgColor,
    required this.inactiveColor,
    required this.appIcon,
    required this.appIconLocalPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kW,
      color: sideBarColor,
      child: Column(
        children: [
          // ── Logo 区 ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18.0),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF6D28D9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x601D4ED8),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: _AppLogoWidget(
                localPath: appIconLocalPath,
                icon: appIcon,
                size: 26,
              ),
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: sideBarDividerColor,
          ),
          const SizedBox(height: 6),
          // ── 导航项（带滑动指示器） ──
          Expanded(
            child: Stack(
              children: [
                // 毛玻璃色胶囊背景
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  top: selectedIndex * _kItemH + 4,
                  left: 8,
                  right: 8,
                  height: _kItemH - 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selectedBgColor,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      border: Border.all(color: selectedColor.withValues(alpha: 0.35), width: 1),
                    ),
                  ),
                ),
                // 左侧强调竖线
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  top: selectedIndex * _kItemH + 20,
                  left: 9,
                  width: 3,
                  height: _kItemH - 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selectedColor,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
                // 导航项列表
                Column(
                  children: List.generate(_items.length, (i) {
                    final sel = i == selectedIndex;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(10),
                        hoverColor: const Color(0x1060A5FA),
                        splashColor: const Color(0x2060A5FA),
                        child: SizedBox(
                          width: _kW,
                          height: _kItemH,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  _items[i].selIcon,
                                  color: sel ? selectedColor : inactiveColor,
                                  size: sel ? 26 : 24,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: sel ? selectedColor : inactiveColor,
                                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                                  letterSpacing: 0.3,
                                ),
                                child: Text(
                                  _items[i].label,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          // ── 底部版本号 ──
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'v 1.0',
              style: TextStyle(
                fontSize: 9,
                color: Color.fromARGB(255, 186, 192, 219),
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppLogoWidget extends StatelessWidget {
  final String? localPath;
  final IconData icon;
  final double size;

  const _AppLogoWidget({
    required this.localPath,
    required this.icon,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (localPath != null && localPath!.isNotEmpty) {
      final file = File(localPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: size + 10,
            height: size + 10,
            errorBuilder: (_, __, ___) => Icon(icon, size: size, color: Colors.white),
          ),
        );
      }
    }
    return Icon(icon, size: size, color: Colors.white);
  }
}
