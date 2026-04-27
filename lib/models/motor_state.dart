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
  String alarmReason;        // 报警原因描述，显示在卡片上
  MotorConfigTemplate? appliedConfig; // 该电机绑定的当前工况
  bool isRunning = false;             // 内部控制打断标记
  bool stopCommandSent = false;       // 本轮是否已下发过停机指令（避免重复发送）
  int runToken = 0;                   // 运行代际标识，防止旧协程干扰新循环
  String? currentBatchUuid;           // 追踪当前运行批次的唯一标识

  SingleMotorState({
    required this.motorId,
    this.qrCode = '',
    this.status = MotorStatus.idle,
    this.currentLoop = 0,
    this.targetLoops = 0,
    this.actualCurrent = 0.0,
    this.isAlarm = false,
    this.alarmReason = '',
    this.isRunning = false,
    this.stopCommandSent = false,
    this.runToken = 0,
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

  // COM_C 灯控：7路（地址1~7）
  final List<bool> _lampStates = List<bool>.filled(7, false);
  bool _isTrafficSyncing = false;
  bool _pendingTrafficSync = false;

  List<SingleMotorState> get motors => _motors;
  List<bool> get lampStates => List<bool>.unmodifiable(_lampStates);

  // 扫码绑定
  void bindQRCode(int index, String qr) {
    if (index >= 0 && index < 25) {
      _motors[index].qrCode = qr;
      notifyListeners();
    }
  }

  Future<void> setLampState(int lampId, bool isOn) async {
    if (lampId < 1 || lampId > 7) return;
    final idx = lampId - 1;
    if (_lampStates[idx] == isOn) return;

    _lampStates[idx] = isOn;
    notifyListeners();

    if (!SerialManager().isConnected) return;
    await SerialManager().sendLightCommand(lampId, isOn);
  }

  Future<void> toggleLamp(int lampId) async {
    if (lampId < 1 || lampId > 7) return;
    await setLampState(lampId, !_lampStates[lampId - 1]);
  }

  Future<void> _syncTrafficLights() async {
    if (_isTrafficSyncing) {
      _pendingTrafficSync = true;
      return;
    }
    _isTrafficSyncing = true;

    do {
      _pendingTrafficSync = false;
      final bool anyAlarm = _motors.any((m) => m.isAlarm);
      final bool anyRunning = _motors.any((m) => m.isRunning);

      // 1红 2黄 3绿 4蜂鸣器（与红灯同步）
      await setLampState(1, anyAlarm);
      await setLampState(2, !anyAlarm && !anyRunning);
      await setLampState(3, !anyAlarm && anyRunning);
      await setLampState(4, anyAlarm); // 蜂鸣器，报警时响
    } while (_pendingTrafficSync);

    _isTrafficSyncing = false;
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

  // 记录采集到的数据并判断报警逻辑（async：等待DB写入完成，防止退出时数据丢失）
  Future<void> updateMotorData(int index, double current, int loop, {bool checkAlarm = false, double upperLimit = 10.0, double lowerLimit = 0.5}) async {
    final motor = _motors[index];
    motor.actualCurrent = current;
    motor.currentLoop = loop;

    // 1. 电流数据落盘（await 确保写入完成）
    if (motor.currentBatchUuid != null) {
      await DatabaseHelper.instance.insertCurrentLog({
        'batch_uuid': motor.currentBatchUuid,
        'motor_id': motor.motorId,
        'qr_code': motor.qrCode,
        'loop_count': loop,
        'read_current': current,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    if (checkAlarm && (current > upperLimit || current < lowerLimit)) {
      motor.alarmReason = '电流越限（${current.toStringAsFixed(2)}A）';
      motor.isAlarm = true;
      motor.status = MotorStatus.alarm;
      motor.isRunning = false;

      // 2. 报警数据落盘
      await DatabaseHelper.instance.insertAlarmLog({
        'timestamp': DateTime.now().toIso8601String(),
        'qr_code': motor.qrCode,
        'motor_id': motor.motorId,
        'trip_current': current,
        'limit_value': current > upperLimit ? upperLimit : lowerLimit,
        'action_taken': 'Auto Stop (Out of Bound)',
      });

      // 硬件侧急停
      motor.stopCommandSent = true;
      await SerialManager().sendMotorCommand(motor.motorId, 'stop');
    }

    notifyListeners();
    _syncTrafficLights();
  }

  // ====================== 核心业务�?======================

  /// 取消报警复位状态
  void resetAlarm(int index) {
    if (index >= 0 && index < 25) {
      _motors[index].isAlarm = false;
      _motors[index].alarmReason = '';
      _motors[index].status = MotorStatus.idle;
      _motors[index].actualCurrent = 0.0; // 清空残留的越界电流显示
      notifyListeners();
      _syncTrafficLights();
    }
  }

  /// 停止单台电机
  Future<void> stopMotorSequence(int index) async {
    if (index < 0 || index >= 25) return;
    final motor = _motors[index];

    // 非运行态不下发 stop，避免无效命令占用总线并引发超时
    if (!motor.isRunning) return;

    // 切换运行代际：让旧循环协程在下一次检查时自动失效退出
    motor.runToken++;

    motor.isRunning = false;
    // 不清除报警标志：报警必须由操作员手动点击复位键确认，而不应被停机操作静默清除
    if (!motor.isAlarm) {
      motor.status = MotorStatus.idle;
    }

    if (motor.currentBatchUuid != null) {
      DatabaseHelper.instance.updateRunHistoryStatus(motor.currentBatchUuid!, 'stopped');
    }

    notifyListeners(); // 提前刷新UI，避免被底层的串口锁阻塞界面响应
    _syncTrafficLights();
    motor.stopCommandSent = true;
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
    motor.stopCommandSent = false;
    final int myRunToken = ++motor.runToken;
    // 【修改点】：不再强制清零，保留断点续跑能力。只有原本设定的次数已经全部跑满了，再次点击启动才会从头来。
    if (motor.currentLoop >= motor.targetLoops) {
      motor.currentLoop = 0;
    }

    final config = motor.appliedConfig!;
    
    // 生成新的批次UUID并落盘
     final String runBatchUuid = '${DateTime.now().millisecondsSinceEpoch}_M${motor.motorId}';
     motor.currentBatchUuid = runBatchUuid;
    DatabaseHelper.instance.insertRunHistory({
       'batch_uuid': runBatchUuid,
       'motor_id': motor.motorId,
       'qr_code': motor.qrCode,
       'template_id': config.id ?? 0, 
       'start_time': DateTime.now().toIso8601String(),
       'end_status': 'running',
    });

    notifyListeners();
    _syncTrafficLights();

    bool stopSent = false;
    try {
      while (motor.isRunning && motor.currentLoop < config.targetLoops) {
        if (motor.runToken != myRunToken) break;
        motor.currentLoop++;
        notifyListeners();

        // 分析本次循环是否该采集数�?
        bool shouldCollect = (motor.currentLoop % config.collectInterval == 0);
        bool hasCollectedThisLoop = false;

        for (var step in config.steps) {
          if (motor.runToken != myRunToken) break;
          if (!motor.isRunning) break; // 中途被打断停止或报�?

          // 每个步骤发命令前按通道号做微错峰，降低同一时刻总线竞争峰值
          final int stepSkewMs = ((motor.motorId - 1) % 5) * 12; // 0/12/24/36/48ms
          if (stepSkewMs > 0) {
            await Future.delayed(Duration(milliseconds: stepSkewMs));
            if (motor.runToken != myRunToken) break;
            if (!motor.isRunning) break;
          }

          // 1. 发送串口指令控制继电器动作（带1次重试）
          bool success = false;
          for (int attempt = 0; attempt < 2; attempt++) {
            success = await SerialManager().sendMotorCommand(motor.motorId, step.action);
            if (success) break;
          }

          if (!success) {
            // 连续2次通信失败，确认设备故障，触发报警并终止序列
            motor.alarmReason = '电机模块通信失败';
            motor.isAlarm = true;
            motor.status = MotorStatus.alarm;
            motor.isRunning = false;
            notifyListeners();
            _syncTrafficLights();
            break;
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
             if (motor.runToken != myRunToken) break;
             if (!motor.isRunning) break; 
             
             // 触发采集（1次重试）
             double? currentVal = await SerialManager().readCurrentChannel(motor.motorId);
             if (currentVal == null) {
               // 重试一次
               currentVal = await SerialManager().readCurrentChannel(motor.motorId);
             }
             if (motor.runToken != myRunToken) break;
             if (currentVal != null) {
               await updateMotorData(index, currentVal, motor.currentLoop,
                 checkAlarm: true,
                 upperLimit: config.limitUpper,
                 lowerLimit: config.limitLower
               );
               // 越限停机在 updateMotorData 中已经下发 stop，标记避免 finally 重复发送
               if (motor.isAlarm && !motor.isRunning) {
                 stopSent = true;
               }
               if (!motor.isRunning) break;
             } else {
               // 重试后仍失败，触发报警状态并停机（需手动复位）
               debugPrint('[MotorState][WARN] Motor ${motor.motorId}: 电流读取失败，停止当前循环');
               motor.alarmReason = '电流采集失败';
               motor.isAlarm = true;
               motor.status = MotorStatus.alarm;
               motor.isRunning = false;
               motor.stopCommandSent = true;
               await SerialManager().sendMotorCommand(motor.motorId, 'stop');
               stopSent = true;
               notifyListeners();
               _syncTrafficLights();
               break;
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
      debugPrint('[MotorState][ERROR] 运行状态机异常 motorId=${motor.motorId}: $e');
    } finally {
      // 旧代际协程退出时不允许改动当前状态，避免干扰新循环
      if (motor.runToken != myRunToken) {
        return;
      }

      // 循环全部结束，或者中途被终止（无论何种原因，保证状态干净归位）
      if (runBatchUuid.isNotEmpty) {
         String endStatus = 'stopped';
         if (motor.isAlarm) {
           endStatus = 'alarm';
         } else if (motor.currentLoop >= config.targetLoops) {
           endStatus = 'completed';
         }
         DatabaseHelper.instance.updateRunHistoryStatus(runBatchUuid, endStatus);
      }

      // 无论是自然完成、手动停止还是被打断，都必须确保 isRunning 归 false
      // 同时只有非报警状态才把 status 归 idle，报警状态保留以供操作员识别
      motor.isRunning = false;
      if (motor.status != MotorStatus.alarm) {
        motor.status = MotorStatus.idle;
      }
      // 最后发一次纯停指令确保硬件侧停机
      if (!stopSent && !motor.stopCommandSent) {
        await SerialManager().sendMotorCommand(motor.motorId, 'stop');
      }
      notifyListeners();
      _syncTrafficLights();
    }
  }

  /// 广播全部启动 (仅针对已绑定配置且未报警的闲置电机)
  /// 分批错峰启动：每组5路之间间隔100ms，避免25路同时争抢串口锁导致UI阻塞
  Future<void> startAll() async {
    for (int i = 0; i < 25; i++) {
       if (!_motors[i].isRunning && !_motors[i].isAlarm && _motors[i].appliedConfig != null) {
          startMotorSequence(i); // 不 await，允许并发运行
          // 每启动一路后等待100ms，错峰串口总线压力
          await Future.delayed(const Duration(milliseconds: 100));
       }
    }
  }

  /// 广播全部停止
  void stopAll() {
    for (int i = 0; i < 25; i++) {
        // 仅停止正在运行的通道，避免对空闲/未运行通道发送无效 stop
        if (_motors[i].isRunning) {
          stopMotorSequence(i);
        }
    }
  }
}


