import 'package:flutter/foundation.dart';
import 'motor_config.dart';
import '../core/serial_manager.dart';
import '../core/database_helper.dart';

// 电机运行的内部状态机枚举
enum MotorStatus { idle, runningFwd, runningRev, waiting, alarm }

// 单个电机的状态模型
class SingleMotorState {
  final int motorId;        // 设备ID 1~20 (支持到25)
  String qrCode;            // 绑定的二维码
  MotorStatus status;       // 当前运行状态
  int currentLoop;          // 当前循环次数
  int targetLoops;          // 目标总循环次数
  double actualCurrent;     // 实时电流（最后一次采集的值）
  bool isAlarm;             // 是否处于报警停机状态
  MotorConfigTemplate? appliedConfig; // 该电机绑定的当前工况
  bool isRunning = false;             // 内部控制打断标记
  String? currentBatchUuid;           // 追踪当前运行批次的唯一标识

  SingleMotorState({
    required this.motorId,
    this.qrCode = '',
    this.status = MotorStatus.idle,
    this.currentLoop = 0,
    this.targetLoops = 0,
    this.actualCurrent = 0.0,
    this.isAlarm = false,
    this.isRunning = false,
    this.appliedConfig,
    this.currentBatchUuid,
  });
}

class MotorState extends ChangeNotifier {
  // 初始�?5个通道
  final List<SingleMotorState> _motors = List.generate(
    25, 
    (index) => SingleMotorState(motorId: index + 1)
  );

  List<SingleMotorState> get motors => _motors;

  // 扫码绑定
  void bindQRCode(int index, String qr) {
    if (index >= 0 && index < 25) {
      _motors[index].qrCode = qr;
      notifyListeners();
    }
  }

  // 给指定行(5个为一�?的电机应用相同的工况参数
  void applyConfigToRow(int rowIndex, MotorConfigTemplate config) {
    int startIdx = rowIndex * 5;
    for (int i = startIdx; i < startIdx + 5; i++) {
        _motors[i].appliedConfig = config;
        _motors[i].targetLoops = config.targetLoops;
    }
    notifyListeners();
  }

  // 更新运行状�?
  void updateMotorStatus(int index, MotorStatus status) {
    _motors[index].status = status;
    notifyListeners();
  }

