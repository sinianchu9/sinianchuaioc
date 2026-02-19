import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_service.dart';
import 'auth_provider.dart';

// Chat message model
class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;
  final String? component;
  final Map<String, dynamic>? componentArgs;
  final List<ToolTraceEvent> toolEvents;
  final Map<String, dynamic>? executionSummary;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.component,
    this.componentArgs,
    this.toolEvents = const [],
    this.executionSummary,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    String? component,
    Map<String, dynamic>? componentArgs,
    List<ToolTraceEvent>? toolEvents,
    Map<String, dynamic>? executionSummary,
  }) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      component: component ?? this.component,
      componentArgs: componentArgs ?? this.componentArgs,
      toolEvents: toolEvents ?? this.toolEvents,
      executionSummary: executionSummary ?? this.executionSummary,
    );
  }

  Map<String, dynamic> toApiMap() => {'role': role, 'content': content};
}

class ToolTraceEvent {
  final String tool;
  final String phase; // start | result
  final String details;
  final DateTime timestamp;

  ToolTraceEvent({
    required this.tool,
    required this.phase,
    required this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// Chat session model
class ChatSession {
  final String id;
  final String title;
  final String modelMode;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    this.title = 'New Chat',
    this.modelMode = 'economy',
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  ChatSession copyWith({
    String? title,
    String? modelMode,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      modelMode: modelMode ?? this.modelMode,
      messages: messages ?? this.messages,
    );
  }
}

class SkillItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final String minPlan;
  final String sourceUrl;
  final String provider;
  final List<String> tools;

  const SkillItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.minPlan,
    required this.sourceUrl,
    required this.provider,
    required this.tools,
  });

  factory SkillItem.fromJson(Map<String, dynamic> json) {
    return SkillItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      minPlan: json['min_plan'] ?? 'free',
      sourceUrl: json['source_url'] ?? '',
      provider: json['provider'] ?? '',
      tools: List<String>.from(json['tools'] ?? const []),
    );
  }
}

class ProjectItem {
  final String id;
  final String name;
  final String description;

  const ProjectItem({
    required this.id,
    required this.name,
    required this.description,
  });

