import 'dart:async';
import 'dart:typed_data';
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

  int _baudRate = 19200;
  int _dataBits = 8;
  int _stopBits = 1;
  int _parity = SerialPortParity.none;

  // 使用 Completer 进行异步等待回调机制
  bool _isComABusy = false;
  bool _isComBBusy = false;

  /// 获取系统当前可用串口列表
  List<String> get availablePorts => SerialPort.availablePorts;

  /// 配置参数并尝试打开两路串口
  Future<bool> initPorts(String portAName, String portBName, {
    int baudRate = 19200, 
    int dataBits = 8, 
    int stopBits = 1, 
    int parity = SerialPortParity.none
  }) async {
    this.portAName = portAName;
    this.portBName = portBName;
    _baudRate = baudRate;
    _dataBits = dataBits;
    _stopBits = stopBits;
    _parity = parity;
    
    bool success = true;

    try {
      if (_comA != null && _comA!.isOpen) _comA!.close();
      _comA = SerialPort(portAName);
      if (_comA!.openReadWrite()) {
        _comA!.config = _getSpConfig();
      } else {
        success = false;
      }
    } catch (e) {
      print('Failed to open COM_A: $e');
      success = false;
    }

    try {
      if (_comB != null && _comB!.isOpen) _comB!.close();
      _comB = SerialPort(portBName);
      if (_comB!.openReadWrite()) {
         _comB!.config = _getSpConfig();
      } else {
        success = false;
      }
    } catch (e) {
      print('Failed to open COM_B: $e');
      success = false;
    }

    isConnected = success;
    return success;
  }

  SerialPortConfig _getSpConfig() {
    final conf = SerialPortConfig();
    conf.baudRate = _baudRate;
    conf.bits = _dataBits;
    conf.parity = _parity;
    conf.stopBits = _stopBits;
    return conf;
  }

  void closePorts() {
    if (_comA?.isOpen == true) _comA?.close();
    if (_comB?.isOpen == true) _comB?.close();
  }

  // ============== COM_A: 单路直流电机控制 ==============

  /// 向指定地址的电机发送控制指令：fwd(正转 0x01), rev(反转 0x02), stop(停止 0x00)
  Future<bool> sendMotorCommand(int motorAddress, String action) async {
    if (_comA == null || !_comA!.isOpen) return false;
    
    // 互斥锁，防止高并发导致 485 冲突
    while (_isComABusy) {
      await Future.delayed(const Duration(milliseconds: 10));
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
      // 等待硬件响应 (通常为原样返回)
      final reader = SerialPortReader(_comA!, timeout: 200);
      bool success = false;
      await for (final chunk in reader.stream) {
        if (chunk.isNotEmpty && ModbusCrc.verifyCRC16(chunk)) {
           // 指令回写检验成功
           success = true;
           break;
        }
      }
      reader.close();
      return success;
    } catch (e) {
      print('sendMotorCommand error: $e');
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

    while (_isComBBusy) {
      await Future.delayed(const Duration(milliseconds: 10));
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

      final reader = SerialPortReader(_comB!, timeout: 300);
      double? result;
      // 缓冲池，应对可能拆包的分段数据
      List<int> buffer = []; 
      
      await for (final chunk in reader.stream) {
        buffer.addAll(chunk);
        // 读取1个寄存器，返回帧长度 = 1(地址) + 1(功能码) + 1(数据长: 0x02) + 2(数据) + 2(CRC) = 7字节
        if (buffer.length >= 7) {
           Uint8List fullFrame = Uint8List.fromList(buffer);
           if (ModbusCrc.verifyCRC16(fullFrame)) {
              // 提取数据部分：01 03 02 [高位] [低位] CRC1 CRC2
              int value = (fullFrame[3] << 8) | fullFrame[4];
              // 通过规格换算电流/电压。文档公式：实际值 = 读数 * 量程 / 10000
              result = (value * rangeMax) / 10000.0;
           }
           break; 
        }
      }
      reader.close();
      return result;
    } catch (e) {
      print('readCurrent error: $e');
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

    // 获取对应的锁
    while (isComA ? _isComABusy : _isComBBusy) {
      await Future.delayed(const Duration(milliseconds: 10));
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

      final reader = SerialPortReader(port, timeout: 300);
      bool success = false;
      await for (final chunk in reader.stream) {
        if (chunk.isNotEmpty && ModbusCrc.verifyCRC16(chunk)) {
           success = true;
           break;
        }
      }
      reader.close();
      return success;
    } catch (e) {
      return false;
    } finally {
      await Future.delayed(const Duration(milliseconds: 10));
      if (isComA) _isComABusy = false; else _isComBBusy = false;
    }
  }
}
