import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/chat_provider.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  final VoidCallback onSelectProject;

  const ProjectsScreen({super.key, required this.onSelectProject});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _projectQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    final filteredProjects = state.projects.where((p) {
      final target = '${p.name} ${p.description}'.toLowerCase();
      return target.contains(_projectQuery.toLowerCase());
    }).toList();

    return Container(
      color: AIOCTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AIOCTheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: AIOCTheme.surfaceLight.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '工作台 / 项目夹',
                        style: TextStyle(
                          color: AIOCTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '项目是您的主要工作场所，您可以在此挂载关联文件并下发任务指令。',
                        style: TextStyle(
                          color: AIOCTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await notifier.loadProjects();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新列表'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AIOCTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () => _showCreateProjectDialog(context, notifier),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    '新建项目',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: SizedBox(
              width: 320,
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AIOCTheme.textSecondary,
                  ),
                  hintText: '搜索项目名称或描述...',
                  filled: true,
                  fillColor: AIOCTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AIOCTheme.surfaceLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AIOCTheme.surfaceLight),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _projectQuery = v),
              ),
            ),
          ),

          // Grid
          Expanded(
            child: filteredProjects.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 48,
                          color: AIOCTheme.surfaceLight,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '没找到匹配的项目\n请调整搜索条件，或新建一个项目',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AIOCTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 380,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.8,
                        ),
                    itemCount: filteredProjects.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildDraftCard(context, notifier);
                      }
                      final p = filteredProjects[index - 1];
                      return _buildProjectCard(context, p, notifier);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(BuildContext context, ChatNotifier notifier) {
    return Card(
      color: AIOCTheme.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AIOCTheme.accent.withOpacity(0.3), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await notifier.selectProject('');
          widget.onSelectProject();
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AIOCTheme.accent.withOpacity(0.05),
                AIOCTheme.primary.withOpacity(0.03),
              ],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AIOCTheme.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AIOCTheme.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '草稿记录 (Global Draft)',
                          style: TextStyle(
                            color: AIOCTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '不关联特定项目的随身对话历史',
                          style: TextStyle(
                            color: AIOCTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: AIOCTheme.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '管理全部通用历史记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: AIOCTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AIOCTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectCard(
    BuildContext context,
    ProjectItem project,
    ChatNotifier notifier,
  ) {
    return Card(
      color: AIOCTheme.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AIOCTheme.surfaceLight),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await notifier.selectProject(project.id);
          widget.onSelectProject();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    project.isTemporary
                        ? Icons.note_alt_outlined
                        : Icons.folder,
                    color: project.isTemporary
                        ? AIOCTheme.warning
                        : AIOCTheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AIOCTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (project.isTemporary) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AIOCTheme.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AIOCTheme.warning.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              '草稿记录',
                              style: TextStyle(
                                fontSize: 10,
                                color: AIOCTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        _confirmDeleteProject(context, project, notifier),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AIOCTheme.textSecondary,
                      size: 20,
                    ),
                    tooltip: '删除项目',
                  ),
                ],
              ),
              const Spacer(),
              if (project.description.isNotEmpty)
                Text(
                  project.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AIOCTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else
                const Text(
                  '添加描述...',
                  style: TextStyle(
                    fontSize: 13,
                    color: AIOCTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AIOCTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(project.updatedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AIOCTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.split('T').first;
    }
  }

  static void _confirmDeleteProject(
    BuildContext context,
    ProjectItem project,
    ChatNotifier notifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AIOCTheme.surfaceCard,
          title: const Text('删除确认'),
          content: Text(
            '您确定要删除项目「${project.name}」吗？关联的文件记录也将一并移除（原资产库文件不受影响）。此操作不可恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: AIOCTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AIOCTheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await notifier.deleteProject(project.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除项目: ${project.name}')),
                  );
                }
              },
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
  }

  static void _showCreateProjectDialog(
    BuildContext context,
    ChatNotifier notifier,
  ) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AIOCTheme.surfaceCard,
          title: const Text('新建工作项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '项目名称',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '项目说明（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: AIOCTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                await notifier.createProject(
                  name: name,
                  description: descController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('项目已创建: $name')));
                }
              },
              child: const Text('创建并配置'),
            ),
          ],
        );
      },
    );
  }
}
