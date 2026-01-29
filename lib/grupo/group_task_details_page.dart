// group_task_details_page.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

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

    try {
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
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task concluída ✅')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;

    final taskRef = db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .doc(widget.taskId);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: const Text(
          'Detalhes da Task',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: TabBar(
                controller: _tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: kOrange,
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
            return const Center(
              child: CircularProgressIndicator(color: kOrange),
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

          final task = (snap.data!.data() as Map<String, dynamic>);

          final title = (task['title'] ?? 'Task').toString();
          final desc = (task['description'] ?? '').toString();
          final mode = (task['mode'] ?? 'Corrida').toString();
          final active = task['active'] != false;

          final goalKm = (task['goalKm'] is num) ? (task['goalKm'] as num).toDouble() : null;
          final routeKm = (task['routeKm'] is num) ? (task['routeKm'] as num).toDouble() : 0.0;

          final isLoop = task['isLoop'] == true;
          final laps = (task['laps'] is num) ? (task['laps'] as num).toInt() : 1;

          final routeList = (task['route'] is List) ? (task['route'] as List) : const [];
          final points = routeList
              .whereType<Map>()
              .map((p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ))
              .toList();

          final start = points.isNotEmpty ? points.first : null;
          final end = points.isNotEmpty ? points.last : null;

          final completedRef = (uid == null)
              ? null
              : taskRef.collection('completions').doc(uid);

          return TabBarView(
            controller: _tabs,
            physics: const BouncingScrollPhysics(),
            children: [
              // =========================
              // TAB 1: DETALHES
              // =========================
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            desc,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(icon: Icons.sports, label: mode),
                            _InfoChip(
                              icon: Icons.route_rounded,
                              label: '${routeKm.toStringAsFixed(2)} km (percurso)',
                            ),
                            if (goalKm != null)
                              _InfoChip(
                                icon: Icons.flag_rounded,
                                label: '${goalKm.toStringAsFixed(2)} km (meta)',
                              ),
                            if (isLoop)
                              _InfoChip(
                                icon: Icons.loop_rounded,
                                label: 'Loop • $laps voltas',
                              ),
                            _StatusChip(active: active),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Mapa preview + fullscreen
                  if (points.isNotEmpty && start != null && end != null)
                    _GlassCard(
                      padding: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🗺️ Percurso',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          _RoutePreview(points: points, start: start, end: end),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _RouteFullscreenPage(
                                      points: points,
                                      accent: kOrange,
                                      bg: kBg,
                                      title: title,
                                      isLoop: isLoop,
                                      laps: laps,
                                      routeKm: routeKm,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: kOrange,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.fullscreen_rounded),
                              label: const Text(
                                'Abrir rota (tela cheia)',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _GlassCard(
                      child: const Text(
                        'Sem percurso definido 📍',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                      ),
                    ),

                  const SizedBox(height: 14),

                  // CTA concluir/desfazer
                  if (uid != null && completedRef != null)
                    StreamBuilder<DocumentSnapshot>(
                      stream: completedRef.snapshots(),
                      builder: (context, cSnap) {
                        final isCompleted = cSnap.data?.exists == true;

                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _toggleComplete(
                                  isCompleted: isCompleted,
                                  task: task,
                                ),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: isCompleted ? Colors.white : kOrange,
                                  foregroundColor: isCompleted ? Colors.black : Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  isCompleted ? 'Desfazer conclusão' : 'Concluir task',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _HintText(
                              text: isCompleted
                                  ? 'Você já concluiu. Pode desfazer se marcou sem querer.'
                                  : 'Marque como concluída quando finalizar. MVP manual (depois vira automático).',
                            ),
                          ],
                        );
                      },
                    )
                  else
                    const _HintText(text: 'Faça login para concluir tasks.'),
                ],
              ),

              // =========================
              // TAB 2: CONCLUÍDOS
              // =========================
              StreamBuilder<QuerySnapshot>(
                stream: taskRef
                    .collection('completions')
                    .orderBy('completedAt', descending: true)
                    .snapshots(),
                builder: (context, cSnap) {
                  if (!cSnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: kOrange));
                  }
                  final docs = cSnap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Ninguém concluiu ainda 🚀',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _GlassCard(
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '🏁 Concluídos',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                              ),
                            ),
                            _Pill(text: '${docs.length}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Miniaturas (top)
                      _GlassCard(
                        padding: 12,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: docs.take(24).map((d) {
                            final m = d.data() as Map<String, dynamic>;
                            final p = (m['photoUrl'] ?? '').toString();
                            return CircleAvatar(
                              radius: 18,
                              backgroundColor: kOrange.withOpacity(0.20),
                              backgroundImage: p.isNotEmpty ? NetworkImage(p) : null,
                              child: p.isEmpty
                                  ? const Icon(Icons.person, color: Colors.white70, size: 18)
                                  : null,
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Ranking (ordem de conclusão)
                      _GlassCard(
                        padding: 0,
                        child: Column(
                          children: [
                            for (int i = 0; i < docs.length; i++)
                              _CompletionTile(
                                position: i + 1,
                                data: docs[i].data() as Map<String, dynamic>,
                              ),
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
// FULLSCREEN MAP (gamer)
// =============================================================
class _RouteFullscreenPage extends StatelessWidget {
  final List<LatLng> points;
  final Color accent;
  final Color bg;
  final String title;
  final bool isLoop;
  final int laps;
  final double routeKm;

  const _RouteFullscreenPage({
    required this.points,
    required this.accent,
    required this.bg,
    required this.title,
    required this.isLoop,
    required this.laps,
    required this.routeKm,
  });

  @override
  Widget build(BuildContext context) {
    final start = points.first;
    final end = points.last;

    return Scaffold(
      backgroundColor: bg,
      body: SizedBox.expand(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: start, zoom: 15),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: {
                Marker(markerId: const MarkerId('start'), position: start),
                Marker(markerId: const MarkerId('end'), position: end),
              },
              polylines: {
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: points,
                  width: 7,
                  color: accent,
                  geodesic: true,
                )
              },
            ),

            // TOP BAR
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _GlassIconBtn(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                        accent: accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.map_rounded, color: accent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${routeKm.toStringAsFixed(2)} km',
                                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900),
                                  ),
                                  if (isLoop) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: accent.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: accent.withOpacity(0.45)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.loop_rounded, color: accent, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'LOOP • $laps',
                                            style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// UI COMPONENTS
// =============================================================
class _GlassCard extends StatelessWidget {
  final Widget child;
  final double padding;

  const _GlassCard({required this.child, this.padding = 14});

  static const Color kCard = Color(0xFF12121A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: kOrange.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kOrange.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kOrange),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: kOrange, fontWeight: FontWeight.w900, fontSize: 12),
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
    final bg = active ? const Color(0xFF00D37F).withOpacity(0.14) : Colors.white.withOpacity(0.10);
    final border = active ? const Color(0xFF00D37F).withOpacity(0.35) : Colors.white.withOpacity(0.18);
    final txt = active ? const Color(0xFF00D37F) : Colors.white70;
    final label = active ? 'ATIVA' : 'ENCERRADA';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(color: txt, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.4),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kOrange.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kOrange.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: kOrange, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  const _HintText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
    );
  }
}

class _CompletionTile extends StatelessWidget {
  final int position;
  final Map<String, dynamic> data;

  const _CompletionTile({
    required this.position,
    required this.data,
  });

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    final name = (data['displayName'] ?? 'Runner').toString();
    final photo = (data['photoUrl'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white10,
            child: Text(
              '$position',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: kOrange.withOpacity(0.20),
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white70) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.verified_rounded, color: kOrange, size: 18),
        ],
      ),
    );
  }
}

class _RoutePreview extends StatelessWidget {
  final List<LatLng> points;
  final LatLng start;
  final LatLng end;

  const _RoutePreview({
    required this.points,
    required this.start,
    required this.end,
  });

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: AbsorbPointer(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(target: start, zoom: 15),
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  markers: {
                    Marker(markerId: const MarkerId('start'), position: start),
                    Marker(markerId: const MarkerId('end'), position: end),
                  },
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: points,
                      width: 6,
                      color: kOrange,
                      geodesic: true,
                    )
                  },
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.route_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Preview do percurso',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  const _GlassIconBtn({
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
      ),
    );
  }
}
