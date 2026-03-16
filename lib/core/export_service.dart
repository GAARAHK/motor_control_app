import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

// 历史数据转 Excel 导出服务
class ExportService {
  /// 将查询结果写入指定路径的 Excel 文件，成功返回 savePath，失败返回 null。
  /// [savePath] 由调用方通过文件选择对话框获取（含完整路径与文件名）
  static Future<String?> exportToExcel(
    List<Map<String, dynamic>> data,
    String savePath,
  ) async {
    try {
      var excel = Excel.createExcel();
      excel.rename('Sheet1', '数据记录');
      Sheet sheet = excel['数据记录'];

      // === 表头 ===
      final headers = [
        '采集时间', '数据类型', '批次ID', '通道/电机ID', '当前循环(圈)', '实测电流(A)',
      ];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      // 表头蓝底白字加粗
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      // === 数据行 ===
      for (var row in data) {
        String timeStr = row['timestamp'].toString();
        if (timeStr.length > 19) {
          timeStr = timeStr.substring(0, 19).replaceAll('T', ' ');
        }
        final isAlarm = row['log_type'].toString().contains('报警');
        final loopVal = row['loop_count'] == -1 ? '-' : row['loop_count'].toString();
        final current = double.tryParse(row['read_current'].toString()) ?? 0.0;

        sheet.appendRow([
          TextCellValue(timeStr),
          TextCellValue(row['log_type'].toString()),
          TextCellValue(row['batch_uuid'].toString()),
          TextCellValue('CH-${row['motor_id'].toString().padLeft(2, '0')}'),
          TextCellValue(loopVal),
          DoubleCellValue(current),
        ]);

        // 报警行标红
        if (isAlarm) {
          final rowIdx = sheet.maxRows - 1;
          for (int col = 0; col < headers.length; col++) {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx));
            cell.cellStyle = CellStyle(
              backgroundColorHex: ExcelColor.fromHexString('#FFEBEE'),
              fontColorHex: ExcelColor.fromHexString('#C62828'),
            );
          }
        }
      }

      // 设置列宽
      sheet.setColumnWidth(0, 22);
      sheet.setColumnWidth(1, 30);
      sheet.setColumnWidth(2, 28);
      sheet.setColumnWidth(3, 12);
      sheet.setColumnWidth(4, 14);
      sheet.setColumnWidth(5, 14);

      // === 写入文件 ===
      final fileBytes = excel.encode();
      if (fileBytes != null) {
        // 确保父目录存在
        final parent = File(savePath).parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await File(savePath).writeAsBytes(fileBytes);
        return savePath;
      }
      return null;
    } catch (e) {
      debugPrint('[ExportService][ERROR] Export failed: $e');
      return null;
    }
  }

  /// 根据当前时间生成默认文件名，格式：查询记录_YYYYMMDD_HHmmss.xlsx
  static String generateFileName() {
    final now = DateTime.now();
    final ts =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return '查询记录_$ts.xlsx';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
