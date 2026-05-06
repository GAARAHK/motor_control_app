import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../utils/modbus_crc.dart';

// COM_A 控制串口 与 COM_B 采集串口 的单例管理
class SerialManager {
  static final SerialManager _instance = SerialManager._internal();
  factory SerialManager() => _instance;
  SerialManager._internal();

  /// 维护端口实例对象
  SerialPort? _comA; // 电机控制
  SerialPort? _comB; // 电流采集
  SerialPort? _comC; // 灯控控制（7路）

  String? portAName;
  String? portBName;
  String? portCName;
  bool isConnected = false;

  int _baudRateA = 19200;
  int _dataBitsA = 8;
  int _stopBitsA = 1;
  int _parityA = SerialPortParity.none;

  int _baudRateB = 19200;
  int _dataBitsB = 8;
  int _stopBitsB = 1;
  int _parityB = SerialPortParity.none;

  int _baudRateC = 19200;
  int _dataBitsC = 8;
  int _stopBitsC = 1;
  int _parityC = SerialPortParity.none;

  // 使用 Completer 进行异步等待回调机制
  bool _isComABusy = false;
  bool _isComBBusy = false;
  bool _isComCBusy = false;

  void _drainRx(SerialPort port) {
    // 清空历史残留数据，避免上一帧残片影响本次CRC判断。
    // 注意：某些串口驱动在 timeout=0 时会阻塞，需使用极短超时并限制总时长。
    final sw = Stopwatch()..start();
    for (int i = 0; i < 16; i++) {
      if (sw.elapsedMilliseconds > 20) break;
      Uint8List chunk;
      try {
        chunk = port.read(256, timeout: 1);
      } catch (_) {
        break;
      }
      if (chunk.isEmpty) break;
    }
  }

  bool _hasValidFixedFrame(
    List<int> buffer,
    int address,
    int function,
    int frameLen,
  ) {
    if (buffer.length < frameLen) return false;
    for (int i = 0; i <= buffer.length - frameLen; i++) {
      if (buffer[i] != address || buffer[i + 1] != function) continue;
      final frame = Uint8List.fromList(buffer.sublist(i, i + frameLen));
      if (ModbusCrc.verifyCRC16(frame)) {
        return true;
      }
    }
    return false;
  }

  Uint8List? _extractFixedFrame(
    List<int> buffer,
    int address,
    int function,
    int frameLen,
  ) {
    if (buffer.length < frameLen) return null;
    for (int i = 0; i <= buffer.length - frameLen; i++) {
      if (buffer[i] != address || buffer[i + 1] != function) continue;
      final frame = Uint8List.fromList(buffer.sublist(i, i + frameLen));
      if (ModbusCrc.verifyCRC16(frame)) {
        return frame;
      }
    }
    return null;
  }

  /// 获取系统当前可用串口列表
  List<String> get availablePorts => SerialPort.availablePorts;

  /// 配置参数并尝试打开串口；portCName 为 null 时跳过灯控总线，不影响 isConnected
  Future<bool> initPorts(String portAName, String portBName, String? portCName, {
    int baudRateA = 19200, 
    int dataBitsA = 8, 
    int stopBitsA = 1, 
    int parityA = SerialPortParity.none,
    int baudRateB = 19200, 
    int dataBitsB = 8, 
    int stopBitsB = 1, 
    int parityB = SerialPortParity.none,
    int baudRateC = 19200,
    int dataBitsC = 8,
    int stopBitsC = 1,
    int parityC = SerialPortParity.none,
  }) async {
    this.portAName = portAName;
    this.portBName = portBName;
    this.portCName = portCName;
    _baudRateA = baudRateA;
    _dataBitsA = dataBitsA;
    _stopBitsA = stopBitsA;
    _parityA = parityA;

    _baudRateB = baudRateB;
    _dataBitsB = dataBitsB;
    _stopBitsB = stopBitsB;
    _parityB = parityB;

    _baudRateC = baudRateC;
    _dataBitsC = dataBitsC;
    _stopBitsC = stopBitsC;
    _parityC = parityC;
    
    bool success = true;

    try {
      if (_comA != null && _comA!.isOpen) _comA!.close();
      _comA = SerialPort(portAName);
      if (_comA!.openReadWrite()) {
        _comA!.config = _getSpConfigA();
      } else {
        success = false;
      }
    } catch (e) {
      debugPrint('[SerialManager][ERROR] Failed to open COM_A: $e');
      success = false;
    }

    try {
      if (_comB != null && _comB!.isOpen) _comB!.close();
      _comB = SerialPort(portBName);
      if (_comB!.openReadWrite()) {
         _comB!.config = _getSpConfigB();
      } else {
        success = false;
      }
    } catch (e) {
      debugPrint('[SerialManager][ERROR] Failed to open COM_B: $e');
      success = false;
    }

    // COM_C 灯控为可选总线，打开失败不影响主连接状态
    if (portCName != null && portCName.isNotEmpty) {
      try {
        if (_comC != null && _comC!.isOpen) _comC!.close();
        _comC = SerialPort(portCName);
        if (_comC!.openReadWrite()) {
          _comC!.config = _getSpConfigC();
        } else {
          debugPrint('[SerialManager][WARN] COM_C open failed, light control disabled');
          _comC = null;
        }
      } catch (e) {
        debugPrint('[SerialManager][ERROR] Failed to open COM_C: $e');
        _comC = null;
      }
    } else {
      // 未配置 COM_C，关闭旧连接
      if (_comC?.isOpen == true) _comC?.close();
      _comC = null;
    }

    isConnected = success;
    return success;
  }

