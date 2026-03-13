import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/database_helper.dart';
import 'models/motor_state.dart';
import 'ui/dashboard_page.dart';
import 'ui/config_page.dart';
import 'ui/history_page.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.grey.shade50,
          indicatorColor: Colors.blue.shade100,
          selectedIconTheme: const IconThemeData(color: Color(0xFF1565C0)),
          selectedLabelTextStyle: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold),
          unselectedIconTheme: IconThemeData(color: Colors.blueGrey.shade400),
          unselectedLabelTextStyle: TextStyle(color: Colors.blueGrey.shade500),
        ),
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

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const ConfigPage(),
    const HistoryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: DragToMoveArea(
          child: const Row(
            children: [
              Icon(Icons.precision_manufacturing, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text('多路电机群控与数据采集系统', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
        titleSpacing: 16,
        flexibleSpace: DragToMoveArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                onPressed: () async => await windowManager.close(),
              ),
            ],
          )
        ],
        elevation: 4,
        shadowColor: Colors.black45,
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: false,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))
                  ],
                ),
                child: const Icon(Icons.hub, size: 32, color: Color(0xFF1565C0)),
              ),
            ),
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('主控看板'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('工况配置'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('数据追溯'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.black12),
          Expanded(
            child: Container(
              color: Colors.white,
              child: _pages[_currentIndex],
            ),
          ),
        ],
      ),
    );
  }
}
