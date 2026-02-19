import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/chat_provider.dart';

class SkillsScreen extends ConsumerStatefulWidget {
  const SkillsScreen({super.key});

  @override
  ConsumerState<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends ConsumerState<SkillsScreen> {
  String _activeRole = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    final roles = state.useCaseRoles;
    if (roles.isNotEmpty && !roles.any((r) => r.roleId == _activeRole)) {
      _activeRole = roles.first.roleId;
    }

    final role = roles.isEmpty
        ? null
        : roles.firstWhere((r) => r.roleId == _activeRole, orElse: () => roles.first);

    final roleTaskSkillIds = role == null
        ? <String>{}
        : role.tasks.expand((t) => t.defaultSkills).toSet();
    final genericSkillIds = state.genericUseCaseSkills.map((g) => g.id).toSet();

    final moreSkills = state.skills
        .where((s) => !roleTaskSkillIds.contains(s.id) && !genericSkillIds.contains(s.id))
        .toList();

    return Container(
      color: AIOCTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AIOCTheme.surface,
              border: Border(
                bottom: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == null ? '使用场景' : '我是${role.title}',
                  style: const TextStyle(
                    color: AIOCTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '按职业选择任务。通用能力与其他技能在下方。',
                  style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (roles.isEmpty)
                  const Text(
                    '职业任务加载中或未配置。',
                    style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: roles.map((cfg) {
                      final selected = cfg.roleId == _activeRole;
                      return ChoiceChip(
                        label: Text(cfg.title),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: AIOCTheme.primary.withOpacity(0.25),
                        backgroundColor: AIOCTheme.surfaceCard,
                        side: BorderSide(
                          color: selected
                              ? AIOCTheme.primary.withOpacity(0.6)
                              : AIOCTheme.surfaceLight.withOpacity(0.5),
                        ),
                        onSelected: (_) => setState(() => _activeRole = cfg.roleId),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                _buildProjectPicker(state, notifier),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildRoleTaskCard(role, state, notifier),
                _buildSourceCard(context, state, notifier),
                _buildGenericCard(state, notifier),
                _buildMoreCard(state, notifier, moreSkills),
                const SizedBox(height: 10),
                _buildAddSkillCard(context),
              ],
            ),
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

  Widget _buildProjectPicker(ChatState state, ChatNotifier notifier) {
    return Column(
      children: [
        Row(
          children: [
            const Text(
              '项目',
              style: TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AIOCTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
                  ),
                  child: DropdownButton<String>(
                    value: state.selectedProjectId.isEmpty ? null : state.selectedProjectId,
                    hint: const Text(
                      '选择项目',
                      style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
                    ),
                    dropdownColor: AIOCTheme.surfaceCard,
                    style: const TextStyle(color: AIOCTheme.textPrimary, fontSize: 13),
                    isExpanded: true,
                    items: state.projects
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(p.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        notifier.selectProject(value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _showCreateProjectDialog(context, notifier),
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('新建项目'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: state.selectedProjectId.isEmpty
                  ? null
                  : () => _showImportSourceDialog(context, notifier),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('导入资料源'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSourceCard(
    BuildContext context,
    ChatState state,
    ChatNotifier notifier,
  ) {
    final sources = state.projectSources;
    return Card(
      color: AIOCTheme.surfaceCard,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '项目资料源',
              style: TextStyle(
                color: AIOCTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '支持文本、文件路径、图片路径、音频路径、链接。任务只引用当前项目资料源。',
              style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (state.selectedProjectId.isEmpty)
              const Text(
                '请先选择或创建项目。',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else if (state.sourcesLoading)
              const Text(
                '正在加载资料源...',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else if (sources.isEmpty)
              const Text(
                '当前项目没有资料源，点击“导入资料源”开始添加。',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else
              Column(
                children: sources.take(6).map((s) {
                  final suffix = s.linkUrl.isNotEmpty
                      ? s.linkUrl
                      : (s.filePath.isNotEmpty ? s.filePath : s.contentText);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_iconForType(s.sourceType), color: AIOCTheme.accent),
                    title: Text(
                      s.name,
                      style: const TextStyle(color: AIOCTheme.textPrimary, fontSize: 13),
                    ),
                    subtitle: Text(
                      '${s.sourceType} · ${_shorten(suffix)}',
                      style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            if (sources.length > 6)
              Text(
                '还有 ${sources.length - 6} 个资料源...',
                style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.selectedProjectId.isEmpty
                      ? null
                      : () => notifier.loadProjectSources(state.selectedProjectId),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: state.selectedProjectId.isEmpty
                      ? null
                      : () => _showImportSourceDialog(context, notifier),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('新增资料源'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleTaskCard(
    UseCaseRoleItem? role,
    ChatState state,
    ChatNotifier notifier,
  ) {
    return Card(
      color: AIOCTheme.surfaceCard,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              role == null ? '职业技能' : '${role.title}技能',
              style: const TextStyle(
                color: AIOCTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (role == null || role.tasks.isEmpty)
              const Text(
                '当前角色暂无已接入任务',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: role.tasks.map((task) {
                  final isActiveTask =
                      state.selectedRoleId == role.roleId && state.selectedTaskId == task.taskId;
                  final selectedBySkill =
                      task.defaultSkills.any((id) => state.selectedSkillIds.contains(id));
                  return FilterChip(
                    label: Text(task.title),
                    selected: selectedBySkill,
                    showCheckmark: false,
                    selectedColor: AIOCTheme.primary.withOpacity(0.25),
                    backgroundColor: AIOCTheme.surface,
                    side: BorderSide(
                      color: isActiveTask
                          ? AIOCTheme.accent.withOpacity(0.8)
                          : (selectedBySkill
                                ? AIOCTheme.primary.withOpacity(0.6)
                                : AIOCTheme.surfaceLight.withOpacity(0.5)),
                    ),
                    onSelected: (_) {
                      notifier.setModelMode(task.mode);
                      notifier.selectScenario(
                        roleId: role.roleId,
                        taskId: task.taskId,
                        defaultSkills: task.defaultSkills,
                      );
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),
            Text(
              '当前任务: ${state.selectedRoleId.isEmpty ? "未选择" : "${state.selectedRoleId} / ${state.selectedTaskId}"}',
              style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericCard(ChatState state, ChatNotifier notifier) {
    return Card(
      color: AIOCTheme.surfaceCard,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '通用技能',
              style: TextStyle(
                color: AIOCTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (state.genericUseCaseSkills.isEmpty)
              const Text(
                '当前没有通用技能',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.genericUseCaseSkills.map((g) {
                  final selected = state.selectedSkillIds.contains(g.id);
                  final available = state.skills.any((s) => s.id == g.id);
                  if (!available) {
                    return _ghostChip(g.name);
                  }
                  return FilterChip(
                    label: Text(g.name),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AIOCTheme.primary.withOpacity(0.25),
                    backgroundColor: AIOCTheme.surface,
                    side: BorderSide(
                      color: selected
                          ? AIOCTheme.primary.withOpacity(0.6)
                          : AIOCTheme.surfaceLight.withOpacity(0.5),
                    ),
                    onSelected: (_) => notifier.toggleSkill(g.id),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreCard(
    ChatState state,
    ChatNotifier notifier,
    List<SkillItem> moreSkills,
  ) {
    return Card(
      color: AIOCTheme.surfaceCard,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '更多',
              style: TextStyle(
                color: AIOCTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (moreSkills.isEmpty)
              const Text(
                '当前没有更多技能',
                style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: moreSkills.map((skill) {
                  final selected = state.selectedSkillIds.contains(skill.id);
                  return FilterChip(
                    label: Text(skill.name),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AIOCTheme.primary.withOpacity(0.25),
                    backgroundColor: AIOCTheme.surface,
                    side: BorderSide(
                      color: selected
                          ? AIOCTheme.primary.withOpacity(0.6)
                          : AIOCTheme.surfaceLight.withOpacity(0.5),
                    ),
                    onSelected: (_) => notifier.toggleSkill(skill.id),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSkillCard(BuildContext context) {
    return Card(
      color: AIOCTheme.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '添加新技能',
                style: TextStyle(
                  color: AIOCTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAddSkillDialog(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
      ),
      child: Text(
        '$label（待接入）',
        style: const TextStyle(color: AIOCTheme.textSecondary, fontSize: 12),
      ),
    );
  }

  void _showAddSkillDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AIOCTheme.surfaceCard,
          title: const Text('添加新技能'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '技能名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '技能描述',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final name = nameController.text.trim();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已记录新技能：${name.isEmpty ? "未命名技能" : name}'),
                  ),
                );
              },
              child: const Text('提交'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateProjectDialog(BuildContext context, ChatNotifier notifier) {
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
                maxLines: 2,
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
                if (context.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  void _showImportSourceDialog(BuildContext context, ChatNotifier notifier) {
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

    String hintForType(String type) {
      switch (type) {
        case 'file':
          return r'例如：C:\data\report.pdf';
        case 'image':
          return r'例如：C:\data\photo.png';
        case 'audio':
          return r'例如：C:\data\meeting.mp3';
        case 'link':
          return '例如：https://example.com/page';
        default:
          return '粘贴要引用的文本内容';
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInnerState) {
            return AlertDialog(
              backgroundColor: AIOCTheme.surfaceCard,
              title: const Text('导入资料源'),
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
                      onChanged: (v) => setInnerState(() => sourceType = v ?? 'text'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '资料名称（可选，留空自动命名）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: valueController,
                      decoration: InputDecoration(
                        labelText: labelForType(sourceType),
                        hintText: hintForType(sourceType),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: sourceType == 'text' ? 5 : 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
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
                        : raw.split(RegExp(r'[\\\\/]')).last;
                    await notifier.createProjectSource(
                      sourceType: sourceType,
                      name: nameController.text.trim().isEmpty ? autoName : nameController.text.trim(),
                      contentText: sourceType == 'text' ? raw : '',
                      filePath: (sourceType == 'file' || sourceType == 'image' || sourceType == 'audio')
                          ? raw
                          : '',
                      linkUrl: sourceType == 'link' ? raw : '',
                    );
                    if (context.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('导入'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _iconForType(String type) {
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

  String _shorten(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    return v.length > 80 ? '${v.substring(0, 80)}...' : v;
  }
}
