// group_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'group_task_details_page.dart';


import 'create_group_task_page.dart';

class GroupPage extends StatefulWidget {
  final String groupId;
  const GroupPage({super.key, required this.groupId});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> with SingleTickerProviderStateMixin {
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Stream<DocumentSnapshot> _groupStream() =>
      _db.collection('groups').doc(widget.groupId).snapshots();

  Stream<DocumentSnapshot> _myMemberStream() {
    final uid = _auth.currentUser?.uid;
    return _db.collection('groups').doc(widget.groupId).collection('members').doc(uid).snapshots();
  }

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: StreamBuilder<DocumentSnapshot>(
          stream: _groupStream(),
          builder: (_, snap) {
            final name = (snap.data?.data() as Map?)?['name']?.toString() ?? 'Grupo';
            return Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.2,
              ),
            );
          },
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _myMemberStream(),
            builder: (_, snap) {
              final role = (snap.data?.data() as Map?)?['role']?.toString() ?? 'member';
              final isAdmin = _isAdminRole(role);

              if (!isAdmin) return const SizedBox.shrink();

              return IconButton(
                tooltip: 'Pedidos',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupJoinRequestsPage(groupId: widget.groupId),
                    ),
                  );
                },
                icon: const Icon(Icons.how_to_reg_rounded, color: Colors.white70),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
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
                  Tab(text: 'Participantes'),
                  Tab(text: 'Desafios'),
                  Tab(text: 'Chat'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const BouncingScrollPhysics(),
        children: [
          _GroupMembersTab(groupId: widget.groupId),
          _GroupTasksTab(groupId: widget.groupId),
          _GroupChatTab(groupId: widget.groupId),
        ],
      ),
    );
  }
}

// =============================================================
// ✅ ABA PARTICIPANTES (ranking por XP; pode trocar para KM depois)
// =============================================================
class _GroupMembersTab extends StatelessWidget {
  final String groupId;
  const _GroupMembersTab({required this.groupId});

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Container(
      color: kBg,
      child: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .orderBy('xp', descending: true)
            .limit(200)
            .snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kOrange));
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Sem membros ainda 😶',
                style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final m = docs[i].data() as Map<String, dynamic>;
              final name = (m['displayName'] ?? 'Runner').toString();
              final photo = (m['photoUrl'] ?? '').toString();
              final xp = (m['xp'] ?? 0);
              final role = (m['role'] ?? 'member').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kOrange.withOpacity(0.8), width: 1.2),
                      ),
                      child: ClipOval(
                        child: photo.isNotEmpty
                            ? Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white70),
                        )
                            : const Icon(Icons.person, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}º  $name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$xp XP',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================
