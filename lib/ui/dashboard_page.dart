import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../models/motor_state.dart';
import '../models/motor_config.dart';
import '../core/database_helper.dart';
import '../core/serial_manager.dart';
import 'serial_config_dialog.dart';

// 监控主控面板 (已升级为 25 路并支持横向/纵向卷动)
class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<MotorConfigTemplate> _templates = [];
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController(); // 添加纵向滚动控制�?

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final data = await DatabaseHelper.instance.getTemplates();
    if (mounted) {
      setState(() {
        _templates = data.map((e) => MotorConfigTemplate.fromMap(e)).toList();
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double minCardWidth = 1150.0;
        final double actualWidth = math.max(constraints.maxWidth, minCardWidth);
        return Scrollbar(
          controller: _vScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _vScrollController,
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              controller: _hScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hScrollController,
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: actualWidth,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      Consumer<MotorState>(
                        builder: (context, motorState, child) {
                          return Column(
                            children: List.generate(5, (rowIndex) {
                              return _buildMotorRow(context, motorState, rowIndex);
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSerialConfigDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SerialConfigDialog(),
    ).then((_) => setState(() {}));
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '实时监控看板',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Text(
              '',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        Row(
          children: [
            ElevatedButton.icon(
              icon: Icon(
                Icons.cable,
                color: SerialManager().isConnected ? Colors.green : Colors.red,
              ),
              label: const Text('串口配置'),
              onPressed: _showSerialConfigDialog,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新模板'),
              onPressed: _loadTemplates,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('全部启动'),
              onPressed: () {
                context.read<MotorState>().startAll();
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('急停 (E-Stop)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                context.read<MotorState>().stopAll();
              },
            ),
          ],
        )
      ],
    );
  }
  Widget _buildMotorRow(BuildContext context, MotorState motorState, int rowIndex) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${rowIndex + 1} 组 (CH-${rowIndex * 5 + 1}~CH-${rowIndex * 5 + 5})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (_templates.isNotEmpty) // 如果有模板则显示批量应用按钮
                    PopupMenuButton<MotorConfigTemplate>(
                      tooltip: '为本行所有电机统一设置工况',
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.rule_folder, size: 18, color: Colors.blue),
                            SizedBox(width: 4),
                            Text('配置本行工况', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      itemBuilder: (context) {
                        return _templates.map((tpl) => PopupMenuItem(
                          value: tpl,
                          child: Text('应用: ${tpl.name}'),
                        )).toList();
                      },
                      onSelected: (tpl) {
                        motorState.applyConfigToRow(rowIndex, tpl);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已将工况 [${tpl.name}] 应用至第 ${rowIndex + 1} 组'))
                        );
                      },
                    )
                  else
                    const Text('暂无工况可配', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动本行'),
                    onPressed: () {
                      for (int i = 0; i < 5; i++) {
                        int idx = rowIndex * 5 + i;
                        if (idx < motorState.motors.length) {
                          motorState.startMotorSequence(idx);
                        }
                      }
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('停止本行'),
                    onPressed: () {
                      for (int i = 0; i < 5; i++) {
                         int idx = rowIndex * 5 + i;
                         if (idx < motorState.motors.length) {
                           motorState.stopMotorSequence(idx);
                         }
                      }
                    },
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (colIndex) {
              int idx = rowIndex * 5 + colIndex;
              if (idx >= motorState.motors.length) return const Expanded(child: SizedBox.shrink());
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _MotorCard(motor: motorState.motors[idx], index: idx),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }}

class _MotorCard extends StatelessWidget {
  final SingleMotorState motor;
  final int index;

  const _MotorCard({required this.motor, required this.index});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusStr;
    switch (motor.status) {
      case MotorStatus.idle:
        statusColor = Colors.grey;
        statusStr = '空闲/停止';
        break;
      case MotorStatus.runningFwd:
        statusColor = Colors.green;
        statusStr = '正转...';
        break;
      case MotorStatus.runningRev:
        statusColor = Colors.blue;
        statusStr = '反转...';
        break;
      case MotorStatus.waiting:
        statusColor = Colors.orange;
        statusStr = '驻留...';
        break;
      case MotorStatus.alarm:
        statusColor = Colors.red;
        statusStr = '报警停机';
        break;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: motor.isAlarm ? Colors.red : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'CH-${motor.motorId.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: () {
                          if (motor.isRunning) {
                            context.read<MotorState>().stopMotorSequence(index);
                          } else {
                            context.read<MotorState>().startMotorSequence(index);
                          }
                        },
                        child: Icon(
                          motor.isRunning ? Icons.stop_circle : Icons.play_circle_fill,
                          color: motor.isRunning ? Colors.red : Colors.green,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      statusStr,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      labelText: '扫码接入',
                      hintText: motor.qrCode.isEmpty ? '待扫...' : motor.qrCode,
                    ),
                    onSubmitted: (val) {
                      context.read<MotorState>().bindQRCode(index, val);
                    },
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('工况:', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Text(
                          motor.appliedConfig?.name ?? 'No Config',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12, 
                            color: motor.appliedConfig == null ? Colors.red : Colors.black,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('电流:', style: TextStyle(fontSize: 12)),
                      FittedBox(
                        child: Text(
                          '${motor.actualCurrent.toStringAsFixed(2)}A',
                          style: TextStyle(
                            color: (motor.isAlarm) ? Colors.red : Colors.green[800],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('循环:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${motor.currentLoop}/${motor.targetLoops == 0 ? '-' : motor.targetLoops}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}










