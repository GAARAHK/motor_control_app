import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// SQLite分表建表与增删改查
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('motor_control.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Windows 环境下初始化 FFI
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    
    // 获取系统的文档目录
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDocDir.path, 'MotorControl', filePath);
    
    // 如果目录不存在则创建
    final dir = Directory(dirname(dbPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3, // v3: 新增查询索引优化
        onCreate: _createDB,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('DROP TABLE IF EXISTS work_mode_templates');
            await db.execute('''
              CREATE TABLE work_mode_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                steps_json TEXT NOT NULL,
                target_loops INTEGER NOT NULL,
                collect_interval INTEGER NOT NULL,
                limit_upper REAL NOT NULL,
                limit_lower REAL NOT NULL
              )
            ''');
          }
          if (oldVersion < 3) {
            // 为已有数据库补充查询索引
            await db.execute('CREATE INDEX IF NOT EXISTS idx_current_logs_qr ON current_logs(qr_code)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_current_logs_batch ON current_logs(batch_uuid)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_alarm_logs_qr ON alarm_logs(qr_code)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_run_history_qr ON motor_run_history(qr_code)');
          }
        }
      ),
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. 系统参数配置表
    await db.execute('''
      CREATE TABLE settings_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT UNIQUE NOT NULL,
        value TEXT NOT NULL
      )
    ''');

    // 2. 预设工况模板表
    await db.execute('''
      CREATE TABLE work_mode_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        steps_json TEXT NOT NULL,
        target_loops INTEGER NOT NULL,
        collect_interval INTEGER NOT NULL,
        limit_upper REAL NOT NULL,
        limit_lower REAL NOT NULL
      )
    ''');

    // 3. 电机运行主记录（批次表）
    await db.execute('''
      CREATE TABLE motor_run_history (
        batch_uuid TEXT PRIMARY KEY,
        motor_id INTEGER NOT NULL,
        qr_code TEXT NOT NULL,
        template_id INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_status TEXT NOT NULL
      )
    ''');

    // 4. 电流采集日志流水表
    await db.execute('''
      CREATE TABLE current_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_uuid TEXT NOT NULL,
        motor_id INTEGER NOT NULL,
        qr_code TEXT NOT NULL,
        loop_count INTEGER NOT NULL,
        read_current REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // 5. 报警记录追溯表
    await db.execute('''
      CREATE TABLE alarm_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        qr_code TEXT NOT NULL,
        motor_id INTEGER NOT NULL,
        trip_current REAL NOT NULL,
        limit_value REAL NOT NULL,
        action_taken TEXT NOT NULL
      )
    ''');

    // 6. 为高频查询字段创建索引，大幅提升 queryLogsByQRCode 在大数据量时的查询速度
    await db.execute('CREATE INDEX idx_current_logs_qr ON current_logs(qr_code)');
    await db.execute('CREATE INDEX idx_current_logs_batch ON current_logs(batch_uuid)');
    await db.execute('CREATE INDEX idx_alarm_logs_qr ON alarm_logs(qr_code)');
    await db.execute('CREATE INDEX idx_run_history_qr ON motor_run_history(qr_code)');
  }

  // ============== 工况模板表 CRUD ==============
  Future<int> insertTemplate(Map<String, dynamic> templateMap) async {
    final db = await instance.database;
    return await db.insert('work_mode_templates', templateMap);
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    final db = await instance.database;
    return await db.query('work_mode_templates');
  }

  Future<int> deleteTemplate(int id) async {
    final db = await instance.database;
    return await db.delete('work_mode_templates', where: 'id = ?', whereArgs: [id]);
  }

  // ============== 测试记录与日志 CRUD ==============

  // 1. 插入一条新的运行批次记录
  Future<int> insertRunHistory(Map<String, dynamic> historyMap) async {
    final db = await instance.database;
    return await db.insert('motor_run_history', historyMap);
  }

  // 2. 更新批次状态（例如从 running 变成为 completed 或 stopped）
  Future<int> updateRunHistoryStatus(String batchUuid, String status) async {
    final db = await instance.database;
    return await db.update(
      'motor_run_history',
      {'end_status': status},
      where: 'batch_uuid = ?',
      whereArgs: [batchUuid],
    );
  }

  // 3. 插入采集到的电流流水
  Future<int> insertCurrentLog(Map<String, dynamic> logMap) async {
    final db = await instance.database;
    return await db.insert('current_logs', logMap);
  }

  // 4. 插入报警记录
  Future<int> insertAlarmLog(Map<String, dynamic> alarmMap) async {
    final db = await instance.database;
    return await db.insert('alarm_logs', alarmMap);
  }

  // 5. 根据二维码查询该设备的历史流水及报错信息（为查询图表页做准备）
  Future<List<Map<String, dynamic>>> queryLogsByQRCode(String qrCode) async {
    final db = await instance.database;
    // 使用 UNION ALL 将正常流水与报警记录合并到一起展示
    // 为了匹配结构，正常记录给它带上 "正常记录" 的标签，报警记录带上 "触发报警异常" 以及触发限值的说明
    final sql = '''
      SELECT 
        timestamp,
        batch_uuid,
        motor_id,
        loop_count,
        read_current,
        '正常记录' AS log_type
      FROM current_logs 
      WHERE qr_code = ?

      UNION ALL

      SELECT 
        timestamp,
        'Alarm' AS batch_uuid,
        motor_id,
        -1 AS loop_count,
        trip_current AS read_current,
        '触发报警异常 (限值: ' || limit_value || ')' AS log_type
      FROM alarm_logs
      WHERE qr_code = ?

      ORDER BY timestamp ASC
    ''';
    
    return await db.rawQuery(sql, [qrCode, qrCode]);
  }

  // 6. 获取所有的批次记录
  Future<List<Map<String, dynamic>>> getAllRunHistories() async {
    final db = await instance.database;
    return await db.query('motor_run_history', orderBy: 'start_time DESC');
  }

  // 7. 多条件高级查询：支持二维码、数据类型、日期范围、通道筛选
  // logType: 'all' | 'normal' | 'alarm'
  // dateFrom / dateTo: 'yyyy-MM-dd' 格式字符串，null 表示不限
  // motorId: null 表示全部通道
  Future<List<Map<String, dynamic>>> queryLogsAdvanced({
    String? qrCode,
    String logType = 'all',
    String? dateFrom,
    String? dateTo,
    int? motorId,
  }) async {
    final db = await instance.database;

    // 分别为正常记录表和报警记录表动态构建 WHERE 子句
    final List<String> normalWhere = [];
    final List<String> alarmWhere = [];
    final List<dynamic> normalArgs = [];
    final List<dynamic> alarmArgs = [];

    if (qrCode != null && qrCode.isNotEmpty) {
      normalWhere.add('qr_code = ?');
      normalArgs.add(qrCode);
      alarmWhere.add('qr_code = ?');
      alarmArgs.add(qrCode);
    }

    if (motorId != null) {
      normalWhere.add('motor_id = ?');
      normalArgs.add(motorId);
      alarmWhere.add('motor_id = ?');
      alarmArgs.add(motorId);
    }

    if (dateFrom != null) {
      normalWhere.add("timestamp >= ?");
      normalArgs.add(dateFrom);
      alarmWhere.add("timestamp >= ?");
      alarmArgs.add(dateFrom);
    }

    if (dateTo != null) {
      // 包含当天结束时间
      normalWhere.add("timestamp <= ?");
      normalArgs.add('${dateTo}T23:59:59');
      alarmWhere.add("timestamp <= ?");
      alarmArgs.add('${dateTo}T23:59:59');
    }

    final nw = normalWhere.isNotEmpty ? 'WHERE ${normalWhere.join(' AND ')}' : '';
    final aw = alarmWhere.isNotEmpty ? 'WHERE ${alarmWhere.join(' AND ')}' : '';

    String sql;
    List<dynamic> args;

    if (logType == 'normal') {
      sql = '''
        SELECT timestamp, batch_uuid, motor_id, loop_count, read_current, '正常记录' AS log_type
        FROM current_logs $nw
        ORDER BY timestamp ASC
      ''';
      args = normalArgs;
    } else if (logType == 'alarm') {
      sql = '''
        SELECT timestamp, 'Alarm' AS batch_uuid, motor_id, -1 AS loop_count,
               trip_current AS read_current,
               '触发报警异常 (限值: ' || limit_value || ')' AS log_type
        FROM alarm_logs $aw
        ORDER BY timestamp ASC
      ''';
      args = alarmArgs;
    } else {
      // all: UNION ALL 合并
      sql = '''
        SELECT timestamp, batch_uuid, motor_id, loop_count, read_current, '正常记录' AS log_type
        FROM current_logs $nw

        UNION ALL

        SELECT timestamp, 'Alarm' AS batch_uuid, motor_id, -1 AS loop_count,
               trip_current AS read_current,
               '触发报警异常 (限值: ' || limit_value || ')' AS log_type
        FROM alarm_logs $aw

        ORDER BY timestamp ASC
      ''';
      args = [...normalArgs, ...alarmArgs];
    }

    return await db.rawQuery(sql, args);
  }

  // =============================================

  // 关闭数据库连接
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
