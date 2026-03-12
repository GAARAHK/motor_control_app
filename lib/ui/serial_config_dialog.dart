import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../core/serial_manager.dart';

class SerialConfigDialog extends StatefulWidget {
  const SerialConfigDialog({Key? key}) : super(key: key);

  @override
  State<SerialConfigDialog> createState() => _SerialConfigDialogState();
}

class _SerialConfigDialogState extends State<SerialConfigDialog> {
  String? selectedComA;
  String? selectedComB;
  int _baudRate = 19200;
  int _parity = SerialPortParity.none;
  int _dataBits = 8;
  int _stopBits = 1;

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
    List<String> ports = SerialManager().availablePorts;
    if (selectedComA != null && !ports.contains(selectedComA)) selectedComA = null;
    if (selectedComB != null && !ports.contains(selectedComB)) selectedComB = null;
  }

  @override
  void dispose() {
    _deviceAddressCtrl.dispose();
    _actionValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (selectedComA == null || selectedComB == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择两个串口')));
      return;
    }
    bool success = await SerialManager().initPorts(
      selectedComA!, 
      selectedComB!,
      baudRate: _baudRate,
      dataBits: _dataBits,
      stopBits: _stopBits,
      parity: _parity,
    );
    setState(() {}); // 刷新转态
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('串口连接成功！')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('串口连接失败，可能被占用或设置无效！')));
    }
  }

  Future<void> _handleSendConfig() async {
    bool isComA = _targetBus == 'COM_A';
    int address = int.tryParse(_deviceAddressCtrl.text) ?? 1;
    int value = int.tryParse(_actionValueCtrl.text) ?? 0;
    int reg = 0;

    switch (_actionType) {
      case 'collector_address': reg = 0x0050; break; // 修改采集器地址
      case 'collector_baud': reg = 0x0051; break; // 修改采集器波特率 (0=4800,1=9600,2=19200...)
      case 'collector_parity': reg = 0x0052; break; // 修改采集器校验 (0=无,1=奇,2=偶)
      case 'motor_address': reg = 0x0032; break; // 修改单路电机控制器地址
      case 'motor_baud': reg = 0x0033; break; // 修改单路电机波特率 (0=4800,1=9600,3=19200...)
      case 'motor_mode': reg = 0x0097; break; // 设置电机工作模式 (M1=1, M34=34(0x22))
    }

    bool res = await SerialManager().sendConfigCommand(isComA, address, reg, value);
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
        width: 600,
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
                    const Text('总线绑定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    Row(
                      children: [
                        const Text('COM_A (电机控制总线): '),
                        const SizedBox(width: 8),
                        Expanded(child: DropdownButton<String>(
                          value: selectedComA,
                          isExpanded: true,
                          hint: const Text('未选择'),
                          items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => setState(() => selectedComA = val),
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('COM_B (电流采集总线): '),
                        const SizedBox(width: 8),
                        Expanded(child: DropdownButton<String>(
                          value: selectedComB,
                          isExpanded: true,
                          hint: const Text('未选择'),
                          items: ports.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => setState(() => selectedComB = val),
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('高级连接参数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    Row(
                      children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('波特率', style: TextStyle(fontSize: 12)),
                            DropdownButton<int>(
                              value: _baudRate,
                              isExpanded: true,
                              items: _baudOptions.map((e) => DropdownMenuItem(value: int.parse(e), child: Text(e))).toList(),
                              onChanged: (val) => setState(() => _baudRate = val!),
                            ),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('校验位', style: TextStyle(fontSize: 12)),
                            DropdownButton<int>(
                              value: _parity,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: SerialPortParity.none, child: Text('None (无)')),
                                DropdownMenuItem(value: SerialPortParity.odd, child: Text('Odd (奇)')),
                                DropdownMenuItem(value: SerialPortParity.even, child: Text('Even (偶)')),
                              ],
                              onChanged: (val) => setState(() => _parity = val!),
                            ),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('数据位/停止位', style: TextStyle(fontSize: 12)),
                            Text('$_dataBits 位 / $_stopBits 位', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        )),
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
                        ElevatedButton.icon(
                          icon: const Icon(Icons.link),
                          label: const Text('应用并连接'),
                          onPressed: _handleConnect,
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
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _targetBus = val!;
                                    if (_targetBus == 'COM_A') _actionType = 'motor_address';
                                    if (_targetBus == 'COM_B') _actionType = 'collector_address';
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
                                ] : const [
                                  DropdownMenuItem(value: 'motor_address', child: Text('修改设备地址 (Reg:0x0032)')),
                                  DropdownMenuItem(value: 'motor_baud', child: Text('修改波特率码 (Reg:0x0033)')),
                                  DropdownMenuItem(value: 'motor_mode', child: Text('修改工作模式 (Reg:0x0097)')),
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