  factory ProjectItem.fromJson(Map<String, dynamic> json) {
    return ProjectItem(
      id: json['project_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

class ProjectSourceItem {
  final String sourceId;
  final String projectId;
  final String sourceType;
  final String name;
  final String contentText;
  final String filePath;
  final String linkUrl;
  final String createdAt;

  const ProjectSourceItem({
    required this.sourceId,
    required this.projectId,
    required this.sourceType,
    required this.name,
    required this.contentText,
    required this.filePath,
    required this.linkUrl,
    required this.createdAt,
  });

  factory ProjectSourceItem.fromJson(Map<String, dynamic> json) {
    return ProjectSourceItem(
      sourceId: json['source_id'] ?? '',
      projectId: json['project_id'] ?? '',
      sourceType: json['source_type'] ?? '',
      name: json['name'] ?? '',
      contentText: json['content_text'] ?? '',
      filePath: json['file_path'] ?? '',
      linkUrl: json['link_url'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class LibrarySourceItem {
  final String sourceId;
  final String sourceType;
  final String name;
  final String contentText;
  final String filePath;
  final String linkUrl;
  final String createdAt;
  final String updatedAt;
  final String metadataJson;

  const LibrarySourceItem({
    required this.sourceId,
    required this.sourceType,
    required this.name,
    required this.contentText,
    required this.filePath,
    required this.linkUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.metadataJson,
  });

  factory LibrarySourceItem.fromJson(Map<String, dynamic> json) {
    return LibrarySourceItem(
      sourceId: json['source_id'] ?? '',
      sourceType: json['source_type'] ?? '',
      name: json['name'] ?? '',
      contentText: json['content_text'] ?? '',
      filePath: json['file_path'] ?? '',
      linkUrl: json['link_url'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      metadataJson: json['metadata_json'] ?? '',
    );
  }
}

class UseCaseTaskItem {
  final String taskId;
  final String title;
  final String description;
  final List<String> defaultSkills;
  final String mode;
  final String category;
  final String minPlan;

  const UseCaseTaskItem({
    required this.taskId,
    required this.title,
    required this.description,
    required this.defaultSkills,
    required this.mode,
    required this.category,
    required this.minPlan,
  });

  factory UseCaseTaskItem.fromJson(Map<String, dynamic> json) {
    return UseCaseTaskItem(
      taskId: json['task_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      defaultSkills: List<String>.from(json['default_skills'] ?? const []),
      mode: json['mode'] ?? 'economy',
      category: json['category'] ?? '',
      minPlan: json['min_plan'] ?? 'free',
    );
  }
}

class UseCaseRoleItem {
  final String roleId;
  final String title;
  final String description;
  final List<UseCaseTaskItem> tasks;

  const UseCaseRoleItem({
    required this.roleId,
    required this.title,
    required this.description,
    required this.tasks,
  });

  factory UseCaseRoleItem.fromJson(Map<String, dynamic> json) {
    final tasksJson = (json['tasks'] as List?) ?? const [];
    return UseCaseRoleItem(
      roleId: json['role_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      tasks: tasksJson
          .map((e) => UseCaseTaskItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class GenericUseCaseSkill {
  final String id;
  final String name;
  final String description;

  const GenericUseCaseSkill({
    required this.id,
    required this.name,
    required this.description,
  });

  factory GenericUseCaseSkill.fromJson(Map<String, dynamic> json) {
    return GenericUseCaseSkill(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

// Chat state
class ChatState {
  final List<ChatSession> sessions;
  final String? activeSessionId;
  final String modelMode;
  final List<SkillItem> skills;
  final List<ProjectItem> projects;
  final List<ProjectSourceItem> projectSources;
  final List<LibrarySourceItem> librarySources;
  final bool sourcesLoading;
  final List<UseCaseRoleItem> useCaseRoles;
  final List<GenericUseCaseSkill> genericUseCaseSkills;
  final List<String> selectedSkillIds;
  final String selectedRoleId;
  final String selectedTaskId;
  final String selectedProjectId;
  final bool isStreaming;
  final String? error;

  const ChatState({
    this.sessions = const [],
    this.activeSessionId,
    this.modelMode = 'economy',
    this.skills = const [],
    this.projects = const [],
    this.projectSources = const [],
    this.librarySources = const [],
    this.sourcesLoading = false,
    this.useCaseRoles = const [],
    this.genericUseCaseSkills = const [],
    this.selectedSkillIds = const [],
    this.selectedRoleId = '',
    this.selectedTaskId = '',
    this.selectedProjectId = '',
    this.isStreaming = false,
    this.error,
  });

  ChatSession? get activeSession {
    if (activeSessionId == null) return null;
    try {
      return sessions.firstWhere((s) => s.id == activeSessionId);
    } catch (_) {
      return null;
    }
  }

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeSessionId,
    String? modelMode,
    List<SkillItem>? skills,
    List<ProjectItem>? projects,
    List<ProjectSourceItem>? projectSources,
    List<LibrarySourceItem>? librarySources,
    bool? sourcesLoading,
    List<UseCaseRoleItem>? useCaseRoles,
    List<GenericUseCaseSkill>? genericUseCaseSkills,
    List<String>? selectedSkillIds,
    String? selectedRoleId,
    String? selectedTaskId,
    String? selectedProjectId,
    bool? isStreaming,
    String? error,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      modelMode: modelMode ?? this.modelMode,
      skills: skills ?? this.skills,
      projects: projects ?? this.projects,
      projectSources: projectSources ?? this.projectSources,
      librarySources: librarySources ?? this.librarySources,
      sourcesLoading: sourcesLoading ?? this.sourcesLoading,
      useCaseRoles: useCaseRoles ?? this.useCaseRoles,
      genericUseCaseSkills: genericUseCaseSkills ?? this.genericUseCaseSkills,
      selectedSkillIds: selectedSkillIds ?? this.selectedSkillIds,
      selectedRoleId: selectedRoleId ?? this.selectedRoleId,
      selectedTaskId: selectedTaskId ?? this.selectedTaskId,
      selectedProjectId: selectedProjectId ?? this.selectedProjectId,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ApiService _api;
  StreamSubscription<ChatStreamEvent>? _streamSubscription;

  ChatNotifier(this._api) : super(const ChatState());

  Future<void> loadSkills() async {
    try {
      final resp = await _api.getSkills();
      if (resp.isSuccess && resp.data is List) {
        final skills = (resp.data as List)
            .map((e) => SkillItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        state = state.copyWith(skills: skills);
        _hydrateUseCasesFromSkillsIfNeeded();
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to load skills: $e');
    }
  }

  Future<void> loadProjects() async {
    try {
      final resp = await _api.getProjects();
      if (resp.isSuccess && resp.data is List) {
        final projects = (resp.data as List)
            .map((e) => ProjectItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        state = state.copyWith(projects: projects);
        if (state.selectedProjectId.isEmpty && projects.isNotEmpty) {
          state = state.copyWith(selectedProjectId: projects.first.id);
          await loadProjectSources(projects.first.id);
        }
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to load projects: $e');
    }
  }

  Future<void> loadSources() async {
    state = state.copyWith(sourcesLoading: true);
    try {
      final resp = await _api.getSources();
      if (resp.isSuccess && resp.data is List) {
        final items = (resp.data as List)
            .map((e) => LibrarySourceItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        state = state.copyWith(librarySources: items, sourcesLoading: false);
      } else {
        state = state.copyWith(sourcesLoading: false, error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to load sources: $e', sourcesLoading: false);
    }
  }

  Future<void> createSource({
    required String sourceType,
    required String name,
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final resp = await _api.createSource(
        sourceType: sourceType,
        name: name,
        contentText: contentText,
        filePath: filePath,
        linkUrl: linkUrl,
        metadata: metadata,
      );
      if (resp.isSuccess) {
        await loadSources();
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to create source: $e');
    }
  }

  Future<void> updateSource({
    required String sourceId,
    required String sourceType,
    required String name,
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final resp = await _api.updateSource(
        sourceId: sourceId,
        sourceType: sourceType,
        name: name,
        contentText: contentText,
        filePath: filePath,
        linkUrl: linkUrl,
        metadata: metadata,
      );
      if (resp.isSuccess) {
        await loadSources();
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to update source: $e');
    }
  }

  Future<void> deleteSource(String sourceId) async {
    try {
      final resp = await _api.deleteSource(sourceId);
      if (resp.isSuccess) {
        await loadSources();
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete source: $e');
    }
  }

  Future<void> createProject({
    required String name,
    String description = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      final resp = await _api.createProject(name: trimmed, description: description);
      if (resp.isSuccess) {
        await loadProjects();
        final id = (resp.data?['project_id'] ?? '').toString();
        if (id.isNotEmpty) {
          await selectProject(id);
        }
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to create project: $e');
    }
  }

  Future<void> loadProjectSources([String? projectId]) async {
    final pid = projectId ?? state.selectedProjectId;
    if (pid.isEmpty) {
      state = state.copyWith(projectSources: const [], sourcesLoading: false);
      return;
    }
    state = state.copyWith(sourcesLoading: true);
    try {
      final resp = await _api.getProjectSources(pid);
      if (resp.isSuccess && resp.data is List) {
        final items = (resp.data as List)
            .map((e) => ProjectSourceItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        state = state.copyWith(projectSources: items, sourcesLoading: false);
      } else {
        state = state.copyWith(sourcesLoading: false, error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to load project sources: $e',
        sourcesLoading: false,
      );
    }
  }

  Future<void> createProjectSource({
    required String sourceType,
    required String name,
    String sourceId = '',
    String contentText = '',
    String filePath = '',
    String linkUrl = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    if (state.selectedProjectId.isEmpty) {
      state = state.copyWith(error: 'Please select a project first');
      return;
    }
    try {
      final resp = await _api.createProjectSource(
        projectId: state.selectedProjectId,
        sourceType: sourceType,
        name: name,
        sourceId: sourceId,
        contentText: contentText,
        filePath: filePath,
        linkUrl: linkUrl,
        metadata: metadata,
      );
      if (resp.isSuccess) {
        await loadProjectSources(state.selectedProjectId);
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to create source: $e');
    }
  }

  Future<void> attachLibrarySourceToProject(String sourceId) async {
    if (state.selectedProjectId.isEmpty) {
      state = state.copyWith(error: 'Please select a project first');
      return;
    }
    final source = state.librarySources.where((s) => s.sourceId == sourceId).toList();
    if (source.isEmpty) {
      state = state.copyWith(error: 'Source not found in library');
      return;
    }
    final s = source.first;
    await createProjectSource(
      sourceType: s.sourceType,
      name: s.name,
      sourceId: s.sourceId,
      contentText: s.contentText,
      filePath: s.filePath,
      linkUrl: s.linkUrl,
      metadata: const {},
    );
  }

  Future<void> removeProjectSource(String sourceId) async {
    if (state.selectedProjectId.isEmpty) {
      state = state.copyWith(error: 'Please select a project first');
      return;
    }
    try {
      final resp = await _api.deleteProjectSource(
        projectId: state.selectedProjectId,
        sourceId: sourceId,
      );
      if (resp.isSuccess) {
        await loadProjectSources(state.selectedProjectId);
      } else {
        state = state.copyWith(error: resp.msg);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to remove project source: $e');
    }
  }

  Future<void> loadUseCases() async {
    try {
      final resp = await _api.getUseCases();
      if (resp.isSuccess && resp.data is Map<String, dynamic>) {
        final data = resp.data as Map<String, dynamic>;
        final roles = ((data['roles'] as List?) ?? const [])
            .map((e) => UseCaseRoleItem.fromJson(Map<String, dynamic>.from(e)))
            .where((r) => r.roleId.isNotEmpty)
            .toList();
        final generic = ((data['generic_skills'] as List?) ?? const [])
            .map(
              (e) => GenericUseCaseSkill.fromJson(Map<String, dynamic>.from(e)),
            )
            .where((g) => g.id.isNotEmpty)
            .toList();

        state = state.copyWith(
          useCaseRoles: roles,
          genericUseCaseSkills: generic,
        );

        if (state.selectedRoleId.isEmpty &&
            state.selectedTaskId.isEmpty &&
            roles.isNotEmpty &&
            roles.first.tasks.isNotEmpty) {
          final firstTask = roles.first.tasks.first;
          state = state.copyWith(
            selectedRoleId: roles.first.roleId,
            selectedTaskId: firstTask.taskId,
            selectedSkillIds: firstTask.defaultSkills,
          );
        }
        if (roles.isEmpty) {
          _hydrateUseCasesFromSkillsIfNeeded();
        }
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to load use-cases: $e');
      _hydrateUseCasesFromSkillsIfNeeded();
    }
  }

  void _hydrateUseCasesFromSkillsIfNeeded() {
    if (state.useCaseRoles.isNotEmpty || state.skills.isEmpty) return;

    const roleOrder = [
      'student',
      'teacher',
      'doctor',
      'lawyer',
      'accountant',
      'support',
      'ecommerce',
    ];
    const roleTitle = {
      'student': '学生',
      'teacher': '老师',
      'doctor': '医生',
      'lawyer': '律师',
      'accountant': '会计',
      'support': '售后',
      'ecommerce': '电商',
    };

    final grouped = <String, List<SkillItem>>{};
    for (final s in state.skills) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    final roles = <UseCaseRoleItem>[];
    for (final rid in roleOrder) {
      final items = grouped[rid] ?? const <SkillItem>[];
      if (items.isEmpty) continue;
      final tasks = items
          .map(
            (s) => UseCaseTaskItem(
              taskId: '$rid.${s.id}',
              title: s.name,
              description: s.description,
              defaultSkills: [s.id],
              mode: 'economy',
              category: rid,
              minPlan: 'free',
            ),
          )
          .toList();
      roles.add(
        UseCaseRoleItem(
          roleId: rid,
          title: roleTitle[rid] ?? rid,
          description: '${roleTitle[rid] ?? rid}技能',
          tasks: tasks,
        ),
      );
    }

    final generic = (grouped['generic'] ?? const <SkillItem>[])
        .map(
          (s) => GenericUseCaseSkill(
            id: s.id,
            name: s.name,
            description: s.description,
          ),
        )
        .toList();

    if (roles.isNotEmpty || generic.isNotEmpty) {
      state = state.copyWith(
        useCaseRoles: roles,
        genericUseCaseSkills: generic,
      );
      if (state.selectedRoleId.isEmpty &&
          roles.isNotEmpty &&
          roles.first.tasks.isNotEmpty) {
        final firstTask = roles.first.tasks.first;
        state = state.copyWith(
          selectedRoleId: roles.first.roleId,
          selectedTaskId: firstTask.taskId,
          selectedSkillIds: firstTask.defaultSkills,
        );
      }
    }
  }

  void toggleSkill(String skillId) {
    final selected = List<String>.from(state.selectedSkillIds);
    if (selected.contains(skillId)) {
      selected.remove(skillId);
    } else {
      selected.add(skillId);
    }
    state = state.copyWith(selectedSkillIds: selected);
  }

  void selectScenario({
    required String roleId,
    required String taskId,
    List<String> defaultSkills = const [],
  }) {
    final knownTaskSkillIDs = state.useCaseRoles
        .expand((r) => r.tasks)
        .expand((t) => t.defaultSkills)
        .toSet();
    final genericIDs = state.genericUseCaseSkills.map((g) => g.id).toSet();

    final kept = state.selectedSkillIds
        .where((id) => genericIDs.contains(id) || !knownTaskSkillIDs.contains(id))
        .toSet();
    kept.addAll(defaultSkills);

    state = state.copyWith(
      selectedRoleId: roleId,
      selectedTaskId: taskId,
      selectedSkillIds: kept.toList(),
    );
  }

  Future<void> selectProject(String projectId) async {
    state = state.copyWith(selectedProjectId: projectId);
    await loadProjectSources(projectId);
  }

  void stopGeneration() {
    if (_streamSubscription != null) {
      _streamSubscription!.cancel();
      _streamSubscription = null;
      state = state.copyWith(isStreaming: false);
    }
  }

  // Load sessions from server
  Future<void> loadSessions() async {
    try {
      final resp = await _api.getSessions();
      if (resp.isSuccess && resp.data is List) {
        final sessions = (resp.data as List).map((s) {
          return ChatSession(
            id: s['session_id'] ?? '',
            title: s['title'] ?? 'Chat',
            modelMode: s['model_mode'] ?? 'economy',
          );
        }).toList();
        state = state.copyWith(sessions: sessions);
        if (state.activeSessionId == null && sessions.isNotEmpty) {
          selectSession(sessions.first.id);
        }
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to load sessions: $e');
    }
  }

  // Create new session
  Future<void> createSession() async {
    try {
      final resp = await _api.createSession(
        title: 'New Chat',
        mode: state.modelMode,
      );
      if (resp.isSuccess) {
        final id = resp.data['session_id'] as String;
        final session = ChatSession(
          id: id,
          title: 'New Chat',
          modelMode: state.modelMode,
        );
        state = state.copyWith(
          sessions: [session, ...state.sessions],
          activeSessionId: id,
        );
      }
    } catch (e) {
      // Create local session if server fails
      final localId = DateTime.now().millisecondsSinceEpoch.toString();
      final session = ChatSession(
        id: localId,
        title: 'New Chat',
        modelMode: state.modelMode,
      );
      state = state.copyWith(
        sessions: [session, ...state.sessions],
        activeSessionId: localId,
      );
    }
  }

  // Select session and load its messages
  Future<void> selectSession(String sessionId) async {
    state = state.copyWith(activeSessionId: sessionId);

    final session = state.sessions.firstWhere((s) => s.id == sessionId);
    if (session.messages.isEmpty) {
      try {
        final resp = await _api.getSession(sessionId);
        if (resp.isSuccess && resp.data != null) {
          final msgsData = resp.data['messages'] as List?;
          if (msgsData != null) {
            final msgs = msgsData.map((m) {
              return ChatMessage(
                role: m['role'] ?? 'user',
                content: m['content'] ?? '',
              );
            }).toList();

            final updatedSessions = state.sessions.map((s) {
              if (s.id == sessionId) {
                return s.copyWith(messages: msgs);
              }
              return s;
            }).toList();

            state = state.copyWith(sessions: updatedSessions);
          }
        }
      } catch (e) {
        debugPrint('Failed to load session messages: $e');
      }
    }
  }

  // Delete session
  Future<void> deleteSession(String sessionId) async {
    try {
      await _api.deleteSession(sessionId);
    } catch (_) {}

    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    String? newActiveId = state.activeSessionId == sessionId
        ? (sessions.isNotEmpty ? sessions.first.id : null)
        : state.activeSessionId;

    state = state.copyWith(sessions: sessions, activeSessionId: newActiveId);
  }

  // Change model mode
  void setModelMode(String mode) {
    state = state.copyWith(modelMode: mode);
  }

  // Send message and stream response
  Future<void> sendMessage(String content) async {
    if (state.isStreaming || content.trim().isEmpty) return;

    // Ensure we have an active session
    if (state.activeSession == null) {
      await createSession();
    }

    final session = state.activeSession;
    if (session == null) return;

    // Add user message
    final userMsg = ChatMessage(role: 'user', content: content);
    final assistantMsg = ChatMessage(
      role: 'assistant',
      content: '',
      isStreaming: true,
    );

    final updatedMessages = [...session.messages, userMsg, assistantMsg];
    _updateSessionMessages(session.id, updatedMessages);
    state = state.copyWith(isStreaming: true, error: null);

    try {
      // Build messages for API (include history)
      final apiMessages = updatedMessages
          .where((m) => !m.isStreaming)
          .map((m) => m.toApiMap())
          .toList();

      final stream = _api.chatStream(
        messages: apiMessages,
        mode: state.modelMode,
        skills: state.selectedSkillIds,
        sessionId: session.id,
        roleId: state.selectedRoleId,
        taskId: state.selectedTaskId,
        projectId: state.selectedProjectId,
      );

      String fullResponse = '';
      String? component;
      Map<String, dynamic>? componentArgs;
      List<ToolTraceEvent> toolEvents = [];
      Map<String, dynamic>? executionSummary;

      final completer = Completer<void>();
      _streamSubscription = stream.listen(
        (event) {
          if (event.type == 'content') {
            fullResponse += event.data;
            _updateCurrentAssistantMessage(
              session.id,
              content: fullResponse,
              component: component,
              componentArgs: componentArgs,
              toolEvents: toolEvents,
              executionSummary: executionSummary,
              isStreaming: true,
            );
          } else if (event.type == 'ui_component') {
            try {
              final uiData = jsonDecode(event.data);
              component = uiData['component'];
              componentArgs = uiData['args'];
              _updateCurrentAssistantMessage(
                session.id,
                content: fullResponse,
                component: component,
                componentArgs: componentArgs,
                toolEvents: toolEvents,
                executionSummary: executionSummary,
                isStreaming: true,
              );
            } catch (e) {
              debugPrint('Failed to decode UI component: $e');
            }
          } else if (event.type == 'tool_call') {
            try {
              final data = jsonDecode(event.data);
              toolEvents = [
                ...toolEvents,
                ToolTraceEvent(
                  tool: '${data['tool'] ?? 'tool'}',
                  phase: 'start',
                  details: jsonEncode(data['args'] ?? {}),
                ),
              ];
              _updateCurrentAssistantMessage(
                session.id,
                content: fullResponse,
                component: component,
                componentArgs: componentArgs,
                toolEvents: toolEvents,
                executionSummary: executionSummary,
                isStreaming: true,
              );
            } catch (_) {}
          } else if (event.type == 'tool_result') {
            try {
              final data = jsonDecode(event.data);
              toolEvents = [
                ...toolEvents,
                ToolTraceEvent(
                  tool: '${data['tool'] ?? 'tool'}',
                  phase: 'result',
                  details: '${data['result'] ?? ''}',
                ),
              ];
              _updateCurrentAssistantMessage(
                session.id,
                content: fullResponse,
                component: component,
                componentArgs: componentArgs,
                toolEvents: toolEvents,
                executionSummary: executionSummary,
                isStreaming: true,
              );
            } catch (_) {}
          } else if (event.type == 'done') {
            try {
              executionSummary = Map<String, dynamic>.from(
                jsonDecode(event.data) as Map,
              );
            } catch (_) {}
            _updateCurrentAssistantMessage(
              session.id,
              content: fullResponse,
              component: component,
              componentArgs: componentArgs,
              toolEvents: toolEvents,
              executionSummary: executionSummary,
              isStreaming: false,
            );

            // Update session title from first user message
            if (session.messages.length <= 2) {
              final title = content.length > 30
                  ? '${content.substring(0, 30)}...'
                  : content;
              _updateSessionTitle(session.id, title);
            }
            completer.complete();
          } else if (event.type == 'error') {
            state = state.copyWith(isStreaming: false, error: event.data);
            _updateCurrentAssistantMessage(
              session.id,
              content: 'Error: ${event.data}',
              component: component,
              componentArgs: componentArgs,
              toolEvents: toolEvents,
              executionSummary: executionSummary,
              isStreaming: false,
            );
            completer.complete();
          }
        },
        onError: (e) {
          state = state.copyWith(isStreaming: false, error: 'Stream error: $e');
          completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
          _streamSubscription = null;
          state = state.copyWith(isStreaming: false);
        },
      );

      await completer.future;
    } catch (e) {
      // Remove streaming assistant message on error if it was empty, or show error
      final updated = List<ChatMessage>.from(updatedMessages);
      if (updated.isNotEmpty &&
          updated.last.isStreaming &&
          updated.last.content.isEmpty) {
        updated[updated.length - 1] = updated.last.copyWith(
          content: 'Stream error: ${e.toString()}',
          isStreaming: false,
        );
      }
      _updateSessionMessages(session.id, updated);
      state = state.copyWith(isStreaming: false, error: 'Stream error: $e');
    } finally {
      state = state.copyWith(isStreaming: false);
    }
  }

  void _updateCurrentAssistantMessage(
    String sessionId, {
    required String content,
    String? component,
    Map<String, dynamic>? componentArgs,
    List<ToolTraceEvent>? toolEvents,
    Map<String, dynamic>? executionSummary,
    required bool isStreaming,
  }) {
    final sessions = state.sessions.map((s) {
      if (s.id == sessionId) {
        final messages = List<ChatMessage>.from(s.messages);
        if (messages.isNotEmpty) {
          messages[messages.length - 1] = messages.last.copyWith(
            content: content,
            component: component,
            componentArgs: componentArgs,
            toolEvents: toolEvents,
            executionSummary: executionSummary,
            isStreaming: isStreaming,
          );
        }
        return s.copyWith(messages: messages);
      }
      return s;
    }).toList();
    state = state.copyWith(sessions: sessions);
  }

  void _updateSessionMessages(String sessionId, List<ChatMessage> messages) {
    final sessions = state.sessions.map((s) {
      if (s.id == sessionId) return s.copyWith(messages: messages);
      return s;
    }).toList();
    state = state.copyWith(sessions: sessions);
  }

  void _updateSessionTitle(String sessionId, String title) {
    final sessions = state.sessions.map((s) {
      if (s.id == sessionId) return s.copyWith(title: title);
      return s;
    }).toList();
    state = state.copyWith(sessions: sessions);
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref.read(apiServiceProvider));
});
