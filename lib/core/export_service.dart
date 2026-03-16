import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// 历史数据转 Excel 导出服务
class ExportService {
  /// 将查询结果导出为 Excel 文件，返回保存路径；失败返回 null
  static Future<String?> exportToExcel(
    List<Map<String, dynamic>> data,
    String label,
  ) async {
    try {
      var excel = Excel.createExcel();
      // 删除默认创建的 Sheet1，使用中文表名
      excel.rename('Sheet1', '数据记录');
      Sheet sheet = excel['数据记录'];

      // === 表头 ===
      final headers = [
        '采集时间', '数据类型', '批次ID', '通道/电机ID', '当前循环(圈)', '实测电流(A)',
      ];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      // 表头加粗样式
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

        // 报警行标红背景
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
      sheet.setColumnWidth(0, 22); // 时间
      sheet.setColumnWidth(1, 30); // 类型
      sheet.setColumnWidth(2, 28); // 批次ID
      sheet.setColumnWidth(3, 12); // 通道
      sheet.setColumnWidth(4, 14); // 循环
      sheet.setColumnWidth(5, 14); // 电流

      // === 文件保存 ===
      final docDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${docDir.path}\\MotorControl\\exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      // 文件名中的特殊字符替换，防止路径非法
      final safeLabel = label.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '${safeLabel}_$ts.xlsx';
      final filePath = '${exportDir.path}\\$fileName';

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        File(filePath).writeAsBytesSync(fileBytes);
        return filePath;
      }
      return null;
    } catch (e) {
      debugPrint('[ExportService][ERROR] Export failed: $e');
      return null;
    }
  }
}
