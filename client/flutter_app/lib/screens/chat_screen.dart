import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;

  const ChatScreen({super.key, this.onBack});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final session = chatState.activeSession;
    final l10n = context.l10n;

    session != null &&
        session.messages.any(
          (m) =>
              m.toolEvents.isNotEmpty ||
              m.component != null ||
              m.executionSummary != null,
        );

    final bodyContent = Container(
      color: AIOCTheme.background,
      child: Column(
        children: [
          _buildTopBar(context, chatState, l10n),
          Expanded(
            child: Row(
              children: [
                // Left Panel: Chat Interface (Control Plane)
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        child: session == null || session.messages.isEmpty
                            ? _buildEmptyState(ref, l10n)
                            : _buildMessageList(session.messages),
                      ),
                      if (chatState.error != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: AIOCTheme.error.withOpacity(0.1),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: AIOCTheme.error,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  chatState.error!,
                                  style: const TextStyle(
                                    color: AIOCTheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ChatInput(
                        onSend: (text) =>
                            ref.read(chatProvider.notifier).sendMessage(text),
                        onStop: () =>
                            ref.read(chatProvider.notifier).stopGeneration(),
                        isStreaming: chatState.isStreaming,
                        skills: chatState.skills
                            .map((s) => ChatInputSkill(id: s.id, name: s.name))
                            .toList(),
                        selectedSkillIds: chatState.selectedSkillIds,
                        onAddSkill: (id) =>
                            ref.read(chatProvider.notifier).addSkill(id),
                        onRemoveSkill: (id) =>
                            ref.read(chatProvider.notifier).removeSkill(id),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AIOCTheme.background,
      endDrawer: _buildSourcesDrawer(chatState),
      endDrawerEnableOpenDragGesture: false,
      body: bodyContent,
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ChatState state,
    AppLocalizations l10n,
  ) {
    final scenarioLabel = state.selectedRoleId.isEmpty
        ? '全局模式'
        : '场景: ${state.selectedRoleId}';

    final activeProject = state.projects
        .where((p) => p.id == state.selectedProjectId)
        .firstOrNull;
    final isDraft =
        state.selectedProjectId.isEmpty ||
        (activeProject?.name.startsWith('Draft:') ?? false);
    final projectLabel = isDraft
        ? '草稿模式 (渐进式增强)'
        : (activeProject?.name ?? state.selectedProjectId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        border: Border(
          bottom: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                color: AIOCTheme.textSecondary,
                tooltip: '返回工作台',
                splashRadius: 24,
              ),
            ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDraft
                  ? Colors.orange.withOpacity(0.1)
                  : AIOCTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isDraft ? Icons.edit_note_rounded : Icons.verified_rounded,
              size: 20,
              color: isDraft ? Colors.orange : AIOCTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            state.activeSession?.title ?? l10n.t('chat'),
            style: const TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          // Tag for Draft vs Project
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDraft
                  ? Colors.orange.withOpacity(0.1)
                  : AIOCTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDraft
                    ? Colors.orange.withOpacity(0.3)
                    : AIOCTheme.primary.withOpacity(0.3),
              ),
            ),
            child: Text(
              projectLabel,
              style: TextStyle(
                color: isDraft ? Colors.orange : AIOCTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AIOCTheme.surfaceLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.psychology_alt_rounded,
                  size: 14,
                  color: AIOCTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  scenarioLabel,
                  style: const TextStyle(
                    color: AIOCTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: '管理本项目/草稿的资料与知识库 (${state.projectSources.length})',
            icon: Stack(
              children: [
                const Icon(
                  Icons.source_rounded,
                  color: AIOCTheme.textSecondary,
                ),
                if (state.projectSources.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AIOCTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '${state.projectSources.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
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

  Widget _buildEmptyState(WidgetRef ref, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AIOCTheme.primary.withOpacity(0.3),
                  AIOCTheme.accent.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 32,
              color: AIOCTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.t('startConversation'),
            style: TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('typeToStart'),
            style: TextStyle(color: AIOCTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.t('quickTasks'),
            style: TextStyle(
              color: AIOCTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _quickTaskChip(
                ref,
                label: l10n.t('systemInspect'),
                prompt:
                    'Use OpenClaw tools to run pwd and ls, then summarize the environment.',
              ),
              _quickTaskChip(
                ref,
                label: l10n.t('processSnapshot'),
                prompt:
                    'Use OpenClaw tools to run whoami and ps, then provide a concise status report.',
              ),
              _quickTaskChip(
                ref,
                label: l10n.t('chartDemo'),
                prompt:
                    'Generate a data chart component with a weekly CPU usage example and explain the trend.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTaskChip(
    WidgetRef ref, {
    required String label,
    required String prompt,
  }) {
    return OutlinedButton(
      onPressed: () => ref.read(chatProvider.notifier).sendMessage(prompt),
      style: OutlinedButton.styleFrom(
        foregroundColor: AIOCTheme.textPrimary,
        side: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.6)),
      ),
      child: Text(label),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length,
      reverse: false,
      itemBuilder: (ctx, i) => MessageBubble(message: messages[i]),
    );
  }

  Widget _buildSourcesDrawer(ChatState state) {
    final activeProject = state.projects
        .where((p) => p.id == state.selectedProjectId)
        .firstOrNull;

    final isDraft =
        state.selectedProjectId.isEmpty ||
        (activeProject?.name.startsWith('Draft:') ?? false);
    final projectName = isDraft ? '草稿模式' : (activeProject?.name ?? '未知项目');

    return Drawer(
      backgroundColor: AIOCTheme.surface,
      width: 320,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AIOCTheme.surfaceLight)),
            ),
            child: Row(
              children: [
                const Icon(Icons.source_rounded, color: AIOCTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '项目关联资料库',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AIOCTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            width: double.infinity,
            color: AIOCTheme.surfaceLight.withOpacity(0.3),
            child: Text(
              '当前环境: $projectName\n此面板中的资料将被提供给 AI 大脑及可访问本地文件的技能插件 (如 OpenClaw) 作为上下文推理依据。',
              style: const TextStyle(
                color: AIOCTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: state.projectSources.isEmpty
                ? const Center(
                    child: Text(
                      '目前没有任何资料关联到本对话环境。',
                      style: TextStyle(
                        color: AIOCTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.projectSources.length,
                    itemBuilder: (context, index) {
                      final s = state.projectSources[index];
                      return Card(
                        color: AIOCTheme.surfaceCard,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            s.sourceType == 'file'
                                ? Icons.insert_drive_file_outlined
                                : Icons.notes_outlined,
                            color: AIOCTheme.accent,
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            s.sourceType,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AIOCTheme.textSecondary,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AIOCTheme.error,
                              size: 18,
                            ),
                            onPressed: () async {
                              await ref
                                  .read(chatProvider.notifier)
                                  .removeProjectSource(s.sourceId);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AIOCTheme.surfaceLight)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Tell the user to go to the project dashboard or drag files into chat
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('请直接将文件拖拽进入聊天框，或前往大盘资料库统一添加。'),
                    ),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增资料片段'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
