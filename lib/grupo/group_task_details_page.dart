import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// 🔥 mesmo import usado nas outras telas
import '../theme/season_theme_scope.dart';

class GroupTaskDetailsPage extends StatefulWidget {
  final String groupId;
  final String taskId;

  const GroupTaskDetailsPage({
    super.key,
    required this.groupId,
    required this.taskId,
  });

  @override
  State<GroupTaskDetailsPage> createState() => _GroupTaskDetailsPageState();
}

class _GroupTaskDetailsPageState extends State<GroupTaskDetailsPage>
    with SingleTickerProviderStateMixin {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleComplete({
    required bool isCompleted,
    required Map<String, dynamic> task,
    required SeasonTheme theme,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final compRef = db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .doc(widget.taskId)
        .collection('completions')
        .doc(uid);

    if (isCompleted) {
      await compRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conclusão removida ❌')),
        );
      }
      return;
    }

    final uDoc = await db.collection('users').doc(uid).get();
    final u = uDoc.data() ?? <String, dynamic>{};

    await compRef.set({
      'uid': uid,
      'displayName': (u['displayName'] ?? u['name'] ?? 'Runner').toString(),
      'photoUrl': (u['photoUrl'] ?? u['photoURL'] ?? '').toString(),
      'completedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task concluída ✅')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SeasonThemeScope.of(context);
    final uid = auth.currentUser?.uid;

    final taskRef = db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .doc(widget.taskId);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.background,
        surfaceTintColor: theme.background,
        centerTitle: true,
        title: const Text(
          'Detalhes da Task',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: TabBar(
                controller: _tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: 'Detalhes'),
                  Tab(text: 'Concluídos'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: taskRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: theme.accent),
            );
          }

          if (!snap.data!.exists) {
            return const Center(
              child: Text(
                'Task não encontrada 😕',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
              ),
            );
          }

          final task = snap.data!.data() as Map<String, dynamic>;

          final title = (task['title'] ?? 'Task').toString();
          final desc = (task['description'] ?? '').toString();
          final active = task['active'] != false;

          final goalKm =
          task['goalKm'] is num ? (task['goalKm'] as num).toDouble() : null;
          final routeKm =
          task['routeKm'] is num ? (task['routeKm'] as num).toDouble() : 0.0;

          final isLoop = task['isLoop'] == true;
          final laps = (task['laps'] ?? 1) as int;

          final routeList = (task['route'] ?? []) as List;
          final points = routeList
              .whereType<Map>()
              .map((p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ))
              .toList();

          final completedRef =
          uid == null ? null : taskRef.collection('completions').doc(uid);

          return TabBarView(
            controller: _tabs,
            children: [
              // =====================
              // DETALHES
              // =====================
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _GlassCard(
                    theme: theme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            desc,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(
                                icon: Icons.route,
                                label:
                                '${routeKm.toStringAsFixed(2)} km',
                                theme: theme),
                            if (goalKm != null)
                              _InfoChip(
                                  icon: Icons.flag,
                                  label:
                                  '${goalKm.toStringAsFixed(2)} km',
                                  theme: theme),
                            if (isLoop)
                              _InfoChip(
                                  icon: Icons.loop,
                                  label: 'Loop • $laps',
                                  theme: theme),
                            _StatusChip(active: active),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (uid != null && completedRef != null)
                    StreamBuilder<DocumentSnapshot>(
                      stream: completedRef.snapshots(),
                      builder: (context, cSnap) {
                        final isCompleted = cSnap.data?.exists == true;
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _toggleComplete(
                              isCompleted: isCompleted,
                              task: task,
                              theme: theme,
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor:
                              isCompleted ? Colors.white : theme.accent,
                              foregroundColor: Colors.black,
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(16)),
                            ),
                            child: Text(
                              isCompleted
                                  ? 'Desfazer conclusão'
                                  : 'Concluir task',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),

              // =====================
              // CONCLUÍDOS
              // =====================
              StreamBuilder<QuerySnapshot>(
                stream: taskRef
                    .collection('completions')
                    .orderBy('completedAt', descending: true)
                    .snapshots(),
                builder: (context, cSnap) {
                  if (!cSnap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: theme.accent),
                    );
                  }

                  final docs = cSnap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Ninguém concluiu ainda 🚀',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _GlassCard(
                        theme: theme,
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '🏁 Concluídos',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            _Pill(
                                text: '${docs.length}', theme: theme),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================
// UI COMPONENTS
// =============================================================

class _GlassCard extends StatelessWidget {
  final Widget child;
  final SeasonTheme theme;

  const _GlassCard({required this.child, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final SeasonTheme theme;

  const _InfoChip(
      {required this.icon, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.accent.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.w900,
                fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;
  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF00D37F) : Colors.white70;
    final label = active ? 'ATIVA' : 'ENCERRADA';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final SeasonTheme theme;

  const _Pill({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.accent.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: theme.accent,
            fontWeight: FontWeight.w900,
            fontSize: 12),
      ),
    );
  }
}
