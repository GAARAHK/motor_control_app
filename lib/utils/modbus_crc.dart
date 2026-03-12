import 'dart:typed_data';

// 485 通信所需的校验辅助函数
class ModbusCrc {
  /// 计算 Modbus RTU 的 CRC16 校验码
  static int calculateCRC16(Uint8List data) {
    int crc = 0xFFFF;
    for (int i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc;
  }

  /// 为字节数组追加 CRC16，返回完整的帧
  static Uint8List appendCRC16(Uint8List data) {
    int crc = calculateCRC16(data);
    List<int> frame = List.from(data);
    // 低位在前，高位在后
    frame.add(crc & 0xFF);
    frame.add((crc >> 8) & 0xFF);
    return Uint8List.fromList(frame);
  }

  /// 验证接收到的数据帧 CRC 是否正确
  static bool verifyCRC16(Uint8List frame) {
    if (frame.length < 2) return false;
    Uint8List data = frame.sublist(0, frame.length - 2);
    int expectedCrc = calculateCRC16(data);
    int actualCrc = frame[frame.length - 2] | (frame[frame.length - 1] << 8);
    return expectedCrc == actualCrc;
  }
}
