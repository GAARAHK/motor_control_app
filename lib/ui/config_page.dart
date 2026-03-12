import 'package:flutter/material.dart';
import '../models/motor_config.dart';
import '../core/database_helper.dart';

// 工况编排与报警阈值设定视图
class ConfigPage extends StatefulWidget {
  const ConfigPage({Key? key}) : super(key: key);

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  List<MotorConfigTemplate> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getTemplates();
    setState(() {
      _templates = data.map((e) => MotorConfigTemplate.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteTemplate(int id) async {
    await DatabaseHelper.instance.deleteTemplate(id);
    _loadTemplates();
  }

  void _showAddTemplateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddTemplateDialog(
        onSaved: (MotorConfigTemplate t) async {
          await DatabaseHelper.instance.insertTemplate(t.toMap());
          _loadTemplates();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '参数与工况预设配置',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建工况'),
                onPressed: _showAddTemplateDialog,
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _templates.isEmpty 
                    ? const Center(child: Text('暂无预设工况，请点击右上角新建。'))
                    : ListView.builder(
                        itemCount: _templates.length,
                        itemBuilder: (context, index) {
                          final t = _templates[index];
                          // 拼接口语化的步骤描述
                          String stepsDesc = t.steps.map((s) => '${s.actionLabel}(${s.duration}s)').join(' → ');

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              subtitle: Text(
                                '流程: $stepsDesc\n'
                                '循环: ${t.targetLoops}次 | 采集: 每${t.collectInterval}次/回 | 阈值: ${t.limitLower}A - ${t.limitUpper}A',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.grey),
                                onPressed: () => _deleteTemplate(t.id!),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// 动态步骤表单弹窗
class _AddTemplateDialog extends StatefulWidget {
  final Function(MotorConfigTemplate) onSaved;
  const _AddTemplateDialog({required this.onSaved});

  @override
  State<_AddTemplateDialog> createState() => _AddTemplateDialogState();
}

class _AddTemplateDialogState extends State<_AddTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  int _targetLoops = 100;
  int _collectInterval = 10;
  double _limitUpper = 10.0;
  double _limitLower = 0.5;
  
  List<MotorStep> _steps = [];

  void _addStep() {
    setState(() {
      _steps.add(MotorStep(action: 'fwd', duration: 10));
    });
  }

  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置自定义流程工况'),
      content: SizedBox(
        width: 500, // 给得宽一点以放下步骤列表
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: '方案名称 (如：正转停-反转停测试)'),
                  validator: (v) => (v == null || v.isEmpty) ? '请输入名称' : null,
                  onSaved: (v) => _name = v!,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: '目标总循环次数'),
                        initialValue: '100',
                        keyboardType: TextInputType.number,
                        onSaved: (v) => _targetLoops = int.tryParse(v ?? '100') ?? 100,
                      )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: '每隔X次采集1回'),
                        initialValue: '10',
                        keyboardType: TextInputType.number,
                        onSaved: (v) => _collectInterval = int.tryParse(v ?? '10') ?? 10,
                      )
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: '报警上限电流(A)'),
                        initialValue: '10.0',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onSaved: (v) => _limitUpper = double.tryParse(v ?? '10.0') ?? 10.0,
                      )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: '报警下限电流(A)'),
                        initialValue: '0.5',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onSaved: (v) => _limitLower = double.tryParse(v ?? '0.5') ?? 0.5,
                      )
                    ),
                  ],
                ),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('动作序列配置', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _addStep,
                      icon: const Icon(Icons.add),
                      label: const Text('添加动作'),
                    )
                  ],
                ),
                if (_steps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('点击右上角添加动作阶段', style: TextStyle(color: Colors.grey)),
                  ),
                ..._steps.asMap().entries.map((entry) {
                  int idx = entry.key;
                  MotorStep step = entry.value;
                  return Row(
                    children: [
                      Text('节点 ${idx + 1}:'),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: step.action,
                        items: const [
                          DropdownMenuItem(value: 'fwd', child: Text('正转')),
                          DropdownMenuItem(value: 'rev', child: Text('反转')),
                          DropdownMenuItem(value: 'stop', child: Text('停止/等待')),
                        ],
                        onChanged: (val) {
                          setState(() => step.action = val!);
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(labelText: '时长(秒)'),
                          initialValue: step.duration.toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => step.duration = int.tryParse(val) ?? 0,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeStep(idx),
                      )
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              if (_steps.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('动作序列不能为空')));
                return;
              }
              _formKey.currentState!.save();
              
              final t = MotorConfigTemplate(
                name: _name,
                steps: _steps,
                targetLoops: _targetLoops,
                collectInterval: _collectInterval,
                limitUpper: _limitUpper,
                limitLower: _limitLower,
              );
              Navigator.pop(context);
              widget.onSaved(t);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

