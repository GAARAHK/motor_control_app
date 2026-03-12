import 'dart:convert';

// 动作类型枚举
class MotorStep {
  String action; // 'fwd'(正转), 'rev'(反转), 'stop'(停止)
  int duration;  // 时长 (秒)

  MotorStep({required this.action, required this.duration});

  Map<String, dynamic> toMap() => {'action': action, 'duration': duration};

  factory MotorStep.fromMap(Map<String, dynamic> map) {
    return MotorStep(
      action: map['action'] ?? 'stop',
      duration: map['duration'] ?? 0,
    );
  }

  String get actionLabel {
    switch(action) {
      case 'fwd': return '正转';
      case 'rev': return '反转';
      case 'stop': return '停止';
      default: return '未知';
    }
  }
}

// 电机工况模板模型
class MotorConfigTemplate {
  int? id;
  String name;
  List<MotorStep> steps; // 自定义的多段工况动作队列
  int targetLoops;      // 目标循环总次数
  int collectInterval;  // 采集间隔 (例如：每 x 次循环采1次)
  double limitUpper;    // 报警上限电流 (A)
  double limitLower;    // 报警下限电流 (A)

  MotorConfigTemplate({
    this.id,
    required this.name,
    required this.steps,
    this.targetLoops = 100,
    this.collectInterval = 10,
    this.limitUpper = 10.0,
    this.limitLower = 0.5,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'steps_json': jsonEncode(steps.map((e) => e.toMap()).toList()),
      'target_loops': targetLoops,
      'collect_interval': collectInterval,
      'limit_upper': limitUpper,
      'limit_lower': limitLower,
    };
  }

  factory MotorConfigTemplate.fromMap(Map<String, dynamic> map) {
    var stepsList = <MotorStep>[];
    if (map['steps_json'] != null) {
      final js = jsonDecode(map['steps_json']) as List;
      stepsList = js.map((e) => MotorStep.fromMap(e)).toList();
    }

    return MotorConfigTemplate(
      id: map['id'],
      name: map['name'].toString(),
      steps: stepsList,
      targetLoops: map['target_loops'] as int,
      collectInterval: map['collect_interval'] as int,
      limitUpper: (map['limit_upper'] as num).toDouble(),
      limitLower: (map['limit_lower'] as num).toDouble(),
    );
  }
}
