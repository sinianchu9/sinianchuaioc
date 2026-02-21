import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_localizations.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/language_provider.dart';
import 'config_center_screen.dart';
import 'materials_screen.dart';
import 'automations_screen.dart';
import 'workspace_screen.dart';
import 'skills_screen.dart';
import 'usage_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(chatProvider.notifier);
      notifier.loadSessions();
      notifier.loadSkills();
      notifier.loadUseCases();
      notifier.loadProjects();
      notifier.loadSources();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState.roles.contains('admin');

    final screens = <Widget>[
      const WorkspaceScreen(), // Combines Chat and Projects
      const SkillsScreen(),
      const MaterialsScreen(),
      const AutomationsScreen(),
      if (isAdmin) const ConfigCenterScreen(),
      const UsageScreen(),
    ];
    final safeIndex = _currentIndex >= screens.length ? 0 : _currentIndex;

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(child: screens[safeIndex]),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final authState = ref.watch(authProvider);
    final chatState = ref.watch(chatProvider);
    final locale = ref.watch(languageProvider);
    final l10n = context.l10n;
    final isAdmin = authState.roles.contains('admin');
    final usageIndex = isAdmin ? 6 : 5;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AIOCTheme.surface,
        border: Border(
          right: BorderSide(color: AIOCTheme.surfaceLight.withOpacity(0.5)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AIOCTheme.primary, AIOCTheme.accent],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'AIOC',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AIOCTheme.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(chatProvider.notifier).createSession();
                      setState(() => _currentIndex = 0);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.t('newChat')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AIOCTheme.primary.withOpacity(0.2),
                      foregroundColor: AIOCTheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: chatState.sessions.length,
              itemBuilder: (ctx, i) {
                final session = chatState.sessions[i];
                final isActive = session.id == chatState.activeSessionId;
                return _buildSessionTile(session, isActive);
              },
            ),
          ),

          const Divider(color: AIOCTheme.surfaceLight, height: 1),

          _buildNavItem(Icons.dashboard_outlined, '工作台', 0),
          _buildNavItem(Icons.local_mall_outlined, '技能模板', 1),
          _buildNavItem(Icons.archive_outlined, '资产库', 2),
          _buildNavItem(Icons.schedule, l10n.t('automations'), 3),
          if (isAdmin)
            _buildNavItem(Icons.settings_suggest_outlined, '配置中心', 4),
          _buildNavItem(
            Icons.analytics_outlined,
            l10n.t('usage'),
            usageIndex - 1,
          ),

          const Divider(color: AIOCTheme.surfaceLight, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  l10n.t('language'),
                  style: const TextStyle(
                    color: AIOCTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: locale.languageCode,
                    dropdownColor: AIOCTheme.surfaceCard,
                    style: const TextStyle(color: AIOCTheme.textPrimary),
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(l10n.t('languageEnglish')),
                      ),
                      DropdownMenuItem(
                        value: 'zh',
                        child: Text(l10n.t('languageChinese')),
                      ),
                      DropdownMenuItem(
                        value: 'ja',
                        child: Text(l10n.t('languageJapanese')),
                      ),
                      DropdownMenuItem(
                        value: 'ko',
                        child: Text(l10n.t('languageKorean')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(languageProvider.notifier)
                            .setLocaleCode(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AIOCTheme.primary.withOpacity(0.3),
                  child: Text(
                    (authState.displayName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AIOCTheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.displayName ?? l10n.t('user'),
                        style: const TextStyle(
                          color: AIOCTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        authState.email ?? '',
                        style: const TextStyle(
                          color: AIOCTheme.textSecondary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.logout,
                    size: 18,
                    color: AIOCTheme.textSecondary,
                  ),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  tooltip: l10n.t('logout'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(ChatSession session, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isActive
            ? AIOCTheme.primary.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            ref.read(chatProvider.notifier).selectSession(session.id);
            setState(() => _currentIndex = 0);
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: isActive ? AIOCTheme.primary : AIOCTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.title,
                    style: TextStyle(
                      color: isActive
                          ? AIOCTheme.textPrimary
                          : AIOCTheme.textSecondary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (isActive)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AIOCTheme.textSecondary,
                    ),
                    onPressed: () => ref
                        .read(chatProvider.notifier)
                        .deleteSession(session.id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? AIOCTheme.primary : AIOCTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? AIOCTheme.primary : AIOCTheme.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
