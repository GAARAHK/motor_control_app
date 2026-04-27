import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/serial_manager.dart';

class SerialConfigDialog extends StatefulWidget {
  const SerialConfigDialog({Key? key}) : super(key: key);

  @override
  State<SerialConfigDialog> createState() => _SerialConfigDialogState();
}

class _SerialConfigDialogState extends State<SerialConfigDialog> {
  static const _kBaudRateAKey = 'serial_last_baud_rate_a';
  static const _kBaudRateBKey = 'serial_last_baud_rate_b';
  static const _kBaudRateCKey = 'serial_last_baud_rate_c';

  String? selectedComA;
  String? selectedComB;
  String? selectedComC;
  int _baudRateA = 19200;
  int _parityA = SerialPortParity.none;
  int _baudRateB = 19200;
  int _parityB = SerialPortParity.none;
  int _baudRateC = 19200;
  int _parityC = SerialPortParity.none;
  final int _dataBits = 8;
  final int _stopBits = 1;

  // 高级配置参数
  bool _isAdvancedVisible = false;
  String _targetBus = 'COM_B'; // 'COM_A' or 'COM_B'
  TextEditingController _deviceAddressCtrl = TextEditingController(text: '1');
  String _actionType = 'collector_address';
  TextEditingController _actionValueCtrl = TextEditingController(text: '2');

  final List<String> _baudOptions = ['4800', '9600', '14400', '19200', '38400', '115200'];

  @override
  void initState() {
    super.initState();
    selectedComA = SerialManager().portAName;
    selectedComB = SerialManager().portBName;
    selectedComC = SerialManager().portCName;
    List<String> ports = SerialManager().availablePorts;
    if (selectedComA != null && !ports.contains(selectedComA)) selectedComA = null;
    if (selectedComB != null && !ports.contains(selectedComB)) selectedComB = null;
    if (selectedComC != null && !ports.contains(selectedComC)) selectedComC = null;
    _loadLastBaudRates();
  }

  Future<void> _loadLastBaudRates() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedA = prefs.getInt(_kBaudRateAKey);
    final int? savedB = prefs.getInt(_kBaudRateBKey);
    final int? savedC = prefs.getInt(_kBaudRateCKey);
    final Set<int> validRates = _baudOptions.map(int.parse).toSet();

