import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/chat_provider.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenChat;

  const ProjectsScreen({super.key, required this.onOpenChat});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _projectQuery = '';
  String _libraryQuery = '';
  String _selectedQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    final selectedProject = state.projects.where((p) => p.id == state.selectedProjectId).toList();
    final selectedName = selectedProject.isEmpty ? '未选择项目' : selectedProject.first.name;

    final filteredProjects = state.projects.where((p) {
      final target = '${p.name} ${p.description}'.toLowerCase();
      return target.contains(_projectQuery.toLowerCase());
    }).toList();

    final filteredProjectSources = state.projectSources.where((s) {
      final target = '${s.name} ${s.sourceType} ${s.contentText} ${s.filePath} ${s.linkUrl}'.toLowerCase();
      return target.contains(_selectedQuery.toLowerCase());
    }).toList();

    final filteredLibrary = state.librarySources.where((s) {
      final target = '${s.name} ${s.sourceType} ${s.contentText} ${s.filePath} ${s.linkUrl}'.toLowerCase();
      return target.contains(_libraryQuery.toLowerCase());
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '项目管理',
                        style: TextStyle(
                          color: AIOCTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '当前项目：$selectedName。项目是资料组合，用于某次对话任务。',
                        style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await notifier.loadProjects();
                    await notifier.loadSources();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: state.selectedProjectId.isEmpty
                      ? null
                      : () {
                          widget.onOpenChat();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已打开对话，后续消息将使用当前项目资料源')),
                          );
                        },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('打开项目对话'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '项目列表',
                            style: TextStyle(
                              color: AIOCTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => _showCreateProjectDialog(context, notifier),
                            icon: const Icon(Icons.add),
                            tooltip: '新建项目',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '搜索项目',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _projectQuery = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filteredProjects.length,
                          itemBuilder: (context, index) {
                            final p = filteredProjects[index];
                            final active = p.id == state.selectedProjectId;
                            return Card(
                              color: active ? AIOCTheme.primary.withOpacity(0.2) : AIOCTheme.surfaceCard,
                              child: ListTile(
                                title: Text(p.name),
                                subtitle: Text(
                                  p.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => notifier.selectProject(p.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '项目已选资料',
                          style: TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索已选资料',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _selectedQuery = v),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: state.selectedProjectId.isEmpty
                              ? const Center(
                                  child: Text(
                                    '请先选择项目',
                                    style: TextStyle(color: AIOCTheme.textSecondary),
                                  ),
                                )
                              : (filteredProjectSources.isEmpty
                                    ? const Center(
                                        child: Text(
                                          '当前项目还未组合任何资料或无匹配结果',
                                          style: TextStyle(color: AIOCTheme.textSecondary),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filteredProjectSources.length,
                                        itemBuilder: (context, index) {
                                          final s = filteredProjectSources[index];
                                          return ListTile(
                                            dense: true,
                                            leading: Icon(_iconForType(s.sourceType), color: AIOCTheme.accent),
                                            title: Text(s.name),
                                            subtitle: Text(s.sourceType),
                                            trailing: IconButton(
                                              tooltip: '移除',
                                              icon: const Icon(Icons.remove_circle_outline, color: AIOCTheme.error),
                                              onPressed: () async {
                                                await notifier.removeProjectSource(s.sourceId);
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('已移除: ${s.name}')),
                                                  );
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      )),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '从资料库加入到当前项目',
                          style: TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索资料库',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _libraryQuery = v),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: filteredLibrary.isEmpty
                              ? const Center(
                                  child: Text(
                                    '资料库为空或无匹配结果',
                                    style: TextStyle(color: AIOCTheme.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredLibrary.length,
                                  itemBuilder: (context, index) {
                                    final s = filteredLibrary[index];
                                    return Card(
                                      color: AIOCTheme.surfaceCard,
                                      child: ListTile(
                                        leading: Icon(_iconForType(s.sourceType), color: AIOCTheme.accent),
                                        title: Text(s.name),
                                        subtitle: Text(s.sourceType),
                                        trailing: OutlinedButton(
                                          onPressed: state.selectedProjectId.isEmpty
                                              ? null
                                              : () async {
                                                  await notifier.attachLibrarySourceToProject(s.sourceId);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('已加入项目: ${s.name}')),
                                                    );
                                                  }
                                                },
                                          child: const Text('加入项目'),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (state.error != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            color: AIOCTheme.error.withOpacity(0.12),
                            child: Text(
                              state.error!,
                              style: const TextStyle(color: AIOCTheme.error, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _showCreateProjectDialog(BuildContext context, ChatNotifier notifier) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AIOCTheme.surfaceCard,
          title: const Text('新建项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '项目名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '项目说明（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                await notifier.createProject(name: name, description: descController.text.trim());
                if (context.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('项目已创建: $name')),
                  );
                }
              },
              child: const Text('创建'),
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
}
