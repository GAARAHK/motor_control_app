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

  String? portAName;
  String? portBName;
  bool isConnected = false;

  int _baudRateA = 19200;
  int _dataBitsA = 8;
  int _stopBitsA = 1;
  int _parityA = SerialPortParity.none;

  int _baudRateB = 19200;
  int _dataBitsB = 8;
  int _stopBitsB = 1;
  int _parityB = SerialPortParity.none;

  // 使用 Completer 进行异步等待回调机制
  bool _isComABusy = false;
  bool _isComBBusy = false;

  /// 获取系统当前可用串口列表
  List<String> get availablePorts => SerialPort.availablePorts;

  /// 配置参数并尝试打开两路串口
  Future<bool> initPorts(String portAName, String portBName, {
    int baudRateA = 19200, 
    int dataBitsA = 8, 
    int stopBitsA = 1, 
    int parityA = SerialPortParity.none,
    int baudRateB = 19200, 
    int dataBitsB = 8, 
    int stopBitsB = 1, 
    int parityB = SerialPortParity.none
  }) async {
    this.portAName = portAName;
    this.portBName = portBName;
    _baudRateA = baudRateA;
    _dataBitsA = dataBitsA;
    _stopBitsA = stopBitsA;
    _parityA = parityA;

    _baudRateB = baudRateB;
    _dataBitsB = dataBitsB;
    _stopBitsB = stopBitsB;
    _parityB = parityB;
    
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

  void closePorts() {
    _isComABusy = false;
    _isComBBusy = false;
    if (_comA?.isOpen == true) _comA?.close();
    if (_comB?.isOpen == true) _comB?.close();
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
      
      _comA!.write(frame);
      
      bool success = false;
      int waitCount = 0;
      List<int> buffer = [];
      
      while (waitCount < 10) { // 最多等 10 x 10ms = 100ms
        Uint8List chunk = _comA!.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
           if (ModbusCrc.verifyCRC16(Uint8List.fromList(buffer))) {
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

  // ============== COM_B: 24路全隔离交直流采集器 ==============

  /// 读取指定路(通道)的实际电流值
  /// 注意这里通道1 对应寄存器 0x0000, 故寄存器地址 = channel - 1
  /// 由于采集模块自身地址固定（假设为 1），可配置参数
  Future<double?> readCurrentChannel(int channel, {int deviceAddress = 1, double rangeMax = 60.0}) async {
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
      _comB!.write(frame);
      
      double? result;
      List<int> buffer = [];
      int waitCount = 0;
      
      while (waitCount < 10) { // 100ms max
        Uint8List chunk = _comB!.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
           if (buffer.length >= 7) {
             Uint8List fullFrame = Uint8List.fromList(buffer);
             if (ModbusCrc.verifyCRC16(fullFrame)) {
                int value = (fullFrame[3] << 8) | fullFrame[4];
                result = (value * rangeMax) / 10000.0;
             }
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
  /// isComA: true为电机总线，false为采集器总线
  Future<bool> sendConfigCommand(bool isComA, int deviceAddress, int regAddress, int value) async {
    SerialPort? port = isComA ? _comA : _comB;
    if (port == null || !port.isOpen) return false;

    // 获取对应的锁并带超时保护
    int lockWaitCount = 0;
    while (isComA ? _isComABusy : _isComBBusy) {
      if (lockWaitCount > 100) {
        if (isComA) _isComABusy = false;
        else _isComBBusy = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
      lockWaitCount++;
    }
    
    if (isComA) {
      _isComABusy = true;
    } else {
      _isComBBusy = true;
    }

    try {
      Uint8List data = Uint8List.fromList([
        deviceAddress,
        0x06,
        (regAddress >> 8) & 0xFF, regAddress & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF
      ]);
      
      Uint8List frame = ModbusCrc.appendCRC16(data);
      port.write(frame);
      
      bool success = false;
      int waitCount = 0;
      List<int> buffer = [];
      
      while (waitCount < 25) { 
        Uint8List chunk = port.read(128, timeout: 10);
        if (chunk.isNotEmpty) {
           buffer.addAll(chunk);
           if (ModbusCrc.verifyCRC16(Uint8List.fromList(buffer))) {
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
      if (isComA) _isComABusy = false; else _isComBBusy = false;
    }
  }
}
