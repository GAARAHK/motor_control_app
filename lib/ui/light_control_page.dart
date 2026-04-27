import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/motor_state.dart';

class LightControlPage extends StatelessWidget {
  const LightControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MotorState>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '灯光手动控制',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      for (int i = 1; i <= 7; i++) {
                        await context.read<MotorState>().setLampState(i, false);
                      }
                    },
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('全部关闭'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      for (int i = 1; i <= 7; i++) {
                        await context.read<MotorState>().setLampState(i, true);
                      }
                    },
                    icon: const Icon(Icons.wb_incandescent_rounded),
                    label: const Text('全部打开'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '说明：1=红灯，2=黄灯，3=绿灯（会被电机运行状态自动接管）；4~7可纯手动控制。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: 7,
              itemBuilder: (context, index) {
                final lampId = index + 1;
                final isOn = state.lampStates[index];

                Color lampColor;
                if (lampId == 1) {
                  lampColor = Colors.red;
                } else if (lampId == 2) {
                  lampColor = Colors.amber.shade700;
                } else if (lampId == 3) {
                  lampColor = Colors.green;
                } else {
                  lampColor = Colors.blueGrey;
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb,
                              color: isOn ? lampColor : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '灯 $lampId',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isOn ? '已打开' : '已关闭',
                              style: TextStyle(
                                color: isOn ? lampColor : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Switch(
                              value: isOn,
                              onChanged: (_) {
                                context.read<MotorState>().toggleLamp(lampId);
                              },
                            ),
                          ],
                        ),
                      ],
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