// ✅ ABA DESAFIOS/TASKS (admin cria; membros concluem; miniaturas)
// =============================================================
class _GroupTasksTab extends StatelessWidget {
  final String groupId;
  const _GroupTasksTab({required this.groupId});

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      color: kBg,
      child: Column(
        children: [
          if (uid != null)
            StreamBuilder<DocumentSnapshot>(
              stream: db.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
              builder: (_, snap) {
                final role = (snap.data?.data() as Map?)?['role']?.toString() ?? 'member';
                final isAdmin = _isAdminRole(role);

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '🎯 Tasks do Grupo',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      if (isAdmin)
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => CreateGroupTaskPage(groupId: groupId)),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: kOrange,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Criar', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                );
              },
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('groups')
                  .doc(groupId)
                  .collection('tasks')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: kOrange));
                }

                final tasks = snap.data!.docs;
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhuma task criada ainda 🚀',
                      style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) {
                    final tDoc = tasks[i];
                    final t = tDoc.data() as Map<String, dynamic>;

                    final title = (t['title'] ?? 'Task').toString();
                    final desc = (t['description'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== Header =====
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),

                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              desc,
                              style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                            ),
                          ],

                          const SizedBox(height: 10),

                          // ===== Chips resumo =====
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MiniChip(icon: Icons.sports, label: (t['mode'] ?? 'Corrida').toString()),
                              if (t['goalKm'] != null)
                                _MiniChip(
                                  icon: Icons.flag_rounded,
                                  label: '${(t['goalKm'] as num).toDouble().toStringAsFixed(1)} km',
                                ),
                              if (t['isLoop'] == true)
                                _MiniChip(
                                  icon: Icons.loop_rounded,
                                  label: 'Loop • ${t['laps'] ?? 1}x',
                                ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // ===== Miniaturas de quem concluiu =====
                          StreamBuilder<QuerySnapshot>(
                            stream: db
                                .collection('groups')
                                .doc(groupId)
                                .collection('tasks')
                                .doc(tDoc.id)
                                .collection('completions')
                                .orderBy('completedAt', descending: true)
                                .limit(8)
                                .snapshots(),
                            builder: (_, compSnap) {
                              final comps = compSnap.data?.docs ?? [];

                              return Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      spacing: 6,
                                      children: comps.map((c) {
                                        final cm = c.data() as Map<String, dynamic>;
                                        final p = (cm['photoUrl'] ?? '').toString();
                                        return CircleAvatar(
                                          radius: 14,
                                          backgroundColor: kOrange.withOpacity(0.2),
                                          backgroundImage: p.isNotEmpty ? NetworkImage(p) : null,
                                          child: p.isEmpty
                                              ? const Icon(Icons.person, size: 16, color: Colors.white70)
                                              : null,
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  Text(
                                    '${comps.length}',
                                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // ===== CTA ABRIR DESAFIO =====
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GroupTaskDetailsPage(
                                      groupId: groupId,
                                      taskId: tDoc.id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.map_rounded),
                              label: const Text('Ver desafio'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: kOrange.withOpacity(0.4)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),

                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniChip({required this.icon, required this.label});

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kOrange),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: kOrange,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}


class _TaskDetailsBlock extends StatelessWidget {
  final Map<String, dynamic> task;
  const _TaskDetailsBlock({required this.task});

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);

  @override
  Widget build(BuildContext context) {
    final mode = (task['mode'] ?? 'Corrida').toString();
    final goalKm = (task['goalKm'] is num) ? (task['goalKm'] as num).toDouble() : null;
    final routeKm = (task['routeKm'] is num) ? (task['routeKm'] as num).toDouble() : 0.0;

    final isLoop = (task['isLoop'] == true);
    final laps = (task['laps'] is num) ? (task['laps'] as num).toInt() : 1;

    final active = task['active'] != false;

    final routeList = (task['route'] is List) ? (task['route'] as List) : const [];
    final points = routeList
        .whereType<Map>()
        .map((p) => LatLng(
      (p['lat'] as num).toDouble(),
      (p['lng'] as num).toDouble(),
    ))
        .toList();

    LatLng? start;
    LatLng? end;

    final rs = task['routeStart'];
    if (rs is Map && rs['lat'] != null && rs['lng'] != null) {
      start = LatLng((rs['lat'] as num).toDouble(), (rs['lng'] as num).toDouble());
    }
    final re = task['routeEnd'];
    if (re is Map && re['lat'] != null && re['lng'] != null) {
      end = LatLng((re['lat'] as num).toDouble(), (re['lng'] as num).toDouble());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(icon: Icons.sports, label: mode),
            if (goalKm != null) _InfoChip(icon: Icons.flag_rounded, label: '${goalKm.toStringAsFixed(2)} km (meta)'),
            _InfoChip(icon: Icons.route_rounded, label: '${routeKm.toStringAsFixed(2)} km (percurso)'),
            if (isLoop) _InfoChip(icon: Icons.loop_rounded, label: 'Loop • $laps voltas'),
            _StatusChip(active: active),
          ],
        ),

        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RoutePreview(points: points, start: start ?? points.first, end: end ?? points.last),
        ] else ...[
          const SizedBox(height: 10),
          const Text(
            'Sem percurso definido 📍',
            style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
          ),
        ],
      ],
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
      height: 160,
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
                  initialCameraPosition: CameraPosition(
                    target: start,
                    zoom: 15,
                  ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.map_outlined, color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Percurso definido (preview)',
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
            style: const TextStyle(
              color: kOrange,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
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
        style: TextStyle(
          color: txt,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}


// =============================================================
// ✅ ABA CHAT INTERNO
// =============================================================
class _GroupChatTab extends StatefulWidget {
  final String groupId;
  const _GroupChatTab({required this.groupId});

  @override
  State<_GroupChatTab> createState() => _GroupChatTabState();
}

class _GroupChatTabState extends State<_GroupChatTab> {
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final msg = _text.text.trim();
    if (msg.isEmpty) return;

    final uDoc = await _db.collection('users').doc(uid).get();
    final u = uDoc.data() ?? <String, dynamic>{};

    await _db.collection('groups').doc(widget.groupId).collection('messages').add({
      'uid': uid,
      'text': msg,
      'createdAt': FieldValue.serverTimestamp(),
      'displayName': (u['displayName'] ?? u['name'] ?? 'Runner').toString(),
      'photoUrl': (u['photoUrl'] ?? u['photoURL'] ?? '').toString(),
    });

    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(120)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: kOrange));
                }

                final msgs = snap.data!.docs;

                if (msgs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Sem mensagens ainda. Puxa o assunto! 💬',
                      style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i].data() as Map<String, dynamic>;
                    final name = (m['displayName'] ?? 'Runner').toString();
                    final text = (m['text'] ?? '').toString();
                    final photo = (m['photoUrl'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: kOrange.withOpacity(0.2),
                            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty
                                ? const Icon(Icons.person, color: Colors.white70, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(text,
                                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: kCard,
                border: const Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        hintText: 'Mensagem...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: kOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kOrange.withOpacity(0.25)),
                    ),
                    child: IconButton(
                      splashRadius: 18,
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, color: kOrange),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// ✅ TELA ADMIN: pedidos pendentes (aprovar/recusar)
// =============================================================
class GroupJoinRequestsPage extends StatelessWidget {
  final String groupId;
  const GroupJoinRequestsPage({super.key, required this.groupId});

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: const Text(
          'Pedidos de Entrada',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
        ),
      ),
      body: uid == null
          ? const Center(
        child: Text('Você precisa estar logado.', style: TextStyle(color: Colors.white60)),
      )
          : StreamBuilder<DocumentSnapshot>(
        stream: db.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
        builder: (_, memberSnap) {
          final role = (memberSnap.data?.data() as Map?)?['role']?.toString() ?? 'member';
          final isAdmin = _isAdminRole(role);

          if (!isAdmin) {
            return const Center(
              child: Text(
                'Apenas admins podem ver pedidos.',
                style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('groups')
                .doc(groupId)
                .collection('join_requests')
                .where('status', isEqualTo: 'pending')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: kOrange));
              }

              final reqs = snap.data!.docs;
              if (reqs.isEmpty) {
                return const Center(
                  child: Text(
                    'Sem pedidos pendentes ✅',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: reqs.length,
                itemBuilder: (_, i) {
                  final rDoc = reqs[i];
                  final r = rDoc.data() as Map<String, dynamic>;
                  final requesterUid = (r['uid'] ?? rDoc.id).toString();

                  return FutureBuilder<DocumentSnapshot>(
                    future: db.collection('users').doc(requesterUid).get(),
                    builder: (_, uSnap) {
                      final u = (uSnap.data?.data() as Map?) ?? {};
                      final name = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
                      final photo = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();
                      final username = (u['username'] ?? '').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: kOrange.withOpacity(0.2),
                              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo.isEmpty
                                  ? const Icon(Icons.person, color: Colors.white70)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    username.isNotEmpty ? '@$username' : requesterUid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Recusar',
                              onPressed: () async {
                                await db
                                    .collection('groups')
                                    .doc(groupId)
                                    .collection('join_requests')
                                    .doc(requesterUid)
                                    .set({'status': 'rejected'}, SetOptions(merge: true));

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Pedido recusado ❌')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.close_rounded, color: Colors.white54),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () async {
                                // aprovar: vira membro + marca request
                                await db.runTransaction((tx) async {
                                  final groupRef = db.collection('groups').doc(groupId);
                                  final memberRef = groupRef.collection('members').doc(requesterUid);
                                  final reqRef = groupRef.collection('join_requests').doc(requesterUid);

                                  final mSnap = await tx.get(memberRef);
                                  if (!mSnap.exists) {
                                    tx.set(memberRef, {
                                      'role': 'member',
                                      'uid': requesterUid,
                                      'joinedAt': FieldValue.serverTimestamp(),
                                      'displayName': name,
                                      'username': username,
                                      'photoUrl': photo,
                                      'xp': 0,
                                      'km': 0,
                                    });
                                    tx.update(groupRef, {'membersCount': FieldValue.increment(1)});
                                  }
                                  tx.set(reqRef, {'status': 'approved'}, SetOptions(merge: true));
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Pedido aprovado ✅')),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: kOrange,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              child: const Text('Aprovar', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
