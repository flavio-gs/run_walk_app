// group_page.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ✅ deps pubspec:
//   share_plus: ^10.0.0
//   qr_flutter: ^4.1.0
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'group_task_details_page.dart';
import 'create_group_task_page.dart';

import 'package:run_walk_app/theme/season_theme_scope.dart';

class GroupPage extends StatefulWidget {
  final String groupId;
  const GroupPage({super.key, required this.groupId});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final TabController _tabs;

  DateTime? _requestsLastSeenAt;
  int _tabIndex = 0;

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';
  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

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
    return _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('members')
        .doc(uid)
        .snapshots();
  }

  // =============================================================
  // ✅ MANAGEMENT (owner/admin)
  // =============================================================

  Future<void> _openManageSheet(
      {required bool isOwner, required bool isAdmin}) async {
    if (!isAdmin) return;
    final s = _S(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: s.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: s.border),
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
                    color: s.mutedForeground.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '🛡️ Gerenciar Clã',
                    style: TextStyle(
                      color: s.foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
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
    final s = _S(context);
    final color = destructive ? Colors.redAccent : s.primary;

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
          color: s.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: s.border),
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
                  Text(title,
                      style: TextStyle(
                          color: s.foreground, fontWeight: FontWeight.w900)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: s.mutedForeground,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: s.mutedForeground),
          ],
        ),
      ),
    );
  }

  Future<void> _renameClan() async {
    final s = _S(context);
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.card,
        title: Text('Renomear clã', style: TextStyle(color: s.foreground)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: s.foreground),
          decoration: InputDecoration(
            hintText: 'Novo nome...',
            hintStyle: TextStyle(color: s.mutedForeground),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: s.mutedForeground))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Salvar',
                  style: TextStyle(color: s.primary, fontWeight: FontWeight.w900))),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Nome atualizado ✅')));
  }

  // ✅ convite link simples (troca depois por Firebase Dynamic Links)
  String _randToken([int len = 18]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
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
    final s = _S(context);
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
              color: s.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: s.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: s.mutedForeground.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'QR Code do convite',
                  style: TextStyle(
                      color: s.foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
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
                    child: QrImageView(data: link),
                  ),
                ),

                const SizedBox(height: 12),
                SelectableText(
                  link,
                  style: TextStyle(
                      color: s.mutedForeground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
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
                      backgroundColor: s.primary,
                      foregroundColor: s.primaryForeground,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Compartilhar',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),

                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Fechar',
                      style: TextStyle(
                          color: s.mutedForeground,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteClanSoft() async {
    final s = _S(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.card,
        title: Text('Excluir clã?', style: TextStyle(color: s.foreground)),
        content: Text(
          'Isso vai esconder o clã no app (soft-delete). Recomendo essa opção.\n\nConfirmar?',
          style: TextStyle(color: s.mutedForeground),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: s.mutedForeground))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w900))),
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
    final s = _S(context);

    final snap = await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();

    if (snap.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sem tasks pra excluir.')));
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: s.border),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Escolha a task pra excluir',
                  style: TextStyle(
                      color: s.foreground, fontWeight: FontWeight.w900),
                ),
              ),
              ...snap.docs.map((d) {
                final t = d.data();
                final title = (t['title'] ?? 'Task').toString();
                return ListTile(
                  title: Text(title, style: TextStyle(color: s.foreground)),
                  subtitle: Text(d.id,
                      style: TextStyle(
                          color: s.mutedForeground, fontSize: 12)),
                  trailing: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
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
    await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .doc(chosen)
        .set({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Task excluída ✅')));
  }

  Future<void> _openInvitePeople() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => InvitePeoplePage(groupId: widget.groupId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _groupStream(),
          builder: (_, snap) {
            final data = snap.data?.data();
            final name = (data?['name'] ?? 'Grupo').toString();
            return Text(
              name,
              style: TextStyle(
                color: s.foreground,
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
                onPressed: () =>
                    _openManageSheet(isOwner: isOwner, isAdmin: isAdmin),
                icon:
                Icon(Icons.settings_rounded, color: s.mutedForeground),
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
                color: s.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.border),
              ),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _myMemberStream(),
                builder: (_, memberSnap) {
                  final role =
                  (memberSnap.data?.data()?['role'] ?? 'member').toString();
                  final isAdmin = _isAdminRole(role);

                  final Stream<QuerySnapshot<Map<String, dynamic>>>
                  pendingStream = isAdmin
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

                          if (createdAt == null) return true;
                          if (_requestsLastSeenAt == null) return true;
                          return createdAt.isAfter(_requestsLastSeenAt!);
                        }).length;

                        if (_tabIndex == 3) badgeCount = 0;
                      }

                      return TabBar(
                        controller: _tabs,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: s.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        labelColor: s.primaryForeground,
                        unselectedLabelColor: s.mutedForeground,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                        tabs: [
                          const Tab(text: 'Participantes'),
                          const Tab(text: 'Desafios'),
                          const Tab(text: 'Chat'),
                          if (isAdmin)
                            _TabWithBadge(
                              text: 'Pedidos',
                              count: badgeCount,
                              theme: s,
                            )
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

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

  Future<void> _removeMember({
    required BuildContext context,
    required FirebaseFirestore db,
    required String groupId,
    required String targetUid,
    required String targetName,
  }) async {
    final s = _S(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.card,
        title: Text('Remover participante?', style: TextStyle(color: s.foreground)),
        content: Text(
          'Remover $targetName do clã?',
          style: TextStyle(color: s.mutedForeground),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: TextStyle(color: s.mutedForeground))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Remover', style: TextStyle(color: s.primary, fontWeight: FontWeight.w900))),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Participante removido ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final db = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final myUid = auth.currentUser?.uid;

    return Container(
      color: s.background,
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
                        return Center(child: CircularProgressIndicator(color: s.primary));
                      }

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Sem membros ainda 😶',
                            style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
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
                              color: s.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: s.border),
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
                                    border: Border.all(color: s.primary.withOpacity(0.8), width: 1.2),
                                  ),
                                  child: ClipOval(
                                    child: photo.isNotEmpty
                                        ? Image.network(
                                      photo,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Icon(Icons.person, color: s.mutedForeground),
                                    )
                                        : Icon(Icons.person, color: s.mutedForeground),
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
                                        style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        role.toUpperCase(),
                                        style: TextStyle(
                                          color: s.mutedForeground,
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
                                  style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w900),
                                ),

                                if (isAdmin && !isMe) ...[
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    color: s.card,
                                    icon: Icon(Icons.more_vert_rounded, color: s.mutedForeground),
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
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remover do clã', style: TextStyle(color: s.foreground)),
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
            Expanded(
              child: Center(
                child: Text('Você precisa estar logado.', style: TextStyle(color: s.mutedForeground)),
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

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';
  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      color: s.background,
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
                      Expanded(
                        child: Text(
                          '🎯 Tasks do Grupo',
                          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900, fontSize: 16),
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
                            backgroundColor: s.primary,
                            foregroundColor: s.primaryForeground,
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
                  return Center(child: CircularProgressIndicator(color: s.primary));
                }

                final tasks = snap.data!.docs
                    .where((d) => (d.data()['deleted'] == true) ? false : true)
                    .toList();

                if (tasks.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhuma task criada ainda 🚀',
                      style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
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
                        color: s.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: s.border),
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
                            style: TextStyle(
                              color: s.foreground,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(desc, style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700)),
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
                                          backgroundColor: s.primary.withOpacity(0.18),
                                          backgroundImage: p.isNotEmpty ? NetworkImage(p) : null,
                                          child: p.isEmpty ? Icon(Icons.person, size: 16, color: s.mutedForeground) : null,
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  Text(
                                    '${comps.length}',
                                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w900),
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
                                foregroundColor: s.foreground,
                                side: BorderSide(color: s.primary.withOpacity(0.45)),
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

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.primary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.primary.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: s.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: s.primary,
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
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _text = TextEditingController();

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

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

    await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .add({
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
    final s = _S(context);

    return Container(
      color: s.background,
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
                  return Center(child: CircularProgressIndicator(color: s.primary));
                }

                final msgs = snap.data!.docs;

                if (msgs.isEmpty) {
                  return Center(
                    child: Text(
                      'Sem mensagens ainda. Puxa o assunto! 💬',
                      style:
                      TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
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
                        color: s.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: s.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: s.primary.withOpacity(0.18),
                            backgroundImage:
                            photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty
                                ? Icon(Icons.person,
                                color: s.mutedForeground, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: TextStyle(
                                        color: s.foreground,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(text,
                                    style: TextStyle(
                                        color: s.mutedForeground,
                                        fontWeight: FontWeight.w700)),
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
                color: s.card,
                border: Border(top: BorderSide(color: s.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      style: TextStyle(
                          color: s.foreground, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'Mensagem...',
                        hintStyle: TextStyle(color: s.mutedForeground),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: s.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: s.primary.withOpacity(0.25)),
                    ),
                    child: IconButton(
                      splashRadius: 18,
                      onPressed: _send,
                      icon: Icon(Icons.send_rounded, color: s.primary),
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

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';
  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        title: Text(
          'Pedidos de Entrada',
          style: TextStyle(
              color: s.foreground, fontWeight: FontWeight.w900, fontSize: 20),
        ),
      ),
      body: uid == null
          ? Center(
        child: Text('Você precisa estar logado.',
            style: TextStyle(color: s.mutedForeground)),
      )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(uid)
            .snapshots(),
        builder: (_, memberSnap) {
          final role =
          (memberSnap.data?.data()?['role'] ?? 'member').toString();
          final isAdmin = _isAdminRole(role);

          if (!isAdmin) {
            return Center(
              child: Text(
                'Apenas admins podem ver pedidos.',
                style: TextStyle(
                    color: s.mutedForeground,
                    fontWeight: FontWeight.w700),
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
                return Center(
                    child:
                    CircularProgressIndicator(color: s.primary));
              }

              final reqs = snap.data!.docs;
              if (reqs.isEmpty) {
                return Center(
                  child: Text(
                    'Sem pedidos pendentes ✅',
                    style: TextStyle(
                        color: s.mutedForeground,
                        fontWeight: FontWeight.w700),
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
                      final name = (u['displayName'] ??
                          u['name'] ??
                          'Runner')
                          .toString();
                      final photo = (u['photoUrl'] ??
                          u['photoURL'] ??
                          '')
                          .toString();
                      final username = (u['username'] ?? '').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: s.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: s.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: s.primary.withOpacity(0.18),
                              backgroundImage: photo.isNotEmpty
                                  ? NetworkImage(photo)
                                  : null,
                              child: photo.isEmpty
                                  ? Icon(Icons.person,
                                  color: s.mutedForeground)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: s.foreground,
                                        fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    username.isNotEmpty
                                        ? '@$username'
                                        : requesterUid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: s.mutedForeground,
                                        fontWeight: FontWeight.w700),
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
                                    .set({'status': 'rejected'},
                                    SetOptions(merge: true));

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                      content:
                                      Text('Pedido recusado ❌')));
                                }
                              },
                              icon: Icon(Icons.close_rounded,
                                  color: s.mutedForeground),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () async {
                                await db.runTransaction((tx) async {
                                  final groupRef =
                                  db.collection('groups').doc(groupId);
                                  final memberRef = groupRef
                                      .collection('members')
                                      .doc(requesterUid);
                                  final reqRef = groupRef
                                      .collection('join_requests')
                                      .doc(requesterUid);

                                  final mSnap = await tx.get(memberRef);
                                  if (!mSnap.exists) {
                                    tx.set(memberRef, {
                                      'role': 'member',
                                      'uid': requesterUid,
                                      'joinedAt':
                                      FieldValue.serverTimestamp(),
                                      'displayName': name,
                                      'username': username,
                                      'photoUrl': photo,
                                      'xp': 0,
                                      'km': 0,
                                    });
                                    tx.update(groupRef, {
                                      'membersCount':
                                      FieldValue.increment(1)
                                    });
                                  }
                                  tx.set(reqRef, {'status': 'approved'},
                                      SetOptions(merge: true));
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                      content:
                                      Text('Pedido aprovado ✅')));
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: s.primary,
                                foregroundColor: s.primaryForeground,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                              child: const Text('Aprovar',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900)),
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
  final SeasonTheme theme;
  const _TabWithBadge(
      {required this.text, required this.count, required this.theme});

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
// ✅ CONVIDAR (seguindo/seguidores)
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

class _InvitePeoplePageState extends State<InvitePeoplePage>
    with SingleTickerProviderStateMixin {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  late final TabController tabs;

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

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

    final meDoc = await db.collection('users').doc(me).get();
    final meData = meDoc.data() ?? {};
    final fromName =
    (meData['displayName'] ?? meData['name'] ?? 'Runner').toString();
    final fromPhoto =
    (meData['photoUrl'] ?? meData['photoURL'] ?? '').toString();
    final fromUsername = (meData['username'] ?? '').toString();

    await db
        .collection('groups')
        .doc(widget.groupId)
        .collection('invites')
        .doc(targetUid)
        .set({
      'uid': targetUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'fromUid': me,
      'fromName': fromName,
      'fromUsername': fromUsername,
      'fromPhotoUrl': fromPhoto,
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Convite enviado ✅')));
  }

  Widget _userRow(String uid) {
    final s = _S(context);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.collection('users').doc(uid).get(),
      builder: (_, snap) {
        final u = snap.data?.data() ?? {};
        final name = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
        final username = (u['username'] ?? '').toString();
        final photo = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('groups')
              .doc(widget.groupId)
              .collection('members')
              .doc(uid)
              .snapshots(),
          builder: (_, memSnap) {
            final alreadyMember = memSnap.data?.exists == true;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('invites')
                  .doc(uid)
                  .snapshots(),
              builder: (_, invSnap) {
                final inviteStatus =
                (invSnap.data?.data()?['status'] ?? '').toString();
                final invited = inviteStatus == 'pending';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: s.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: s.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: s.primary.withOpacity(0.18),
                        backgroundImage:
                        photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty
                            ? Icon(Icons.person, color: s.mutedForeground)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: s.foreground,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(
                              username.isNotEmpty ? '@$username' : uid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: s.mutedForeground,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (alreadyMember)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: s.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: s.border),
                          ),
                          child: Text('No clã',
                              style: TextStyle(
                                  color: s.mutedForeground,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12)),
                        )
                      else if (invited)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: s.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: s.primary.withOpacity(0.25)),
                          ),
                          child: Text('Convidado',
                              style: TextStyle(
                                  color: s.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12)),
                        )
                      else
                        ElevatedButton(
                          onPressed: () => _invite(uid),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: s.primary,
                            foregroundColor: s.primaryForeground,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          child: const Text('Convidar',
                              style: TextStyle(fontWeight: FontWeight.w900)),
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
    final s = _S(context);
    final me = auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        title: Text(
          'Convidar para o clã',
          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s.border),
              ),
              child: TabBar(
                controller: tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: s.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: s.primaryForeground,
                unselectedLabelColor: s.mutedForeground,
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
          ? Center(
          child: Text('Você precisa estar logado.',
              style: TextStyle(color: s.mutedForeground)))
          : TabBarView(
        controller: tabs,
        physics: const BouncingScrollPhysics(),
        children: [
          // Mutuals
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _followingStream(me),
            builder: (_, folSnap) {
              final followingIds =
                  folSnap.data?.docs.map((d) => d.id).toSet() ??
                      <String>{};

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _followersStream(me),
                builder: (_, ferSnap) {
                  if (!folSnap.hasData || !ferSnap.hasData) {
                    return Center(
                        child:
                        CircularProgressIndicator(color: s.primary));
                  }

                  final followerIds =
                  ferSnap.data!.docs.map((d) => d.id).toSet();
                  final mutuals =
                  followingIds.intersection(followerIds).toList();

                  if (mutuals.isEmpty) {
                    return Center(
                      child: Text(
                        'Sem mutuals ainda 😶',
                        style: TextStyle(
                            color: s.mutedForeground,
                            fontWeight: FontWeight.w700),
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
              if (!snap.hasData) {
                return Center(
                    child:
                    CircularProgressIndicator(color: s.primary));
              }
              final ids = snap.data!.docs.map((d) => d.id).toList();
              if (ids.isEmpty) {
                return Center(
                  child: Text(
                    'Você não segue ninguém ainda 😅',
                    style: TextStyle(
                        color: s.mutedForeground,
                        fontWeight: FontWeight.w700),
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
              if (!snap.hasData) {
                return Center(
                    child:
                    CircularProgressIndicator(color: s.primary));
              }
              final ids = snap.data!.docs.map((d) => d.id).toList();
              if (ids.isEmpty) {
                return Center(
                  child: Text(
                    'Você ainda não tem seguidores 😶',
                    style: TextStyle(
                        color: s.mutedForeground,
                        fontWeight: FontWeight.w700),
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