  SerialPortConfig _getSpConfigA() {
    final conf = SerialPortConfig();
    conf.baudRate = _baudRateA;
    conf.bits = _dataBitsA;
    conf.parity = _parityA;
    conf.stopBits = _stopBitsA;
    return conf;
  }

  SerialPortConfig _getSpConfigB() {
    final conf = SerialPortConfig();
    conf.baudRate = _baudRateB;
    conf.bits = _dataBitsB;
    conf.parity = _parityB;
    conf.stopBits = _stopBitsB;
    return conf;
  }

  SerialPortConfig _getSpConfigC() {
    final conf = SerialPortConfig();
    conf.baudRate = _baudRateC;
    conf.bits = _dataBitsC;
    conf.parity = _parityC;
    conf.stopBits = _stopBitsC;
    return conf;
  }

  void closePorts() {
    _isComABusy = false;
    _isComBBusy = false;
    _isComCBusy = false;
    if (_comA?.isOpen == true) _comA?.close();
    if (_comB?.isOpen == true) _comB?.close();
    if (_comC?.isOpen == true) _comC?.close();
    isConnected = false;
  }

  // ============== COM_A: 单路直流电机控制 ==============

  /// 向指定地址的电机发送控制指令：fwd(正转 0x01), rev(反转 0x02), stop(停止 0x00)
  Future<bool> sendMotorCommand(int motorAddress, String action) async {
    if (_comA == null || !_comA!.isOpen) return false;
    
    // 互斥锁，防止高并发导致 485 冲突 (带超时保护防止死锁)
    int lockWaitCount = 0;
    while (_isComABusy) {
      if (lockWaitCount > 100) { // 等待锁超过1秒强行破除死锁
        _isComABusy = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
      lockWaitCount++;
    }
    _isComABusy = true;

    try {
      int actionValue = 0x00;
      if (action == 'fwd') actionValue = 0x01;
      else if (action == 'rev') actionValue = 0x02;
      else if (action == 'stop') actionValue = 0x00;

      // 报文结构：地址(1), 功能码(1, 0x06), 寄存器高(1, 0x00), 寄存低(1, 0x00), 变量高(1, 0x00), 变量低(1, action)
      Uint8List data = Uint8List.fromList([
        motorAddress,
        0x06,
        0x00, 0x00,
        0x00, actionValue
      ]);
      
      Uint8List frame = ModbusCrc.appendCRC16(data);
      _drainRx(_comA!);
      
      _comA!.write(frame);
      
      bool success = false;
      int waitCount = 0;
      List<int> buffer = [];
      
      while (waitCount < 10) { // 最多等 10 x 10ms = 100ms
        Uint8List chunk = _comA!.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
          if (_hasValidFixedFrame(buffer, motorAddress, 0x06, 8)) {
              success = true;
              break;
           }
        }
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
      }
      
      if (!success) {
        debugPrint('[SerialManager][WARN] sendMotorCommand timeout: addr=$motorAddress action=$action');
      }
return success;
    } catch (e) {
      debugPrint('[SerialManager][ERROR] sendMotorCommand exception: $e');
      return false;
    } finally {
      // 延迟一小段时间，释放 485 总线资源
      await Future.delayed(const Duration(milliseconds: 10));
      _isComABusy = false;
    }
  }

  // ============== COM_C: 7路灯控模块 ==============

