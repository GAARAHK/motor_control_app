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
        version: 2, // 升级为支持动态动作队列的版本
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

  // 5. 根据二维码查询该设备的历史流水（为查询图表页做准备）
  Future<List<Map<String, dynamic>>> queryLogsByQRCode(String qrCode) async {
    final db = await instance.database;
    return await db.query(
      'current_logs',
      where: 'qr_code = ?',
      whereArgs: [qrCode],
      orderBy: 'timestamp ASC',  // 按时间正序
    );
  }

  // 6. 获取所有的批次记录
  Future<List<Map<String, dynamic>>> getAllRunHistories() async {
    final db = await instance.database;
    return await db.query('motor_run_history', orderBy: 'start_time DESC');
  }

  // =============================================

  // 关闭数据库连接
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
