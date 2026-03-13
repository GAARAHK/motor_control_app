import 'package:flutter/material.dart';
import '../core/database_helper.dart';

// 扫码记录查询与电流曲线报表视图
class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  void _searchLogs() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await DatabaseHelper.instance.queryLogsByQRCode(keyword);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      print('Query Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据追溯查询'),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 顶部搜索栏
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: '输入设备二维码或条码追溯测试流水',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                    onSubmitted: (_) => _searchLogs(),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _searchLogs,
                  icon: const Icon(Icons.search),
                  label: const Text('查询记录'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),
            
            // 数据表格展示
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _searchResults.isEmpty 
                  ? const Center(
                      child: Text('未找到该码值对应的数据', style: TextStyle(color: Colors.grey)),
                    )
                  : Card(
                      elevation: 2,
                      child: ListView(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.resolveWith(
                                (states) => Colors.grey.shade200,
                              ),
                              columns: const [
                                DataColumn(label: Text('采集时间')),
                                DataColumn(label: Text('批次ID')),
                                DataColumn(label: Text('通道/电机ID')),
                                DataColumn(label: Text('当前循环(圈)')),
                                DataColumn(label: Text('实测电流(A)')),
                              ],
                              rows: _searchResults.map((row) {
                                // 提取并解析时间，做简易截取
                                String timeStr = row['timestamp'].toString();
                                if (timeStr.length > 19) {
                                  timeStr = timeStr.substring(0, 19).replaceAll('T', ' ');
                                }
                                return DataRow(cells: [
                                  DataCell(Text(timeStr)),
                                  DataCell(Text(row['batch_uuid'].toString())),
                                  DataCell(Text('通道 ${row['motor_id']}')),
                                  DataCell(Text(row['loop_count'].toString())),
                                  DataCell(Text(
                                    '${row['read_current']} A',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
            )
          ],
        ),
      ),
    );
  }
}