  /// 灯控指令：on(映射fwd=0x01) / off(映射stop=0x00)
  Future<bool> sendLightCommand(int lightAddress, bool on) async {
    if (_comC == null || !_comC!.isOpen) return false;

    int lockWaitCount = 0;
    while (_isComCBusy) {
      if (lockWaitCount > 100) {
        _isComCBusy = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
      lockWaitCount++;
    }
    _isComCBusy = true;

    try {
      final int value = on ? 0x01 : 0x00;
      final data = Uint8List.fromList([
        lightAddress,
        0x06,
        0x00, 0x00,
        0x00, value,
      ]);

      final frame = ModbusCrc.appendCRC16(data);
      _drainRx(_comC!);
      _comC!.write(frame);

      bool success = false;
      int waitCount = 0;
      final List<int> buffer = [];

      while (waitCount < 10) {
        final chunk = _comC!.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
          buffer.addAll(chunk);
          if (_hasValidFixedFrame(buffer, lightAddress, 0x06, 8)) {
            success = true;
            break;
          }
        }
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
      }

      if (!success) {
        debugPrint('[SerialManager][WARN] sendLightCommand timeout: addr=$lightAddress on=$on');
      }
      return success;
    } catch (e) {
      debugPrint('[SerialManager][ERROR] sendLightCommand exception: $e');
      return false;
    } finally {
      await Future.delayed(const Duration(milliseconds: 10));
      _isComCBusy = false;
    }
  }

  // ============== COM_B: 24路全隔离交直流采集器 ==============

  /// 读取指定路(通道)的实际电流值
  /// 注意这里通道1 对应寄存器 0x0000, 故寄存器地址 = channel - 1
  /// 由于采集模块自身地址固定（假设为 1），可配置参数
  Future<double?> readCurrentChannel(int channel, {int deviceAddress = 1, double rangeMax = 2.0}) async {
    if (_comB == null || !_comB!.isOpen) return null;

    int lockWaitCount = 0;
    while (_isComBBusy) {
      if (lockWaitCount > 100) {
        _isComBBusy = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
      lockWaitCount++;
    }
    _isComBBusy = true;

    try {
      int regAddress = channel - 1; 
      Uint8List data = Uint8List.fromList([
        deviceAddress,
        0x03, 
        (regAddress >> 8) & 0xFF, regAddress & 0xFF,
        0x00, 0x01 // 读取个数为 1
      ]);
      
      Uint8List frame = ModbusCrc.appendCRC16(data);
      _drainRx(_comB!);
      _comB!.write(frame);
      
      double? result;
      List<int> buffer = [];
      int waitCount = 0;
      
      while (waitCount < 10) { // 100ms max
        Uint8List chunk = _comB!.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
           final fullFrame = _extractFixedFrame(buffer, deviceAddress, 0x03, 7);
           if (fullFrame != null && fullFrame.length >= 5) {
             final int value = (fullFrame[3] << 8) | fullFrame[4];
             result = (value * rangeMax) / 10000.0;
             break;
           }
        }
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
      }
      
      if (result == null) {
         debugPrint('[SerialManager][WARN] readCurrentChannel timeout: ch=$channel');
      }
return result;
    } catch (e) {
      debugPrint('[SerialManager][ERROR] readCurrentChannel exception: $e');
      return null;
    } finally {
      await Future.delayed(const Duration(milliseconds: 10));
      _isComBBusy = false;
    }
  }

  // ============== 通用配置命令 ==============

  /// 向指派的总线设备发送通用修改指令 (功能码 0x06，写单个寄存器)
  /// bus: 'A'=电机总线, 'B'=采集器总线, 'C'=灯控总线
  Future<bool> sendConfigCommand(String bus, int deviceAddress, int regAddress, int value) async {
    SerialPort? port;
    if (bus == 'A') port = _comA;
    else if (bus == 'B') port = _comB;
    else if (bus == 'C') port = _comC;
    if (port == null || !port.isOpen) return false;

    // 获取对应的锁并带超时保护
    int lockWaitCount = 0;
    while ((bus == 'A' ? _isComABusy : bus == 'B' ? _isComBBusy : _isComCBusy)) {
      if (lockWaitCount > 100) {
        if (bus == 'A') _isComABusy = false;
        else if (bus == 'B') _isComBBusy = false;
        else _isComCBusy = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
      lockWaitCount++;
    }
    
    if (bus == 'A') _isComABusy = true;
    else if (bus == 'B') _isComBBusy = true;
    else _isComCBusy = true;

    try {
      Uint8List data = Uint8List.fromList([
        deviceAddress,
        0x06,
        (regAddress >> 8) & 0xFF, regAddress & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF
      ]);
      
      Uint8List frame = ModbusCrc.appendCRC16(data);
      _drainRx(port);
      port.write(frame);
      
      bool success = false;
      int waitCount = 0;
      List<int> buffer = [];
      
      while (waitCount < 25) { 
        Uint8List chunk = port.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
          if (_hasValidFixedFrame(buffer, deviceAddress, 0x06, 8)) {
              success = true;
              break;
           }
        }
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
      }
      
      if (!success) {
        debugPrint('[SerialManager][WARN] sendConfigCommand timeout: addr=$deviceAddress reg=$regAddress');
      }
      return success;
    } catch (e) {
      return false;
    } finally {
      await Future.delayed(const Duration(milliseconds: 10));
      if (bus == 'A') _isComABusy = false;
      else if (bus == 'B') _isComBBusy = false;
      else _isComCBusy = false;
    }
  }
}
