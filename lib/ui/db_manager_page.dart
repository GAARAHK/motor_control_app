import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/database_helper.dart';

// SQLite 数据库管理页面（输入密码后才可进入）
class DbManagerPage extends StatefulWidget {
  const DbManagerPage({Key? key}) : super(key: key);

  @override
  State<DbManagerPage> createState() => _DbManagerPageState();
}

class _DbManagerPageState extends State<DbManagerPage> {
  Map<String, int> _stats = {};
  String _dbPath = '';
  String _dbSize = '计算中...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ── 刷新概览数据 ───────────────────────────────────────────
  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final stats = await DatabaseHelper.instance.getTableStats();
      final path = await DatabaseHelper.instance.getDatabaseFilePath();
      String sizeStr = '未知';
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        if (bytes < 1024) {
          sizeStr = '$bytes B';
        } else if (bytes < 1024 * 1024) {
          sizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
        } else {
          sizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
        }
      }
      setState(() {
        _stats = stats;
        _dbPath = path;
        _dbSize = sizeStr;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 备份数据库 ─────────────────────────────────────────────
  Future<void> _backupDatabase() async {
    final now = DateTime.now();
    final ts =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '选择备份保存位置',
      fileName: 'motor_control_backup_$ts.db',
      type: FileType.any,
      lockParentWindow: true,
    );
    if (savePath == null) return;

    try {
      await File(_dbPath).copy(savePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('备份成功: $savePath'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '复制路径',
          textColor: Colors.white,
          onPressed: () => Clipboard.setData(ClipboardData(text: savePath)),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('备份失败: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── 清空指定表（带二次确认）──────────────────────────────────
  Future<void> _clearTable({
    required String tableKey,
    required String displayName,
    String? extraTable,
    String? extraName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
            const SizedBox(width: 8),
            const Text('危险操作确认'),
          ],
        ),
        content: Text(
          '即将永久删除「$displayName」${extraName != null ? '和「$extraName」' : ''}中的所有数据。\n\n此操作不可撤销，确认继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DatabaseHelper.instance.clearTable(tableKey);
      if (extraTable != null) {
        await DatabaseHelper.instance.clearTable(extraTable);
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('「$displayName」${extraName != null ? '和「$extraName」' : ''}已清空'),
        backgroundColor: Colors.orange.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('操作失败: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// 清空全部运行数据（批次 + 采集点 + 报警）
  Future<void> _clearAllOperationalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.dangerous_outlined, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('清空所有运行数据'),
          ],
        ),
        content: const Text(
          '将同时清空「批次记录」「正常采集点」「报警记录」三张表中的全部数据。\n\n此操作不可撤销，请确认已提前备份！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('我已备份，确认清空全部'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DatabaseHelper.instance.clearTable('motor_run_history');
      await DatabaseHelper.instance.clearTable('current_logs');
      await DatabaseHelper.instance.clearTable('alarm_logs');
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('所有运行数据已清空'),
        backgroundColor: Colors.deepOrange.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('操作失败: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库管理'),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新统计',
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final availW = constraints.maxWidth;
                // 统计卡片列数：>=680 -> 4列，>=360 -> 2列，否则1列
                final statCols = availW >= 680 ? 4 : availW >= 360 ? 2 : 1;
                final statCardW =
                    (availW - 40 - (statCols - 1) * 12) / statCols;
                // 危险卡片宽度 clamp 在 200~280 之间
                final dangerCardW =
                    ((availW - 40 - 12) / 2).clamp(200.0, 280.0);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ───────────────────────────────────
                      // 数据概览
                      // ───────────────────────────────────
                      _sectionTitle('数据概览', Icons.bar_chart_rounded),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statCard('批次运行记录',
                              _stats['motor_run_history'] ?? 0,
                              Icons.play_circle_outline, Colors.blue,
                              statCardW),
                          _statCard('正常采集数据点',
                              _stats['current_logs'] ?? 0,
                              Icons.show_chart, Colors.green, statCardW),
                          _statCard('报警触发记录',
                              _stats['alarm_logs'] ?? 0,
                              Icons.warning_amber_outlined, Colors.red,
                              statCardW),
                          _statCard('工况模板数',
                              _stats['work_mode_templates'] ?? 0,
                              Icons.rule_folder_outlined, Colors.orange,
                              statCardW),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ───────────────────────────────────
                      // 数据库文件信息
                      // ───────────────────────────────────
                      _sectionTitle('数据库文件信息', Icons.storage_rounded),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: Colors.blueGrey.shade50,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.folder_open,
                                      color: Colors.blueGrey.shade400,
                                      size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _dbPath,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13),
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '文件大小: $_dbSize',
                                    style: TextStyle(
                                        color: Colors.blueGrey.shade500,
                                        fontSize: 12),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => Clipboard.setData(
                                        ClipboardData(text: _dbPath)),
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: const Text('复制路径'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ───────────────────────────────────
                      // 数据备份
                      // ───────────────────────────────────
                      _sectionTitle('数据备份', Icons.backup_rounded),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: Colors.green.shade50,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.cloud_download_outlined,
                                      color: Colors.green.shade600, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '导出完整数据库备份',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '将整个 .db 文件复制到指定位置，包含所有表和数据。可用于迁移或恢复。',
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: _backupDatabase,
                                  icon: const Icon(Icons.save_alt),
                                  label: const Text('选择路径并备份'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ───────────────────────────────────
                      // 危险操作区
                      // ───────────────────────────────────
                      _sectionTitle('数据清理（危险区域）', Icons.delete_forever,
                          color: Colors.red.shade700),
                      const SizedBox(height: 4),
                      Text(
                        '以下操作将永久删除数据库中的记录，无法恢复，请确认已备份后再操作。',
                        style: TextStyle(
                            color: Colors.red.shade400, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _dangerCard(
                            title: '清空正常采集数据',
                            description: '删除 current_logs 表全部记录',
                            count: _stats['current_logs'] ?? 0,
                            width: dangerCardW,
                            onPressed: () => _clearTable(
                              tableKey: 'current_logs',
                              displayName: '正常采集数据',
                            ),
                          ),
                          _dangerCard(
                            title: '清空报警记录',
                            description: '删除 alarm_logs 表全部记录',
                            count: _stats['alarm_logs'] ?? 0,
                            width: dangerCardW,
                            onPressed: () => _clearTable(
                              tableKey: 'alarm_logs',
                              displayName: '报警记录',
                            ),
                          ),
                          _dangerCard(
                            title: '清空批次记录',
                            description: '删除 motor_run_history 表全部记录',
                            count: _stats['motor_run_history'] ?? 0,
                            width: dangerCardW,
                            onPressed: () => _clearTable(
                              tableKey: 'motor_run_history',
                              displayName: '批次运行记录',
                            ),
                          ),
                          _dangerCard(
                            title: '清空工况模板',
                            description: '删除 work_mode_templates 表全部记录',
                            count: _stats['work_mode_templates'] ?? 0,
                            width: dangerCardW,
                            onPressed: () => _clearTable(
                              tableKey: 'work_mode_templates',
                              displayName: '工况模板',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _clearAllOperationalData,
                          icon: Icon(Icons.delete_sweep,
                              color: Colors.red.shade700),
                          label: Text(
                            '清空全部运行数据（批次 + 采集点 + 报警）',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red.shade300),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
    );
  }
  // ── 小部件构建器 ──────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon,
      {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.blueGrey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.blueGrey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, int count, IconData icon, Color color,
      double width) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.07),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withOpacity(0.2))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: Colors.blueGrey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dangerCard({
    required String title,
    required String description,
    required int count,
    required double width,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(description,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              '当前 $count 条记录',
              style: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('清空此表'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

