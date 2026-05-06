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
                      const SizedBox(height: 36), // 增加顶部操作区与卡片区域的距离，防止误触
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8)
                ),
                child: const Icon(Icons.dashboard_customize, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 12),
              const Text(
                '实时监控看板',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                ),
                onPressed: _showSerialConfigDialog,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新模板'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                  elevation: 0,
                ),
                onPressed: _loadTemplates,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('全部启动', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  context.read<MotorState>().startAll();
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.report_problem),
                label: const Text('总急停 (E-Stop)', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  context.read<MotorState>().stopAll();
                },
              ),
            ],
          )
        ],
      ),
    );
  }
  Widget _buildMotorRow(BuildContext context, MotorState motorState, int rowIndex) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.group_work, color: Colors.blueGrey, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '第 ${rowIndex + 1} 组总线 (CH-${rowIndex * 5 + 1} ~ CH-${rowIndex * 5 + 5})',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_templates.isNotEmpty) // 如果有模板则显示批量应用按钮
                      PopupMenuButton<MotorConfigTemplate>(
                        tooltip: '为本行所有电机统一设置工况',
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.rule_folder, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Text('配置全组方案', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                        itemBuilder: (context) {
                          return _templates.map((tpl) => PopupMenuItem(
                            value: tpl,
                            child: Text('应用工况: ${tpl.name}'),
                          )).toList();
                        },
                        onSelected: (tpl) {
                          motorState.applyConfigToRow(rowIndex, tpl);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ 已将工况 [${tpl.name}] 应用至第 ${rowIndex + 1} 组'),
                              backgroundColor: Colors.green,
                            )
                          );
                        },
                      )
                    else
                      const Text('暂无工况可配', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('启动组'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        for (int i = 0; i < 5; i++) {
                          int idx = rowIndex * 5 + i;
                          if (idx < motorState.motors.length) {
                            motorState.startMotorSequence(idx);
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('停止组'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
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
          ),
          const SizedBox(height: 12),
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

class _MotorCard extends StatefulWidget {
  final SingleMotorState motor;
  final int index;

  const _MotorCard({required this.motor, required this.index});

  @override
  State<_MotorCard> createState() => _MotorCardState();
}

class _MotorCardState extends State<_MotorCard> {
  final TextEditingController _qrController = TextEditingController();
  final FocusNode _qrFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 初始化时将已绑定的二维码同步到输入框
    _qrController.text = widget.motor.qrCode;
    // 监听焦点变化，获取焦点时清空输入框，实现重新扫描录入
    _qrFocusNode.addListener(() {
      if (_qrFocusNode.hasFocus) {
         _qrController.clear();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MotorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Provider rebuild 时同步最新 qrCode 到输入框
    // 仅在未获焦点时更新，避免打断正在扫码输入的操作
    if (!_qrFocusNode.hasFocus && widget.motor.qrCode != oldWidget.motor.qrCode) {
      _qrController.text = widget.motor.qrCode;
    }
  }

  @override
  void dispose() {
    _qrController.dispose();
    _qrFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusStr;
    switch (widget.motor.status) {
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
        statusStr = widget.motor.alarmReason.isNotEmpty
            ? widget.motor.alarmReason
            : '报警停机';
        break;
    }

    return Card(
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: widget.motor.isAlarm ? Colors.red.shade400 : Colors.grey.shade200,
          width: widget.motor.isAlarm ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: widget.motor.isAlarm 
                ? [Colors.red.shade50, Colors.white]
                : [Colors.white, Colors.blueGrey.shade50.withOpacity(0.3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        ),
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade800,
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          'CH-${widget.motor.motorId.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          if (widget.motor.isAlarm) {
                            context.read<MotorState>().resetAlarm(widget.index);
                          } else if (widget.motor.isRunning) {
                            context.read<MotorState>().stopMotorSequence(widget.index);
                          } else {
                            context.read<MotorState>().startMotorSequence(widget.index);
                          }
                        },
                        child: Icon(
                          widget.motor.isAlarm 
                              ? Icons.settings_backup_restore 
                              : (widget.motor.isRunning ? Icons.stop_circle : Icons.play_circle_fill),
                          color: widget.motor.isAlarm 
                              ? Colors.orange.shade700 
                              : (widget.motor.isRunning ? Colors.red.shade600 : Colors.green.shade600),
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5))
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      statusStr,
                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6)
                    ),
                    child: TextField(
                      controller: _qrController,
                      focusNode: _qrFocusNode,
                      onChanged: (val) {
                        context.read<MotorState>().bindQRCode(widget.index, val);
                      },
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.qr_code, size: 16, color: Colors.grey.shade600),
                        prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 0),
                        hintText: widget.motor.qrCode.isEmpty ? '待扫码..' : widget.motor.qrCode,
                        hintStyle: TextStyle(color: Colors.grey.shade500)
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('码值绑定:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Expanded(
                        child: Text(
                          widget.motor.qrCode.isEmpty ? '未绑定' : widget.motor.qrCode,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: widget.motor.qrCode.isEmpty ? Colors.grey.shade400 : Colors.blue.shade700,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('当前工况:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Expanded(
                        child: Text(
                          widget.motor.appliedConfig?.name ?? '未配置',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            color: widget.motor.appliedConfig == null ? Colors.red.shade300 : Colors.black87,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.motor.isAlarm ? Colors.red.shade50 : (widget.motor.actualCurrent > 0 ? Colors.green.shade50 : Colors.transparent),
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('适时电流:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        FittedBox(
                          child: Text(
                            '${widget.motor.actualCurrent.toStringAsFixed(2)} A',
                            style: TextStyle(
                              color: (widget.motor.isAlarm) ? Colors.red.shade600 : Colors.green.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('运行循环:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Row(
                        children: [
                          Text(
                            '${widget.motor.currentLoop}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                          ),
                          Text(
                            ' / ${widget.motor.targetLoops == 0 ? '-' : widget.motor.targetLoops}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 14,
                              tooltip: '清零循环次数',
                              icon: Icon(Icons.refresh, size: 14, color: Colors.grey.shade400),
                              onPressed: widget.motor.isRunning
                                  ? null
                                  : () {
                                      final state = context.read<MotorState>();
                                      final idx = state.motors.indexOf(widget.motor);
                                      if (idx >= 0) state.resetLoopCount(idx);
                                    },
                            ),
                          ),
                        ],
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










