// group_requests_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupRequestsTab extends StatelessWidget {
  final String groupId;
  final VoidCallback? onViewed; // chama quando a aba é aberta (pra zerar badge)

  const GroupRequestsTab({
    super.key,
    required this.groupId,
    this.onViewed,
  });

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  bool _isAdminRole(String role) => role == 'owner' || role == 'admin';

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(
        child: Text(
          'Faça login para ver pedidos.',
          style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
        ),
      );
    }

    // ✅ Marca como visto assim que renderiza a aba (1ª vez que abriu)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onViewed?.call();
    });

    // Primeiro: checa se é admin/owner
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
      builder: (context, memberSnap) {
        final role = memberSnap.data?.data()?['role']?.toString() ?? 'member';
        final isAdmin = _isAdminRole(role);

        if (!isAdmin) {
          return const Center(
            child: Text(
              'Apenas administradores podem ver pedidos.',
              style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
            ),
          );
        }

        // Lista pedidos pendentes
        return Container(
          color: kBg,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('groups')
                .doc(groupId)
                .collection('join_requests')
                .where('status', isEqualTo: 'pending')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: kOrange));
              }

              final reqs = snap.data!.docs;

              if (reqs.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhum pedido pendente 🚀',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: reqs.length,
                itemBuilder: (context, i) {
                  final rDoc = reqs[i];
                  final r = rDoc.data();
                  final requesterUid = (r['uid'] ?? rDoc.id).toString();

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: db.collection('users').doc(requesterUid).get(),
                    builder: (context, userSnap) {
                      final u = userSnap.data?.data() ?? <String, dynamic>{};
                      final displayName = (u['displayName'] ?? u['name'] ?? 'Runner').toString();
                      final username = (u['username'] ?? '').toString();
                      final photoUrl = (u['photoUrl'] ?? u['photoURL'] ?? '').toString();

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
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: kOrange.withOpacity(0.18),
                              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl.isEmpty
                                  ? const Icon(Icons.person, color: Colors.white70)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                  ),
                                  if (username.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '@$username',
                                      style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),

                            // ✅ Recusar
                            _MiniBtn(
                              label: 'Recusar',
                              bg: Colors.white,
                              fg: Colors.black,
                              onTap: () => _reject(context, db, groupId, requesterUid),
                            ),
                            const SizedBox(width: 8),

                            // ✅ Aceitar
                            _MiniBtn(
                              label: 'Aceitar',
                              bg: kOrange,
                              fg: Colors.black,
                              onTap: () => _approve(context, db, groupId, requesterUid),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _approve(
      BuildContext context,
      FirebaseFirestore db,
      String groupId,
      String requesterUid,
      ) async {
    try {
      final groupRef = db.collection('groups').doc(groupId);
      final reqRef = groupRef.collection('join_requests').doc(requesterUid);
      final memberRef = groupRef.collection('members').doc(requesterUid);

      final uDoc = await db.collection('users').doc(requesterUid).get();
      final u = uDoc.data() ?? <String, dynamic>{};

      await db.runTransaction((tx) async {
        final reqSnap = await tx.get(reqRef);
        if (!reqSnap.exists) return;

        final existingMember = await tx.get(memberRef);
        if (!existingMember.exists) {
          tx.set(memberRef, {
            'role': 'member',
            'uid': requesterUid,
            'joinedAt': FieldValue.serverTimestamp(),
            'displayName': (u['displayName'] ?? u['name'] ?? 'Runner').toString(),
            'username': (u['username'] ?? '').toString(),
            'photoUrl': (u['photoUrl'] ?? u['photoURL'] ?? '').toString(),
            'xp': 0,
            'km': 0,
          });
          tx.update(groupRef, {'membersCount': FieldValue.increment(1)});
        }

        // pode deletar ou marcar status
        tx.set(reqRef, {'status': 'approved', 'handledAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido aprovado ✅')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aprovar: $e')),
        );
      }
    }
  }

  Future<void> _reject(
      BuildContext context,
      FirebaseFirestore db,
      String groupId,
      String requesterUid,
      ) async {
    try {
      final reqRef = db.collection('groups').doc(groupId).collection('join_requests').doc(requesterUid);

      await reqRef.set({
        'status': 'rejected',
        'handledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido recusado ❌')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao recusar: $e')),
        );
      }
    }
  }
}

class _MiniBtn extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}
