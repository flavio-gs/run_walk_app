// groups_explore_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart'; // ✅ IMPORTA
import 'group_page.dart';

class GroupsExplorePage extends StatefulWidget {
  const GroupsExplorePage({super.key});

  @override
  State<GroupsExplorePage> createState() => _GroupsExplorePageState();
}

class _GroupsExplorePageState extends State<GroupsExplorePage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _search = TextEditingController();
  String _q = '';

  SeasonTheme _S(BuildContext c) => SeasonThemeScope.of(c);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _joinPublicGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final uDoc = await _db.collection('users').doc(uid).get();
    final u = uDoc.data() ?? <String, dynamic>{};

    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(uid);

    await _db.runTransaction((tx) async {
      final existing = await tx.get(memberRef);
      if (!existing.exists) {
        tx.set(memberRef, {
          'role': 'member',
          'uid': uid,
          'joinedAt': FieldValue.serverTimestamp(),
          'displayName': (u['displayName'] ?? u['name'] ?? 'Runner').toString(),
          'username': (u['username'] ?? '').toString(),
          'photoUrl': (u['photoUrl'] ?? u['photoURL'] ?? '').toString(),
          'xp': 0,
          'km': 0,
        });
        tx.update(groupRef, {'membersCount': FieldValue.increment(1)});
      }
    });
  }

  Future<void> _requestToJoin(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final reqRef = _db.collection('groups').doc(groupId).collection('join_requests').doc(uid);

    await reqRef.set({
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    }, SetOptions(merge: true));
  }

  Future<bool> _isMember(String groupId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('groups').doc(groupId).collection('members').doc(uid).get();
    return doc.exists;
  }

  Stream<QuerySnapshot> _groupsStream() {
    final base = _db.collection('groups').orderBy('createdAt', descending: true).limit(50);
    return base.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final uid = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        title: Text(
          'Grupos',
          style: TextStyle(
            color: s.foreground,
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.2,
          ),
        ),
        iconTheme: IconThemeData(color: s.foreground),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: s.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border.withOpacity(0.65)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: s.mutedForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                        style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: 'Buscar clãs...',
                          hintStyle: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w600),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_search.text.isNotEmpty)
                      IconButton(
                        splashRadius: 18,
                        onPressed: () => setState(() {
                          _search.clear();
                          _q = '';
                        }),
                        icon: Icon(Icons.close, color: s.mutedForeground),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _groupsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: s.primary));
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Nenhum clã encontrado 😶',
                        style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                      ),
                    );
                  }

                  final docs = snap.data!.docs.where((d) {
                    final m = d.data() as Map<String, dynamic>;
                    if (m['deleted'] == true) return false;

                    if (_q.isEmpty) return true;

                    final name = (m['name'] ?? '').toString().toLowerCase();
                    final desc = (m['description'] ?? '').toString().toLowerCase();
                    return name.contains(_q) || desc.contains(_q);
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Nada com esse termo 😕',
                        style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>;

                      final name = (m['name'] ?? 'Grupo').toString();
                      final desc = (m['description'] ?? '').toString();
                      final isPublic = (m['isPublic'] ?? true) == true;
                      final ownerId = (m['ownerId'] ?? '').toString();
                      final membersCount = (m['membersCount'] ?? 0);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: s.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: s.border.withOpacity(0.45)),
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
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: s.primary.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: s.primary.withOpacity(0.25)),
                              ),
                              child: Icon(
                                isPublic ? Icons.public_rounded : Icons.lock_rounded,
                                color: s.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        isPublic ? 'Público' : 'Privado',
                                        style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(Icons.people_alt_rounded, size: 16, color: s.mutedForeground.withOpacity(0.7)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$membersCount',
                                        style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
                                      ),
                                      if (uid != null && uid == ownerId) ...[
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: s.primary.withOpacity(0.14),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: s.primary.withOpacity(0.25)),
                                          ),
                                          child: Text(
                                            'ADMIN',
                                            style: TextStyle(
                                              color: s.primary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        )
                                      ],
                                    ],
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: uid == null
                                  ? null
                                  : () async {
                                final alreadyMember = await _isMember(d.id);
                                if (alreadyMember) {
                                  if (!context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => GroupPage(groupId: d.id)),
                                  );
                                  return;
                                }

                                if (isPublic) {
                                  await _joinPublicGroup(d.id);
                                  if (!context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => GroupPage(groupId: d.id)),
                                  );
                                } else {
                                  await _requestToJoin(d.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Pedido enviado ao admin ✉️')),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: isPublic ? s.primary : s.secondary,
                                foregroundColor: isPublic ? s.primaryForeground : s.secondaryForeground,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              child: Text(
                                isPublic ? 'Entrar' : 'Pedir',
                                style: const TextStyle(fontWeight: FontWeight.w900),
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
      ),
    );
  }
}
