import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/database_helper.dart';
import '../core/export_service.dart';

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
  bool _hasSearched = false;
  bool _isExporting = false;

  // 高级筛选条件
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _logType = 'all'; // 'all' | 'normal' | 'alarm'
  int? _motorId; // null = 全部通道

  // ── 日期选择 ────────────────────────────────────────────────
  Future<void> _pickDate(bool isFrom) async {
    final init = isFrom ? (_dateFrom ?? DateTime.now()) : (_dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: isFrom ? '选择开始日期' : '选择结束日期',
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _logType = 'all';
      _motorId = null;
    });
  }

  // ── 查询 ───────────────────────────────────────────────────
  Future<void> _searchLogs() async {
    final keyword = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });
    try {
      final results = await DatabaseHelper.instance.queryLogsAdvanced(
        qrCode: keyword.isEmpty ? null : keyword,
        logType: _logType,
        dateFrom: _dateFrom != null ? _formatDate(_dateFrom!) : null,
        dateTo: _dateTo != null ? _formatDate(_dateTo!) : null,
        motorId: _motorId,
      );
      setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('[HistoryPage] 查询失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 导出 ───────────────────────────────────────────────────
  Future<void> _exportResults() async {
    if (_searchResults.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final label = _searchController.text.trim().isEmpty
          ? 'all'
          : _searchController.text.trim();
      final path = await ExportService.exportToExcel(_searchResults, label);
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导出至: $path'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '复制路径',
            textColor: Colors.white,
            onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('导出失败，请检查磁盘空间或写入权限'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final normalCount =
        _searchResults.where((r) => !r['log_type'].toString().contains('报警')).length;
    final alarmCount = _searchResults.length - normalCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据追溯查询'),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          if (_searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _isExporting
                  ? const Padding(
                      padding: EdgeInsets.all(14.0),
                      child: SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : ElevatedButton.icon(
                      onPressed: _exportResults,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text('导出 Excel（${_searchResults.length} 条）'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ──────────────────────────────────────────────────
            // 查询条件面板
            // ──────────────────────────────────────────────────
            Card(
              elevation: 0,
              color: Colors.blueGrey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：二维码 + 数据类型 + 通道
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: '产品二维码（留空查全部）',
                              hintText: '扫码或手动输入...',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.qr_code_scanner),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _searchLogs(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 数据类型下拉
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _logType,
                            decoration: InputDecoration(
                              labelText: '数据类型',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('全部记录')),
                              DropdownMenuItem(
                                  value: 'normal', child: Text('仅正常记录')),
                              DropdownMenuItem(
                                  value: 'alarm', child: Text('仅报警记录')),
                            ],
                            onChanged: (v) =>
                                setState(() => _logType = v ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 通道筛选下拉
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int?>(
                            value: _motorId,
                            decoration: InputDecoration(
                              labelText: '通道筛选',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                  value: null, child: Text('全部通道')),
                              ...List.generate(
                                25,
                                (i) => DropdownMenuItem<int?>(
                                  value: i + 1,
                                  child: Text(
                                      'CH-${(i + 1).toString().padLeft(2, '0')}'),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => _motorId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 第二行：日期范围 + 重置 + 查询
                    Row(
                      children: [
                        // 开始日期
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(true),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: '开始日期',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_dateFrom != null)
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _dateFrom = null),
                                        child: const Icon(Icons.clear,
                                            size: 16, color: Colors.grey),
                                      ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              child: Text(
                                _dateFrom != null
                                    ? _formatDate(_dateFrom!)
                                    : '不限',
                                style: TextStyle(
                                    color: _dateFrom != null
                                        ? Colors.black87
                                        : Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('至',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        // 结束日期
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(false),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: '结束日期',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_dateTo != null)
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _dateTo = null),
                                        child: const Icon(Icons.clear,
                                            size: 16, color: Colors.grey),
                                      ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              child: Text(
                                _dateTo != null ? _formatDate(_dateTo!) : '不限',
                                style: TextStyle(
                                    color: _dateTo != null
                                        ? Colors.black87
                                        : Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重置'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _searchLogs,
                          icon: const Icon(Icons.search),
                          label: const Text('查询'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ──────────────────────────────────────────────────
            // 结果统计栏
            // ──────────────────────────────────────────────────
            if (_hasSearched && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _searchResults.isEmpty
                      ? '未找到符合条件的数据'
                      : '共 ${_searchResults.length} 条记录'
                          '  ·  正常: $normalCount'
                          '  ·  报警: $alarmCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // ──────────────────────────────────────────────────
            // 数据表格
            // ──────────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasSearched
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.manage_search,
                                  size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('请设置查询条件后点击「查询」',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 15)),
                            ],
                          ),
                        )
                      : _searchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 72, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text('未找到符合条件的数据',
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 15)),
                                  const SizedBox(height: 8),
                                  Text('请调整筛选条件，或该产品尚未进行测试',
                                      style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12)),
                                ],
                              ),
                            )
                          : Card(
                              elevation: 2,
                              child: ListView(
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor:
                                          MaterialStateProperty.resolveWith(
                                        (states) => Colors.grey.shade200,
                                      ),
                                      columns: const [
                                        DataColumn(label: Text('采集时间')),
                                        DataColumn(label: Text('数据类型')),
                                        DataColumn(label: Text('批次ID')),
                                        DataColumn(label: Text('通道/电机')),
                                        DataColumn(label: Text('当前循环(圈)')),
                                        DataColumn(label: Text('实测电流(A)')),
                                      ],
                                      rows: _searchResults.map((row) {
                                        String timeStr =
                                            row['timestamp'].toString();
                                        if (timeStr.length > 19) {
                                          timeStr = timeStr
                                              .substring(0, 19)
                                              .replaceAll('T', ' ');
                                        }
                                        final isAlarm = row['log_type']
                                            .toString()
                                            .contains('报警');
                                        final current = double.tryParse(
                                                row['read_current']
                                                    .toString()) ??
                                            0.0;
                                        return DataRow(
                                          color:
                                              MaterialStateProperty.resolveWith(
                                            (states) => isAlarm
                                                ? Colors.red.shade50
                                                : null,
                                          ),
                                          cells: [
                                            DataCell(Text(timeStr)),
                                            DataCell(Text(
                                              row['log_type'].toString(),
                                              style: TextStyle(
                                                color: isAlarm
                                                    ? Colors.red
                                                    : Colors.green,
                                                fontWeight: isAlarm
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            )),
                                            DataCell(Text(
                                                row['batch_uuid'].toString())),
                                            DataCell(Text(
                                                'CH-${row['motor_id'].toString().padLeft(2, '0')}')),
                                            DataCell(Text(
                                                row['loop_count'] == -1
                                                    ? '-'
                                                    : row['loop_count']
                                                        .toString())),
                                            DataCell(Text(
                                              '${current.toStringAsFixed(3)} A',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isAlarm
                                                    ? Colors.red
                                                    : Colors.blue,
                                              ),
                                            )),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
