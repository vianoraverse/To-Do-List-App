import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TodoApp());

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3B8AC4);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'To-Do List',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 15, color: Colors.black87),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
      ),
      home: const TaskHome(),
    );
  }
}

/* =========================== DOMAIN =========================== */

class Task {
  Task({
    required this.title,
    required this.description,
    this.isDone = false,
    DateTime? createdAt,
    this.dueDate,
  }) : createdAt = createdAt ?? DateTime.now();

  String title;
  String description;
  bool isDone;
  final DateTime createdAt;
  DateTime? dueDate;

  Task copyWith({
    String? title,
    String? description,
    bool? isDone,
    DateTime? dueDate,
  }) {
    return Task(
      title: title ?? this.title,
      description: description ?? this.description,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'isDone': isDone,
    'createdAt': createdAt.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
  };

  factory Task.fromMap(Map<String, dynamic> map) => Task(
    title: map['title'] as String? ?? '',
    description: map['description'] as String? ?? '',
    isDone: map['isDone'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    dueDate: DateTime.tryParse(map['dueDate'] as String? ?? ''),
  );
}

enum TaskFilter { all, today, completed }

class _TaskEditResult {
  _TaskEditResult({required this.task, this.index});
  final Task task;
  final int? index;
}

/* ======================== HOME (LIST) ========================= */

class TaskHome extends StatefulWidget {
  const TaskHome({super.key});
  @override
  State<TaskHome> createState() => _TaskHomeState();
}

class _TaskHomeState extends State<TaskHome> {
  static const String _storageKey = 'todo_breeze_tasks';
  static const String _filterKey = 'todo_breeze_filter';
  static const String _searchKey = 'todo_breeze_search';
  static const String _onboardingKey = 'todo_breeze_onboarding_seen';

  final List<Task> _tasks = <Task>[];
  bool _isLoading = true;
  TaskFilter _filter = TaskFilter.all;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final storedTasks = prefs.getStringList(_storageKey);
    final storedFilter = prefs.getString(_filterKey);
    final savedSearch = prefs.getString(_searchKey) ?? '';
    final onboardSeen = prefs.getBool(_onboardingKey) ?? false;

    final TaskFilter persistedFilter = storedFilter == null
        ? TaskFilter.all
        : TaskFilter.values.firstWhere(
            (e) => e.name == storedFilter,
            orElse: () => TaskFilter.all,
          );

    final loadedTasks = (storedTasks ?? <String>[])
        .map((raw) {
          try {
            return Task.fromMap(jsonDecode(raw) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Task>()
        .toList();

    if (!mounted) return;

    _searchController.value = TextEditingValue(text: savedSearch);
    if (!onboardSeen && loadedTasks.isNotEmpty) {
      _persistOnboarding();
    }

    setState(() {
      _tasks
        ..clear()
        ..addAll(loadedTasks);
      _tasks.sort(_taskSorter);
      _filter = persistedFilter;
      _searchQuery = savedSearch;
      _showOnboarding = loadedTasks.isEmpty && !onboardSeen;
      _isLoading = false;
    });
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _tasks.map((t) => jsonEncode(t.toMap())).toList(),
    );
  }

  void _toggleTaskStatus(int index) {
    setState(() {
      _tasks[index].isDone = !_tasks[index].isDone;
      _tasks.sort(_taskSorter);
    });
    _saveTasks();
  }

  Future<void> _openTaskSheet({Task? task, int? index}) async {
    if (_isLoading) return;

    final result = await showModalBottomSheet<_TaskEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => TaskEditorSheet(task: task, index: index),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (result.index == null) {
        _tasks.add(result.task);
      } else {
        _tasks[result.index!] = result.task;
      }
      _tasks.sort(_taskSorter);
      _showOnboarding = false;
    });
    _saveTasks();
  }

  void _deleteTask(int index) {
    setState(() {
      _tasks.removeAt(index);
      _tasks.sort(_taskSorter);
    });
    _saveTasks();
  }

  void _clearCompleted() {
    setState(() {
      _tasks.removeWhere((t) => t.isDone);
      _tasks.sort(_taskSorter);
    });
    _saveTasks();
  }

  void _dismissOnboarding() {
    if (!_showOnboarding) return;
    setState(() => _showOnboarding = false);
    _persistOnboarding();
  }

  void _updateFilter(TaskFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _persistFilter(filter);
  }

  void _updateSearch(String value) {
    if (_searchQuery == value) return;
    setState(() => _searchQuery = value);
    _persistSearch(value);
  }

  List<Task> get _visibleTasks {
    List<Task> filtered;
    switch (_filter) {
      case TaskFilter.all:
        filtered = List.of(_tasks);
        break;
      case TaskFilter.today:
        filtered = _tasks
            .where(
              (t) =>
                  t.dueDate != null &&
                  isSameDay(t.dueDate!, DateTime.now()) &&
                  !t.isDone,
            )
            .toList();
        break;
      case TaskFilter.completed:
        filtered = _tasks.where((t) => t.isDone).toList();
        break;
    }
    if (_searchQuery.trim().isEmpty) return filtered;
    final q = _searchQuery.toLowerCase();
    return filtered
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q),
        )
        .toList();
  }

