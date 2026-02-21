import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/chat_provider.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onOpenChat;

  const ProjectDetailScreen({
    super.key,
    required this.onBack,
    required this.onOpenChat,
  });

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  String _libraryQuery = '';
  String _selectedQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    final selectedProject = state.projects
        .where((p) => p.id == state.selectedProjectId)
        .toList();
    final project = selectedProject.isEmpty ? null : selectedProject.first;

    if (project == null) {
      return Container(
        color: AIOCTheme.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '项目已删除或未找到',
                style: TextStyle(color: AIOCTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onBack,
                child: const Text('返回工作台'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredProjectSources = state.projectSources.where((s) {
      final target =
          '${s.name} ${s.sourceType} ${s.contentText} ${s.filePath} ${s.linkUrl}'
              .toLowerCase();
      return target.contains(_selectedQuery.toLowerCase());
    }).toList();

    final filteredLibrary = state.librarySources.where((s) {
      final target =
          '${s.name} ${s.sourceType} ${s.contentText} ${s.filePath} ${s.linkUrl}'
              .toLowerCase();
      return target.contains(_libraryQuery.toLowerCase());
    }).toList();

    return Container(
      color: AIOCTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: AIOCTheme.surface,
              border: Border(bottom: BorderSide(color: AIOCTheme.surfaceLight)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: AIOCTheme.textPrimary,
                  onPressed: widget.onBack,
                  tooltip: '返回工作台',
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AIOCTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await notifier.loadSources();
                    await notifier.loadProjectSources(project.id);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AIOCTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                  onPressed: () {
                    widget.onOpenChat();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已进入项目工作区')));
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text(
                    '开始工作',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

          if (project.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                project.description,
                style: const TextStyle(
                  color: AIOCTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),

          // Main split area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Panel: Project Sources
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '当前项目资料',
                          style: TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '这些资料是当前项目的专属上下文环境',
                          style: TextStyle(
                            color: AIOCTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索已挂载的资料',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _selectedQuery = v),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: filteredProjectSources.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 48,
                                        color: AIOCTheme.surfaceLight,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '还没有挂载任何资料\n从右侧资料库添加，或在聊天中自动沉淀',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AIOCTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredProjectSources.length,
                                  itemBuilder: (context, index) {
                                    final s = filteredProjectSources[index];
                                    return Card(
                                      color: AIOCTheme.surfaceCard,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(
                                          color: AIOCTheme.surfaceLight,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListTile(
                                        leading: Icon(
                                          _iconForType(s.sourceType),
                                          color: AIOCTheme.primary,
                                        ),
                                        title: Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          s.sourceType,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: IconButton(
                                          tooltip: '解除关联 (不会删除原始资产)',
                                          icon: const Icon(
                                            Icons.link_off,
                                            color: AIOCTheme.textSecondary,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            await notifier.removeProjectSource(
                                              s.sourceId,
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '已解除资产关联: ${s.name}',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Divider
                Container(width: 1, color: AIOCTheme.surfaceLight),

                // Right Panel: Global Library
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '全局资产库',
                          style: TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '将现有的全局资产接入到该项目中',
                          style: TextStyle(
                            color: AIOCTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索全局资产...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _libraryQuery = v),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: filteredLibrary.isEmpty
                              ? const Center(
                                  child: Text(
                                    '资产库为空或无匹配结果',
                                    style: TextStyle(
                                      color: AIOCTheme.textSecondary,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredLibrary.length,
                                  itemBuilder: (context, index) {
                                    final s = filteredLibrary[index];
                                    return Card(
                                      color: AIOCTheme.surfaceCard,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(
                                          color: AIOCTheme.surfaceLight,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListTile(
                                        leading: Icon(
                                          _iconForType(s.sourceType),
                                          color: AIOCTheme.accent,
                                        ),
                                        title: Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          s.sourceType,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 0,
                                            ),
                                          ),
                                          onPressed: () async {
                                            await notifier
                                                .attachLibrarySourceToProject(
                                                  s.sourceId,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '已接入项目任务: ${s.name}',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text('挂载'),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (state.error != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AIOCTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              state.error!,
                              style: const TextStyle(
                                color: AIOCTheme.error,
                                fontSize: 13,
                              ),
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
