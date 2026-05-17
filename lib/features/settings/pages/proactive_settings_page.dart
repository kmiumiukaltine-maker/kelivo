import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/proactive_message_service.dart';
import '../../../shared/widgets/ios_switch.dart';

class ProactiveSettingsPage extends StatefulWidget {
  const ProactiveSettingsPage({super.key});

  @override
  State<ProactiveSettingsPage> createState() => _ProactiveSettingsPageState();
}

class _ProactiveSettingsPageState extends State<ProactiveSettingsPage> {
  late TextEditingController _urlController;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController = TextEditingController(text: settings.proactiveServerUrl);
    _nameController = TextEditingController(text: settings.proactiveAssistantName);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setProactiveServerUrl(_urlController.text);
    await settings.setProactiveAssistantName(_nameController.text);
    ProactiveMessageService.instance.stop();
    ProactiveMessageService.instance.configure(
      serverUrl: settings.proactiveServerUrl,
      enabled: settings.proactiveEnabled,
      assistantName: settings.proactiveAssistantName,
    );
    await ProactiveMessageService.instance.start();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);

    return Scaffold(
      appBar: AppBar(title: const Text('主动消息推送')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable toggle
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '开启主动消息',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'AI 主动向你发送消息',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IosSwitch(
                    value: settings.proactiveEnabled,
                    onChanged: (v) async {
                      await settings.setProactiveEnabled(v);
                      ProactiveMessageService.instance.stop();
                      ProactiveMessageService.instance.configure(
                        serverUrl: settings.proactiveServerUrl,
                        enabled: v,
                      );
                      if (v) await ProactiveMessageService.instance.start();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Server URL
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '推送服务器',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'http://your-server.com',
                    hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: cs.outlineVariant,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Text(
                  '填入服务器地址，不需要加 /push-api/events',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '指定助手',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: '助手名称，例如：澄',
                    hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Text(
                  '收到消息后，将插入该助手的对话记录',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Status
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '状态',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: settings.proactiveEnabled &&
                                settings.proactiveServerUrl.isNotEmpty
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      settings.proactiveEnabled &&
                              settings.proactiveServerUrl.isNotEmpty
                          ? '运行中'
                          : '未启用',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
