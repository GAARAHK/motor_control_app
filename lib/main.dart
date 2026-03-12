import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database_helper.dart';
import 'models/motor_state.dart';
import 'ui/dashboard_page.dart';
import 'ui/config_page.dart';
import 'ui/history_page.dart';

void main() async {
  // 确保 Flutter Binding 初始化完成
  WidgetsFlutterBinding.ensureInitialized();
  
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
      title: '20路电机群控系统',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
        title: const Text('20路电机群控与数据采集系统'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: false,
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard),
                label: Text('主控看板'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('工况配置'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('数据追溯'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _pages[_currentIndex],
          ),
        ],
      ),
    );
  }
}
