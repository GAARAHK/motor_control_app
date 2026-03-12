// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motor_control_app/main.dart';
import 'package:provider/provider.dart';
import 'package:motor_control_app/models/motor_state.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MotorState()),
        ],
        child: const MotorControlApp(),
      ),
    );

    // 验证应用是否正常加载并在主页显示了"20路电机串口群控与数据采集系统"这段字
    expect(find.text('实时监控面板'), findsWidgets);
  });
}