  // 记录采集到的数据并判断报警逻辑
  void updateMotorData(int index, double current, int loop, {bool checkAlarm = false, double upperLimit = 10.0, double lowerLimit = 0.5}) {
    final motor = _motors[index];
    motor.actualCurrent = current;
    motor.currentLoop = loop;

    // 1. 电流数据落盘
    if (motor.currentBatchUuid != null) {
      DatabaseHelper.instance.insertCurrentLog({
        'batch_uuid': motor.currentBatchUuid,
        'motor_id': motor.motorId,
        'qr_code': motor.qrCode,
        'loop_count': loop,
        'read_current': current,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    if (checkAlarm && (current > upperLimit || current < lowerLimit)) {
      motor.isAlarm = true;
      motor.status = MotorStatus.alarm;
      motor.isRunning = false;

      // 2. 报警数据落盘
      DatabaseHelper.instance.insertAlarmLog({
        'timestamp': DateTime.now().toIso8601String(),
        'qr_code': motor.qrCode,
        'motor_id': motor.motorId,
        'trip_current': current,
        'limit_value': current > upperLimit ? upperLimit : lowerLimit,
        'action_taken': 'Auto Stop (Out of Bound)',
      });

      // 硬件侧急停
      SerialManager().sendMotorCommand(motor.motorId, 'stop');
    }

    notifyListeners();
  }

  // ====================== 核心业务�?======================

  /// 取消报警复位状态
  void resetAlarm(int index) {
    if (index >= 0 && index < 25) {
      _motors[index].isAlarm = false;
      _motors[index].status = MotorStatus.idle;
      _motors[index].actualCurrent = 0.0; // 清空残留的越界电流显示
      notifyListeners();
    }
  }

  /// 停止单台电机
  Future<void> stopMotorSequence(int index) async {
    if (index < 0 || index >= 25) return;
    final motor = _motors[index];
    motor.isRunning = false;
    motor.isAlarm = false; // 停机操作也可附带清除报警
    motor.status = MotorStatus.idle;

    if (motor.currentBatchUuid != null) {
      DatabaseHelper.instance.updateRunHistoryStatus(motor.currentBatchUuid!, 'stopped');
    }

    notifyListeners(); // 提前刷新UI，避免被底层的串口锁阻塞界面响应
    await SerialManager().sendMotorCommand(motor.motorId, 'stop');
  }

  /// 启动单台电机的工况循�?
  Future<void> startMotorSequence(int index) async {
    if (index < 0 || index >= 25) return;
    final motor = _motors[index];
    if (motor.appliedConfig == null || motor.appliedConfig!.steps.isEmpty) return;

    // 【关键守护】：如果这个电机已经在运行循环中，绝对不允许再次启动！
    // 强制防抖防手滑，防止队列无限重叠把系统撑爆！
    if (motor.isRunning) return; 


    
    // 如果已经在报错、或没有绑定扫码、或没有连上串口（这里可在此做额外守护校验）
    if (!SerialManager().isConnected) {
      // 串口未连接，拒绝启动
      return; 
    }
    
    if (motor.isAlarm) {
      // 当前设备正处于报警锁定状态，需要人工干预（复位或重新配置）
      return;
    }

    if (motor.qrCode.isEmpty) {
      // 尚未绑定设备二维码（SN码），拒绝启动测试
      return;
    }
    
    motor.isRunning = true;
    motor.isAlarm = false;
    // 【修改点】：不再强制清零，保留断点续跑能力。只有原本设定的次数已经全部跑满了，再次点击启动才会从头来。
    if (motor.currentLoop >= motor.targetLoops) {
      motor.currentLoop = 0;
    }

    final config = motor.appliedConfig!;
    
    // 生成新的批次UUID并落盘
    motor.currentBatchUuid = '${DateTime.now().millisecondsSinceEpoch}_M${motor.motorId}';
    DatabaseHelper.instance.insertRunHistory({
       'batch_uuid': motor.currentBatchUuid,
       'motor_id': motor.motorId,
       'qr_code': motor.qrCode,
       'template_id': config.id ?? 0, 
       'start_time': DateTime.now().toIso8601String(),
       'end_status': 'running',
    });

    notifyListeners();
    
    try {
      while (motor.isRunning && motor.currentLoop < config.targetLoops) {
        motor.currentLoop++;
        notifyListeners();

        // 分析本次循环是否该采集数�?
        bool shouldCollect = (motor.currentLoop % config.collectInterval == 0);
        bool hasCollectedThisLoop = false;

        for (var step in config.steps) {
          if (!motor.isRunning) break; // 中途被打断停止或报�?

          // 1. 发送串口指令控制继电器动作
          bool success = await SerialManager().sendMotorCommand(motor.motorId, step.action); 

          if (!success) {
            // 【新增机制】如果驱动模块无响应或通信超时，触发报警并终止序列
            motor.isAlarm = true;               // 切入报警锁死状态
            motor.status = MotorStatus.alarm;   // 让 UI 显示红色的"报警停机"
            motor.isRunning = false;            // 终止运行流水线
            notifyListeners();                  // 立即通知改变卡片样式
            break;                              // 跳出整个工况运转的解析循环
          }

          if (step.action == 'fwd') {
             motor.status = MotorStatus.runningFwd;
          } else if (step.action == 'rev') {
             motor.status = MotorStatus.runningRev;
          } else {
             motor.status = MotorStatus.waiting;
          }
          notifyListeners();

          // 2. 数据采集探测逻辑 (防浪涌采�?
          // 仅当这是一个运转指令，并且大于3秒，并且这轮还没采集过时，执�?延时2~3秒后采集"
          if (shouldCollect && !hasCollectedThisLoop && step.action != 'stop' && step.duration >= 3) {
             hasCollectedThisLoop = true;
             
             // 拆分等待：先�?秒（避开浪涌�?
             await Future.delayed(const Duration(seconds: 2));
             if (!motor.isRunning) break; 
             
             // 触发采集
             double? currentVal = await SerialManager().readCurrentChannel(motor.motorId);
             if (currentVal != null) {
               updateMotorData(index, currentVal, motor.currentLoop, 
                 checkAlarm: true, 
                 upperLimit: config.limitUpper,
                 lowerLimit: config.limitLower
               );
               // 若触发了报错（updateMotorData里会�?isRunning 设为 false�?
               if (!motor.isRunning) break;
             }

             // 剩下的时间继续等�?
             if (step.duration > 2) {
               int remain = step.duration - 2;
               await Future.delayed(Duration(seconds: remain));
             }
          } else {
             // 正常无需采集的等待时�?
             await Future.delayed(Duration(seconds: step.duration));
          }
        }
      }
    } catch (e) {
      print('运行状态机异常: $e');
    } finally {
      // 循环全部结束，或者中途被终止
      if (motor.currentBatchUuid != null) {
         String endStatus = 'stopped';
         if (motor.isAlarm) {
           endStatus = 'alarm';
         } else if (motor.currentLoop >= config.targetLoops) {
           endStatus = 'completed';
         }
         DatabaseHelper.instance.updateRunHistoryStatus(motor.currentBatchUuid!, endStatus);
      }

      if (motor.isRunning) {
        // 自然完成
        motor.isRunning = false;
        motor.status = MotorStatus.idle;
        // 最后发一次纯停指令确保安�?
        await SerialManager().sendMotorCommand(motor.motorId, 'stop');
        notifyListeners();
      }
    }
  }

  /// 广播全部启动 (仅针对已绑定配置且未报警的闲置电�?
  void startAll() {
    for (int i = 0; i < 25; i++) {
       if (!_motors[i].isRunning && !_motors[i].isAlarm && _motors[i].appliedConfig != null) {
          startMotorSequence(i);
       }
    }
  }

  /// 广播全部停止
  void stopAll() {
    for (int i = 0; i < 25; i++) {
        // 优化：只有实际在运行的电机才去发送结束指令，避免下发多余的25次串口指令阻塞整条总线
        if (_motors[i].isRunning || _motors[i].status != MotorStatus.idle) {
          stopMotorSequence(i);
        }
    }
  }
}


