// group_page.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ✅ these two need pubspec deps:
//   share_plus: ^10.0.0
//   qr_flutter: ^4.1.0
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  DateTime? _requestsLastSeenAt;
  int _tabIndex = 0;

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  @override
  void initState() {
    super.initState();

    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() => _tabIndex = _tabs.index);

        // ✅ entrou na aba Pedidos -> marca como visto
        if (_tabIndex == 3) {
          _markRequestsSeen();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _markRequestsSeen() {
    setState(() {
      _requestsLastSeenAt = DateTime.now();
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _groupStream() =>
      _db.collection('groups').doc(widget.groupId).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _myMemberStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db.collection('groups').doc(widget.groupId).collection('members').doc(uid).snapshots();
  }

  // =============================================================
  // ✅ MANAGEMENT (owner/admin)
  // =============================================================

  Future<void> _openManageSheet({required bool isOwner, required bool isAdmin}) async {
    if (!isAdmin) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white12),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '🛡️ Gerenciar Clã',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),

                _manageTile(
                  icon: Icons.edit_rounded,
                  title: 'Renomear clã',
                  onTap: _renameClan,
                ),
                _manageTile(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Convidar (seguindo/seguidores)',
                  onTap: _openInvitePeople,
                ),
                _manageTile(
                  icon: Icons.link_rounded,
                  title: 'Gerar link de convite + compartilhar',
                  subtitle: 'WhatsApp, Instagram, etc.',
                  onTap: _shareInviteLink,
                ),
                _manageTile(
                  icon: Icons.qr_code_2_rounded,
                  title: 'Gerar QR Code do convite',
                  onTap: _showInviteQr,
                ),
                _manageTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Excluir desafio',
                  subtitle: 'Escolher um desafio e remover',
                  onTap: _pickAndDeleteTask,
                ),

                if (isOwner) ...[
                  const SizedBox(height: 6),
                  _manageTile(
                    icon: Icons.warning_amber_rounded,
                    title: 'Excluir clã',
                    subtitle: 'Soft-delete (recomendado)',
                    destructive: true,
                    onTap: _deleteClanSoft,
                  ),
                ],

                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _manageTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool destructive = false,
    required VoidCallback onTap,
  }) {
    final color = destructive ? Colors.redAccent : kOrange;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ]
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Future<void> _renameClan() async {
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Renomear clã', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Novo nome...',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );

    if (ok != true) return;

    final name = ctrl.text.trim();
    if (name.isEmpty) return;

    await _db.collection('groups').doc(widget.groupId).update({
      'name': name,
      'searchName': name.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nome atualizado ✅')));
  }

  // ✅ convite link simples (troca depois por Firebase Dynamic Links)
  String _randToken([int len = 18]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> _createInviteLink() async {
    final token = _randToken();

    await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('invite_links')
        .doc(token)
        .set({
      'token': token,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? '',
    });

    // ✅ deep link do seu app (exemplo). Ajuste pro seu schema real.
    return 'runwalk://joinGroup?groupId=${widget.groupId}&token=$token';
  }

  Future<void> _shareInviteLink() async {
    final link = await _createInviteLink();
    await Share.share('⚔️ Entra no meu clã no Runner!\n$link');
  }

  Future<void> _showInviteQr() async {
    final link = await _createInviteLink();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 320, // ✅ largura fixa -> evita Intrinsic
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'QR Code do convite',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),

                // ✅ tamanho fixo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: QrImageView(
                      data: link,
                      // se quiser: version: QrVersions.auto,
                      // se quiser: errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                SelectableText(
                  link,
                  style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Share.share('⚔️ Entra no meu clã no Runner!\n$link');
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: kOrange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Compartilhar', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),

                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Future<void> _deleteClanSoft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Excluir clã?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Isso vai esconder o clã no app (soft-delete). Recomendo essa opção.\n\nConfirmar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );

    if (ok != true) return;

    await _db.collection('groups').doc(widget.groupId).update({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  // ✅ excluir task: por padrão faz SOFT DELETE (evita problema com subcoleções)
  Future<void> _pickAndDeleteTask() async {
    final snap = await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();

    if (snap.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem tasks pra excluir.')));
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: Colors.white12),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Escolha a task pra excluir',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
              ...snap.docs.map((d) {
                final t = d.data();
                final title = (t['title'] ?? 'Task').toString();
                return ListTile(
                  title: Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(d.id, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onTap: () => Navigator.pop(context, d.id),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    if (chosen == null) return;

    // ✅ SOFT DELETE
    await _db.collection('groups').doc(widget.groupId).collection('tasks').doc(chosen).set({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task excluída ✅')));
  }

  Future<void> _openInvitePeople() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvitePeoplePage(groupId: widget.groupId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,

        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _groupStream(),
          builder: (_, snap) {
            final data = snap.data?.data();
            final name = (data?['name'] ?? 'Grupo').toString();
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

        // ✅ botão gerenciar (admin/owner)
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _myMemberStream(),
            builder: (_, snap) {
              final role = (snap.data?.data()?['role'] ?? 'member').toString();
              final isAdmin = _isAdminRole(role);
              final isOwner = role == 'owner';

              if (!isAdmin) return const SizedBox.shrink();

              return IconButton(
                tooltip: 'Gerenciar clã',
                onPressed: () => _openManageSheet(isOwner: isOwner, isAdmin: isAdmin),
                icon: const Icon(Icons.settings_rounded, color: Colors.white70),
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _myMemberStream(),
                builder: (_, memberSnap) {
                  final role = (memberSnap.data?.data()?['role'] ?? 'member').toString();
                  final isAdmin = _isAdminRole(role);

                  // ✅ typed stream (evita Stream<dynamic>)
                  final Stream<QuerySnapshot<Map<String, dynamic>>> pendingStream = isAdmin
                      ? _db
                      .collection('groups')
                      .doc(widget.groupId)
                      .collection('join_requests')
                      .where('status', isEqualTo: 'pending')
                      .snapshots()
                      : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: pendingStream,
                    builder: (_, reqSnap) {
                      int badgeCount = 0;

                      if (isAdmin && reqSnap.hasData) {
                        final docs = reqSnap.data!.docs;

                        badgeCount = docs.where((d) {
                          final data = d.data();
                          final ts = data['createdAt'];
                          DateTime? createdAt;
                          if (ts is Timestamp) createdAt = ts.toDate();

                          if (createdAt == null) return true; // sem createdAt -> conta
                          if (_requestsLastSeenAt == null) return true; // nunca viu -> conta tudo
                          return createdAt.isAfter(_requestsLastSeenAt!); // só novos
                        }).length;

                        // ✅ se estiver na aba pedidos, não mostra badge
                        if (_tabIndex == 3) badgeCount = 0;
                      }

                      return TabBar(
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
                        tabs: [
                          const Tab(text: 'Participantes'),
                          const Tab(text: 'Desafios'),
                          const Tab(text: 'Chat'),
                          if (isAdmin)
                            _TabWithBadge(text: 'Pedidos', count: badgeCount)
                          else
                            const Tab(text: 'Pedidos'),
                        ],
                      );
                    },
                  );
                },
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
          GroupJoinRequestsPage(groupId: widget.groupId),
        ],
      ),
    );
  }
}

// =============================================================
// ✅ ABA PARTICIPANTES (ranking por XP) + remover (admin/owner)
// =============================================================
class _GroupMembersTab extends StatelessWidget {
  final String groupId;
  const _GroupMembersTab({required this.groupId});

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  Future<void> _removeMember({
    required BuildContext context,
    required FirebaseFirestore db,
    required String groupId,
    required String targetUid,
    required String targetName,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Remover participante?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remover $targetName do clã?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ),
    );

    if (ok != true) return;

    await db.runTransaction((tx) async {
      final groupRef = db.collection('groups').doc(groupId);
      final memberRef = groupRef.collection('members').doc(targetUid);
      tx.delete(memberRef);
      tx.update(groupRef, {'membersCount': FieldValue.increment(-1)});
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Participante removido ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final myUid = auth.currentUser?.uid;

    return Container(
      color: kBg,
      child: Column(
        children: [
          if (myUid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db.collection('groups').doc(groupId).collection('members').doc(myUid).snapshots(),
              builder: (_, mySnap) {
                final myRole = (mySnap.data?.data()?['role'] ?? 'member').toString();
                final isAdmin = _isAdminRole(myRole);

                return Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                          final m = docs[i].data();
                          final uid = (m['uid'] ?? docs[i].id).toString();
                          final name = (m['displayName'] ?? 'Runner').toString();
                          final photo = (m['photoUrl'] ?? '').toString();
                          final xp = (m['xp'] ?? 0);
                          final role = (m['role'] ?? 'member').toString();

                          final isMe = uid == myUid;

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
                                      errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.person, color: Colors.white70),
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
                                        '${i + 1}º  $name${isMe ? ' (você)' : ''}',
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

                                // ✅ menu admin (remover)
                                if (isAdmin && !isMe) ...[
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    color: kCard,
                                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white60),
                                    onSelected: (v) async {
                                      if (v == 'remove') {
                                        await _removeMember(
                                          context: context,
                                          db: db,
                                          groupId: groupId,
                                          targetUid: uid,
                                          targetName: name,
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remover do clã', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            )
          else
            const Expanded(
              child: Center(
                child: Text('Você precisa estar logado.', style: TextStyle(color: Colors.white60)),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================
// ✅ ABA DESAFIOS/TASKS (admin cria; membros concluem; miniaturas)
//   - Filtra tasks deletadas (deleted != true)
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
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
              builder: (_, snap) {
                final role = (snap.data?.data()?['role'] ?? 'member').toString();
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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                // ✅ filtra deletadas
                final tasks = snap.data!.docs.where((d) => (d.data()['deleted'] == true) ? false : true).toList();

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
                    final t = tDoc.data();

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
                            Text(desc, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                          ],
                          const SizedBox(height: 10),
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
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                                        final cm = c.data();
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
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GroupTaskDetailsPage(groupId: groupId, taskId: tDoc.id),
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

// =============================================================
// ✅ CHAT INTERNO
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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                    final m = msgs[i].data();
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
// ✅ PEDIDOS (aprovar/recusar)
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
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
        builder: (_, memberSnap) {
          final role = (memberSnap.data?.data()?['role'] ?? 'member').toString();
          final isAdmin = _isAdminRole(role);

          if (!isAdmin) {
            return const Center(
              child: Text(
                'Apenas admins podem ver pedidos.',
                style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  final r = rDoc.data();
                  final requesterUid = (r['uid'] ?? rDoc.id).toString();

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: db.collection('users').doc(requesterUid).get(),
                    builder: (_, uSnap) {
                      final u = uSnap.data?.data() ?? {};
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
                              child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white70) : null,
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

class _TabWithBadge extends StatelessWidget {
  final String text;
  final int count;
  const _TabWithBadge({required this.text, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tab(text: text),
        if (count > 0)
          Positioned(
            right: -10,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================
// ✅ CONVIDAR (seguindo/seguidores) com sua estrutura
// users/{me}/followers/{uid}
// users/{me}/following/{uid}
// Cria convite em groups/{groupId}/invites/{targetUid}
// =============================================================
class InvitePeoplePage extends StatefulWidget {
  final String groupId;
  const InvitePeoplePage({super.key, required this.groupId});

  @override
  State<InvitePeoplePage> createState() => _InvitePeoplePageState();
}

class _InvitePeoplePageState extends State<InvitePeoplePage> with SingleTickerProviderStateMixin {
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  late final TabController tabs;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _followersStream(String uid) =>
      db.collection('users').doc(uid).collection('followers').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> _followingStream(String uid) =>
      db.collection('users').doc(uid).collection('following').snapshots();

  Future<void> _invite(String targetUid) async {
    final me = auth.currentUser?.uid;
    if (me == null) return;

    // pega meus dados básicos
    final meDoc = await db.collection('users').doc(me).get();
    final meData = meDoc.data() ?? {};
    final fromName = (meData['displayName'] ?? meData['name'] ?? 'Runner').toString();
    final fromPhoto = (meData['photoUrl'] ?? meData['photoURL'] ?? '').toString();
    final fromUsername = (meData['username'] ?? '').toString();

    // salva convite
    await db.collection('groups').doc(widget.groupId).collection('invites').doc(targetUid).set({
      'uid': targetUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'fromUid': me,
      'fromName': fromName,
      'fromUsername': fromUsername,
      'fromPhotoUrl': fromPhoto,
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Convite enviado ✅')));
  }

  Widget _userRow(String uid) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.collection('users').doc(uid).get(),
      builder: (_, snap) {
        final u = snap.data?.data() ?? {};
        final name = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
        final username = (u['username'] ?? '').toString();
        final photo = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('groups').doc(widget.groupId).collection('members').doc(uid).snapshots(),
          builder: (_, memSnap) {
            final alreadyMember = memSnap.data?.exists == true;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db.collection('groups').doc(widget.groupId).collection('invites').doc(uid).snapshots(),
              builder: (_, invSnap) {
                final inviteStatus = (invSnap.data?.data()?['status'] ?? '').toString();
                final invited = inviteStatus == 'pending';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: kOrange.withOpacity(0.2),
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white70) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(
                              username.isNotEmpty ? '@$username' : uid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (alreadyMember)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Text('No clã',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 12)),
                        )
                      else if (invited)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: kOrange.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: kOrange.withOpacity(0.25)),
                          ),
                          child: const Text('Convidado',
                              style: TextStyle(color: kOrange, fontWeight: FontWeight.w900, fontSize: 12)),
                        )
                      else
                        ElevatedButton(
                          onPressed: () => _invite(uid),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: kOrange,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          child: const Text('Convidar', style: TextStyle(fontWeight: FontWeight.w900)),
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
  }

  @override
  Widget build(BuildContext context) {
    final me = auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        title: const Text(
          'Convidar para o clã',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
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
                controller: tabs,
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
                  Tab(text: 'Mutuals'),
                  Tab(text: 'Following'),
                  Tab(text: 'Followers'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: me == null
          ? const Center(child: Text('Você precisa estar logado.', style: TextStyle(color: Colors.white60)))
          : TabBarView(
        controller: tabs,
        physics: const BouncingScrollPhysics(),
        children: [
          // Mutuals = interseção
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _followingStream(me),
            builder: (_, folSnap) {
              final followingIds = folSnap.data?.docs.map((d) => d.id).toSet() ?? <String>{};

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _followersStream(me),
                builder: (_, ferSnap) {
                  if (!folSnap.hasData || !ferSnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: kOrange));
                  }

                  final followerIds = ferSnap.data!.docs.map((d) => d.id).toSet();
                  final mutuals = followingIds.intersection(followerIds).toList();

                  if (mutuals.isEmpty) {
                    return const Center(
                      child: Text(
                        'Sem mutuals ainda 😶',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: mutuals.length,
                    itemBuilder: (_, i) => _userRow(mutuals[i]),
                  );
                },
              );
            },
          ),

          // Following
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _followingStream(me),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kOrange));
              final ids = snap.data!.docs.map((d) => d.id).toList();
              if (ids.isEmpty) {
                return const Center(
                  child: Text(
                    'Você não segue ninguém ainda 😅',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: ids.length,
                itemBuilder: (_, i) => _userRow(ids[i]),
              );
            },
          ),

          // Followers
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _followersStream(me),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: kOrange));
              final ids = snap.data!.docs.map((d) => d.id).toList();
              if (ids.isEmpty) {
                return const Center(
                  child: Text(
                    'Você ainda não tem seguidores 😶',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: ids.length,
                itemBuilder: (_, i) => _userRow(ids[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}
