import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/chat_provider.dart';

class MaterialsScreen extends ConsumerStatefulWidget {
  const MaterialsScreen({super.key});

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    final filtered = state.librarySources.where((s) {
      final target = '${s.name} ${s.sourceType} ${s.linkUrl} ${s.filePath} ${s.contentText}'.toLowerCase();
      return target.contains(_query.toLowerCase());
    }).toList();

    return Container(
      color: AIOCTheme.background,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AIOCTheme.surface,
              border: Border(
                bottom: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '资料库',
                        style: TextStyle(
                          color: AIOCTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '管理你的全部资料源（文本、文件、图片、音频、链接）。',
                        style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showCreateSourceDialog(context, notifier),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增资料'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: notifier.loadSources,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索资料名称/路径/链接/内容',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: state.sourcesLoading
                ? const Center(child: CircularProgressIndicator())
                : (filtered.isEmpty
                      ? const Center(
                          child: Text(
                            '资料库为空或无匹配结果。',
                            style: TextStyle(color: AIOCTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final s = filtered[index];
                            return Card(
                              color: AIOCTheme.surfaceCard,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(_iconForType(s.sourceType), color: AIOCTheme.accent),
                                title: Text(
                                  s.name,
                                  style: const TextStyle(color: AIOCTheme.textPrimary),
                                ),
                                subtitle: Text(
                                  '${s.sourceType} · ${_preview(s)}',
                                  style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    IconButton(
                                      tooltip: '编辑',
                                      onPressed: () => _showEditSourceDialog(context, notifier, s),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                    ),
                                    IconButton(
                                      tooltip: '删除',
                                      onPressed: () => _confirmDeleteSource(context, notifier, s),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: AIOCTheme.error),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
          ),
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AIOCTheme.error.withOpacity(0.12),
              child: Text(
                state.error!,
                style: const TextStyle(color: AIOCTheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static void _showCreateSourceDialog(BuildContext context, ChatNotifier notifier) {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    String sourceType = 'text';

    String labelForType(String type) {
      switch (type) {
        case 'file':
          return '文件路径';
        case 'image':
          return '图片路径';
        case 'audio':
          return '音频路径';
        case 'link':
          return '链接地址';
        default:
          return '文本内容';
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) {
            return AlertDialog(
              backgroundColor: AIOCTheme.surfaceCard,
              title: const Text('新增资料'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: sourceType,
                      decoration: const InputDecoration(
                        labelText: '资料类型',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'text', child: Text('文本')),
                        DropdownMenuItem(value: 'file', child: Text('文件')),
                        DropdownMenuItem(value: 'image', child: Text('图片')),
                        DropdownMenuItem(value: 'audio', child: Text('音频')),
                        DropdownMenuItem(value: 'link', child: Text('链接')),
                      ],
                      onChanged: (v) => setInner(() => sourceType = v ?? 'text'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '资料名称（可选）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: valueController,
                      decoration: InputDecoration(
                        labelText: labelForType(sourceType),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: sourceType == 'text' ? 5 : 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () async {
                    final raw = valueController.text.trim();
                    if (raw.isEmpty) return;
                    if (sourceType == 'link' &&
                        !(raw.startsWith('http://') || raw.startsWith('https://'))) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('链接必须以 http:// 或 https:// 开头')),
                      );
                      return;
                    }
                    final autoName = sourceType == 'text'
                        ? '文本资料 ${DateTime.now().toIso8601String()}'
                        : raw.split(RegExp(r'[\\/]')).last;
                    final finalName = nameController.text.trim().isEmpty ? autoName : nameController.text.trim();
                    await notifier.createSource(
                      sourceType: sourceType,
                      name: finalName,
                      contentText: sourceType == 'text' ? raw : '',
                      filePath: (sourceType == 'file' || sourceType == 'image' || sourceType == 'audio')
                          ? raw
                          : '',
                      linkUrl: sourceType == 'link' ? raw : '',
                    );
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('资料已保存: $finalName')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _showEditSourceDialog(BuildContext context, ChatNotifier notifier, LibrarySourceItem source) {
    final nameController = TextEditingController(text: source.name);
    final valueController = TextEditingController(
      text: source.linkUrl.isNotEmpty ? source.linkUrl : (source.filePath.isNotEmpty ? source.filePath : source.contentText),
    );
    String sourceType = source.sourceType;

    String labelForType(String type) {
      switch (type) {
        case 'file':
          return '文件路径';
        case 'image':
          return '图片路径';
        case 'audio':
          return '音频路径';
        case 'link':
          return '链接地址';
        default:
          return '文本内容';
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) {
            return AlertDialog(
              backgroundColor: AIOCTheme.surfaceCard,
              title: const Text('编辑资料'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: sourceType,
                      decoration: const InputDecoration(
                        labelText: '资料类型',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'text', child: Text('文本')),
                        DropdownMenuItem(value: 'file', child: Text('文件')),
                        DropdownMenuItem(value: 'image', child: Text('图片')),
                        DropdownMenuItem(value: 'audio', child: Text('音频')),
                        DropdownMenuItem(value: 'link', child: Text('链接')),
                      ],
                      onChanged: (v) => setInner(() => sourceType = v ?? source.sourceType),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '资料名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: valueController,
                      decoration: InputDecoration(
                        labelText: labelForType(sourceType),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: sourceType == 'text' ? 5 : 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () async {
                    final raw = valueController.text.trim();
                    final name = nameController.text.trim();
                    if (raw.isEmpty || name.isEmpty) return;
                    if (sourceType == 'link' &&
                        !(raw.startsWith('http://') || raw.startsWith('https://'))) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('链接必须以 http:// 或 https:// 开头')),
                      );
                      return;
                    }
                    await notifier.updateSource(
                      sourceId: source.sourceId,
                      sourceType: sourceType,
                      name: name,
                      contentText: sourceType == 'text' ? raw : '',
                      filePath: (sourceType == 'file' || sourceType == 'image' || sourceType == 'audio') ? raw : '',
                      linkUrl: sourceType == 'link' ? raw : '',
                    );
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('资料已更新: $name')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _confirmDeleteSource(BuildContext context, ChatNotifier notifier, LibrarySourceItem source) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AIOCTheme.surfaceCard,
          title: const Text('删除资料'),
          content: Text('确认删除资料“${source.name}”？此操作不可撤销。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AIOCTheme.error),
              onPressed: () async {
                await notifier.deleteSource(source.sourceId);
                if (context.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除: ${source.name}')),
                  );
                }
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'file':
        return Icons.insert_drive_file_outlined;
      case 'image':
        return Icons.image_outlined;
      case 'audio':
        return Icons.graphic_eq_outlined;
      case 'link':
        return Icons.link_outlined;
      default:
        return Icons.notes_outlined;
    }
  }

  static String _preview(LibrarySourceItem s) {
    final raw = s.linkUrl.isNotEmpty ? s.linkUrl : (s.filePath.isNotEmpty ? s.filePath : s.contentText);
    if (raw.length <= 90) return raw;
    return '${raw.substring(0, 90)}...';
  }
}