  String get _filteredEmptyMessage {
    if (_searchQuery.trim().isNotEmpty) {
      return 'Tidak menemukan tugas yang cocok dengan pencarian "${_searchQuery.trim()}".';
    }
    switch (_filter) {
      case TaskFilter.all:
        return 'Tambahkan beberapa tugas untuk mulai produktif hari ini.';
      case TaskFilter.today:
        return 'Tidak ada tugas yang jatuh tempo hari ini.';
      case TaskFilter.completed:
        return 'Tandai tugas selesai untuk melihatnya di sini.';
    }
  }

  void _persistFilter(TaskFilter filter) {
    SharedPreferences.getInstance().then(
      (p) => p.setString(_filterKey, filter.name),
    );
  }

  void _persistSearch(String value) {
    SharedPreferences.getInstance().then((p) {
      final t = value.trim();
      if (t.isEmpty) {
        p.remove(_searchKey);
      } else {
        p.setString(_searchKey, t);
      }
    });
  }

  void _persistOnboarding() {
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_onboardingKey, true),
    );
  }

  int _taskSorter(Task a, Task b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    final da = a.dueDate, db = b.dueDate;
    if (da != null && db != null) return da.compareTo(db);
    if (da != null) return -1;
    if (db != null) return 1;
    return a.createdAt.compareTo(b.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isDone).length;
    final remaining = total - completed;
    final dueToday = _tasks
        .where(
          (t) => t.dueDate != null && isSameDay(t.dueDate!, DateTime.now()),
        )
        .length;
    final visible = _visibleTasks;
    final showDefaultEmpty = total == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do List'),
        actions: [
          IconButton(
            tooltip: 'Tambah cepat',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _isLoading ? null : () => _openTaskSheet(),
          ),
          if (_tasks.any((t) => t.isDone))
            PopupMenuButton<String>(
              onSelected: (v) =>
                  v == 'clear_completed' ? _clearCompleted() : null,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clear_completed',
                  child: Text('Hapus tugas selesai'),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showOnboarding && _searchQuery.isEmpty)
                      _OnboardingBanner(
                        onCreate: () => _openTaskSheet(),
                        onDismiss: _dismissOnboarding,
                      ),
                    if (_showOnboarding && _searchQuery.isEmpty)
                      const SizedBox(height: 16),
                    _StatsCard(
                      total: total,
                      completed: completed,
                      remaining: remaining,
                      dueToday: dueToday,
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<TaskFilter>(
                      segments: const [
                        ButtonSegment(
                          value: TaskFilter.all,
                          icon: Icon(Icons.view_stream_outlined),
                          label: Text('Semua'),
                        ),
                        ButtonSegment(
                          value: TaskFilter.today,
                          icon: Icon(Icons.today_outlined),
                          label: Text('Hari ini'),
                        ),
                        ButtonSegment(
                          value: TaskFilter.completed,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text('Selesai'),
                        ),
                      ],
                      selected: <TaskFilter>{_filter},
                      onSelectionChanged: (s) => _updateFilter(s.first),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _searchController,
                      onChanged: _updateSearch,
                      decoration: InputDecoration(
                        hintText: 'Cari tugas atau catatan...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.trim().isNotEmpty
                            ? IconButton(
                                tooltip: 'Bersihkan',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  _updateSearch('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (visible.isEmpty)
                      _EmptyState(
                        title: showDefaultEmpty
                            ? 'Belum ada tugas'
                            : 'Tidak ada tugas',
                        subtitle: showDefaultEmpty
                            ? 'Tekan tombol + untuk mulai menambahkan to-do list kamu.'
                            : _filteredEmptyMessage,
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final task = visible[i];
                          final idx = _tasks.indexWhere(
                            (o) => o.createdAt == task.createdAt,
                          );
                          if (idx == -1) return const SizedBox();
                          return Dismissible(
                            key: ValueKey(
                              task.createdAt.millisecondsSinceEpoch,
                            ),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) => _deleteTask(idx),
                            child: _TaskCard(
                              task: task,
                              onTap: () => _toggleTaskStatus(idx),
                              onEdit: () =>
                                  _openTaskSheet(task: task, index: idx),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openTaskSheet(),
              icon: const Icon(Icons.add),
              label: const Text('Tugas Baru'),
            ),
    );
  }
}

/* ====================== EDITOR BOTTOM SHEET ====================== */

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({super.key, this.task, this.index});
  final Task? task;
  final int? index;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descController = TextEditingController(
      text: widget.task?.description ?? '',
    );
    _selectedDueDate = widget.task?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.task != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Edit Tugas' : 'Tambah Tugas',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Judul',
                hintText: 'Contoh: Belajar Flutter',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Judul tidak boleh kosong.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Deskripsi',
                hintText: 'Tambahkan catatan penting',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _selectedDueDate == null
                          ? 'Pilih jatuh tempo'
                          : 'Jatuh tempo ${formatDate(_selectedDueDate!)}',
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final initial =
                          _selectedDueDate ?? now.add(const Duration(days: 1));
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (!mounted) return; // PENTING
                      if (picked != null) {
                        setState(() => _selectedDueDate = picked);
                      }
                    },
                  ),
                ),
                if (_selectedDueDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Hapus tanggal',
                    onPressed: () => setState(() => _selectedDueDate = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),
            if (isEdit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Tandai selesai'),
                  const SizedBox(width: 8),
                  Switch(
                    value: widget.task!.isDone,
                    onChanged: (v) => setState(() => widget.task!.isDone = v),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState?.validate() != true) return;

                final task = Task(
                  title: _titleController.text.trim(),
                  description: _descController.text.trim(),
                  isDone: widget.task?.isDone ?? false,
                  createdAt: widget.task?.createdAt,
                  dueDate: _selectedDueDate,
                );
                final result = _TaskEditResult(task: task, index: widget.index);

                // KUNCI: tutup sheet setelah frame ini selesai
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) Navigator.of(context).pop(result);
                  });
                }
              },
              child: Text(isEdit ? 'Perbarui' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================ UI PARTS ============================ */

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.total,
    required this.completed,
    required this.remaining,
    required this.dueToday,
  });
  final int total, completed, remaining, dueToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF4ECDC4), Color(0xFF556270)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A111111),
            blurRadius: 10,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ringkasan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              _StatItem(label: 'Total Tugas', value: total.toString()),
              _StatItem(label: 'Tersisa', value: remaining.toString()),
              _StatItem(label: 'Selesai', value: completed.toString()),
              _StatItem(
                label: 'Jatuh tempo Hari Ini',
                value: dueToday.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingBanner extends StatelessWidget {
  const _OnboardingBanner({required this.onCreate, required this.onDismiss});
  final VoidCallback onCreate, onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14111111),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.rocket_launch_outlined,
                size: 28,
                color: Color(0xFF3B8AC4),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selamat datang!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Mulai tracking tugas kamu. Tambahkan to-do pertama dan tandai selesai untuk pantau progres.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tutup panduan',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Tambah tugas pertama'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onDismiss, child: const Text('Nanti saja')),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.color,
    required this.textColor,
  });
  final String label;
  final Color color, textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.onEdit,
  });
  final Task task;
  final VoidCallback onTap, onEdit;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final due = task.dueDate;
    final isOverdue = due != null && due.isBefore(now) && !task.isDone;
    final dueColor = isOverdue
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: task.isDone
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  color: task.isDone
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                ),
                child: task.isDone
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (task.description.isNotEmpty)
                      Text(
                        task.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          decoration: task.isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (due != null)
                          _InfoChip(
                            label: isOverdue
                                ? 'Terlambat!'
                                : 'Jatuh tempo ${formatDate(due)}',
                            color: dueColor.withValues(alpha: 0.1),
                            textColor: dueColor,
                          ),
                        _InfoChip(
                          label: 'Dibuat ${timeAgo(task.createdAt)}',
                          color: Colors.grey.shade200,
                          textColor: Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.title = 'Belum ada tugas',
    this.subtitle = 'Tekan tombol + untuk mulai menambahkan to-do list kamu.',
  });
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            color: Colors.blueGrey.shade200,
            size: 70,
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/* ============================ UTIL ============================ */

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String timeAgo(DateTime date) {
  final d = DateTime.now().difference(date);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  if (d.inDays == 1) return 'kemarin';
  return '${d.inDays} hari lalu';
}

String formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