    if (!mounted) return;
    setState(() {
      if (savedA != null && validRates.contains(savedA)) {
        _baudRateA = savedA;
      }
      if (savedB != null && validRates.contains(savedB)) {
        _baudRateB = savedB;
      }
      if (savedC != null && validRates.contains(savedC)) {
        _baudRateC = savedC;
      }
    });
  }

  Future<void> _saveLastBaudRates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBaudRateAKey, _baudRateA);
    await prefs.setInt(_kBaudRateBKey, _baudRateB);
    await prefs.setInt(_kBaudRateCKey, _baudRateC);
  }

  @override
  void dispose() {
    _deviceAddressCtrl.dispose();
    _actionValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (selectedComA == null || selectedComB == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择 COM_A 和 COM_B 串口')));
      return;
    }
    bool success = await SerialManager().initPorts(
      selectedComA!,
      selectedComB!,
      selectedComC, // 可为 null，表示不启用灯控总线
      baudRateA: _baudRateA,
      dataBitsA: _dataBits,
      stopBitsA: _stopBits,
      parityA: _parityA,
      baudRateB: _baudRateB,
      dataBitsB: _dataBits,
      stopBitsB: _stopBits,
      parityB: _parityB,
      baudRateC: _baudRateC,
      dataBitsC: _dataBits,
      stopBitsC: _stopBits,
      parityC: _parityC,
    );
    if (success) {
      await _saveLastBaudRates();
    }
    setState(() {}); // 刷新转态
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('串口连接成功！')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('串口连接失败，可能被占用或设置无效！')));
    }
  }

  void _handleDisconnect() {
    SerialManager().closePorts();
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已断开串口连接。')));
  }

  Future<void> _handleSendConfig() async {
    bool isComA = _targetBus == 'COM_A';
    bool isComC = _targetBus == 'COM_C';
    int address = int.tryParse(_deviceAddressCtrl.text) ?? 1;
    int value = int.tryParse(_actionValueCtrl.text) ?? 0;
    int reg = 0;

    switch (_actionType) {
      case 'collector_address': reg = 0x0050; break;
      case 'collector_baud': reg = 0x0051; break;
      case 'collector_parity': reg = 0x0052; break;
      case 'motor_address': reg = 0x0032; break;
      case 'motor_baud': reg = 0x0033; break;
      case 'motor_mode': reg = 0x0097; break;
      case 'light_address': reg = 0x0032; break;
      case 'light_baud': reg = 0x0033; break;
    }

    final String bus = isComA ? 'A' : isComC ? 'C' : 'B';
    bool res = await SerialManager().sendConfigCommand(bus, address, reg, value);
    if (!mounted) return;
    if (res) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('指令发送并验证成功！')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('指令发送失败或未得到确认回复！')));
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> ports = SerialManager().availablePorts;
    return AlertDialog(
      title: const Text('串口与设备配置面板', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 750,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ====== 1. 基础连接部分 ======
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('总线绑定与参数配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    Row(
                      children: [
                        const SizedBox(
                          width: 100,
                          child: Text('COM_A (电机):', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButton<String>(
                            value: selectedComA,
                            isExpanded: true,
                            hint: const Text('未选择'),
                            items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) => setState(() => selectedComA = val),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('波特率:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _baudRateA,
                            isExpanded: true,
                            items: _baudOptions.map((e) => DropdownMenuItem(value: int.parse(e), child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _baudRateA = val!),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('校验:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _parityA,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(value: SerialPortParity.none, child: Text('无(None)')),
                              DropdownMenuItem(value: SerialPortParity.odd, child: Text('奇(Odd)')),
                              DropdownMenuItem(value: SerialPortParity.even, child: Text('偶(Even)')),
                            ],
                            onChanged: (val) => setState(() => _parityA = val!),
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 100,
                          child: Text('COM_B (采集):', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButton<String>(
                            value: selectedComB,
                            isExpanded: true,
                            hint: const Text('未选择'),
                            items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) => setState(() => selectedComB = val),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('波特率:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _baudRateB,
                            isExpanded: true,
                            items: _baudOptions.map((e) => DropdownMenuItem(value: int.parse(e), child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _baudRateB = val!),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('校验:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _parityB,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(value: SerialPortParity.none, child: Text('无(None)')),
                              DropdownMenuItem(value: SerialPortParity.odd, child: Text('奇(Odd)')),
                              DropdownMenuItem(value: SerialPortParity.even, child: Text('偶(Even)')),
                            ],
                            onChanged: (val) => setState(() => _parityB = val!),
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 100,
                          child: Text('COM_C (灯控)\n可选:', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          flex: 3,
                          child: DropdownButton<String>(
                            value: selectedComC,
                            isExpanded: true,
                            hint: const Text('未选择'),
                            items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) => setState(() => selectedComC = val),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('波特率:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _baudRateC,
                            isExpanded: true,
                            items: _baudOptions.map((e) => DropdownMenuItem(value: int.parse(e), child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _baudRateC = val!),
                          )
                        ),
                        const SizedBox(width: 16),
                        const Text('校验:'),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButton<int>(
                            value: _parityC,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(value: SerialPortParity.none, child: Text('无(None)')),
                              DropdownMenuItem(value: SerialPortParity.odd, child: Text('奇(Odd)')),
                              DropdownMenuItem(value: SerialPortParity.even, child: Text('偶(Even)')),
                            ],
                            onChanged: (val) => setState(() => _parityC = val!),
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('系统固定参数:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 16),
                        Text('数据位: $_dataBits 位   停止位: $_stopBits 位', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          SerialManager().isConnected ? '● 当前串口已建立连接' : '○ 当前串口未建立/断开',
                          style: TextStyle(
                            color: SerialManager().isConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            if (SerialManager().isConnected)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.link_off, color: Colors.orange),
                                label: const Text('断开连接', style: TextStyle(color: Colors.orange)),
                                onPressed: _handleDisconnect,
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.link),
                              label: const Text('应用并连接'),
                              onPressed: _handleConnect,
                            ),
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ====== 2. 设备高级指令配置部分 ======
              InkWell(
                onTap: () {
                  setState(() { _isAdvancedVisible = !_isAdvancedVisible; });
                },
                child: Row(
                  children: [
                    Icon(_isAdvancedVisible ? Icons.arrow_drop_down : Icons.arrow_right, color: Colors.blue),
                    const Text('单机设备基础参数配置 (需先建立连接)', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (_isAdvancedVisible) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.blue.shade100), color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('目标总线', style: TextStyle(fontSize: 12)),
                              DropdownButton<String>(
                                value: _targetBus,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'COM_B', child: Text('COM_B (24路采集器)')),
                                  DropdownMenuItem(value: 'COM_A', child: Text('COM_A (电机控制器)')),
                                  DropdownMenuItem(value: 'COM_C', child: Text('COM_C (灯控模块)')),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _targetBus = val!;
                                    if (_targetBus == 'COM_A') _actionType = 'motor_address';
                                    if (_targetBus == 'COM_B') _actionType = 'collector_address';
                                    if (_targetBus == 'COM_C') _actionType = 'light_address';
                                  });
                                },
                              ),
                            ],
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('目标从机地址', style: TextStyle(fontSize: 12)),
                              TextField(
                                controller: _deviceAddressCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(isDense: true),
                              ),
                            ],
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(flex: 2, child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('下发指令类别 (Hex: 06单写)', style: TextStyle(fontSize: 12)),
                              DropdownButton<String>(
                                value: _actionType,
                                isExpanded: true,
                                items: _targetBus == 'COM_B' ? const [
                                  DropdownMenuItem(value: 'collector_address', child: Text('修改设备地址 (Reg:0x0050)')),
                                  DropdownMenuItem(value: 'collector_baud', child: Text('修改波特率码 (Reg:0x0051)')),
                                  DropdownMenuItem(value: 'collector_parity', child: Text('修改校验位码 (Reg:0x0052)')),
                                ] : _targetBus == 'COM_A' ? const [
                                  DropdownMenuItem(value: 'motor_address', child: Text('修改设备地址 (Reg:0x0032)')),
                                  DropdownMenuItem(value: 'motor_baud', child: Text('修改波特率码 (Reg:0x0033)')),
                                  DropdownMenuItem(value: 'motor_mode', child: Text('修改工作模式 (Reg:0x0097)')),
                                ] : const [
                                  DropdownMenuItem(value: 'light_address', child: Text('修改设备地址 (Reg:0x0032)')),
                                  DropdownMenuItem(value: 'light_baud', child: Text('修改波特率码 (Reg:0x0033)')),
                                ],
                                onChanged: (val) => setState(() => _actionType = val!),
                              ),
                            ],
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('设定数值 (10进制)', style: TextStyle(fontSize: 12)),
                              TextField(
                                controller: _actionValueCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(isDense: true),
                              ),
                            ],
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                          onPressed: SerialManager().isConnected ? _handleSendConfig : null,
                          icon: const Icon(Icons.send),
                          label: const Text('下发修改并要求确认'),
                        ),
                      )
                    ],
                  ),
                )
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () { 
            Navigator.pop(context);
          },
          child: const Text('关闭'),
        ),
      ],
    );
  }
}