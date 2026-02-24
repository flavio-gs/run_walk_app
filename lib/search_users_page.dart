import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/profile_page.dart';

// ✅ importa o scope do tema da season
import 'package:run_walk_app/theme/season_theme_scope.dart';

enum FollowStatus { none, requested, following }

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

  // Status por usuário: none / requested / following
  final Map<String, FollowStatus> _followStatus = {};

  @override
  void initState() {
    super.initState();
    _loadFollowStatus();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cancelFollowRequest(String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final currentUserRef = _firestore.collection('users').doc(currentUser.uid);
    final targetUserRef = _firestore.collection('users').doc(userId);

    // UI otimista
    setState(() => _followStatus[userId] = FollowStatus.none);

    try {
      await targetUserRef
          .collection('follow_requests')
          .doc(currentUser.uid)
          .delete();

      await currentUserRef
          .collection('follow_requests_sent')
          .doc(userId)
          .delete();
    } catch (_) {
      if (!mounted) return;
      setState(() => _followStatus[userId] = FollowStatus.requested);
    }
  }

  Future<void> _confirmCancelRequest(String userId) async {
    final st = SeasonThemeScope.of(context);

    final shouldCancel = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final st = SeasonThemeScope.of(context);
        return AlertDialog(
          backgroundColor: st.popover,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Cancelar solicitação?',
            style: TextStyle(color: st.popoverForeground, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Se você cancelar, precisará solicitar novamente para seguir.',
            style: TextStyle(color: st.mutedForeground, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: st.mutedForeground),
              child: const Text(
                'Voltar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: st.destructive,
                foregroundColor: st.destructiveForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true) {
      await _cancelFollowRequest(userId);
    }
  }

  Future<void> _loadFollowStatus() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final followingSnap = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('following')
        .get();

    final requestsSnap = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('follow_requests_sent')
        .get();

    if (!mounted) return;

    setState(() {
      for (final doc in followingSnap.docs) {
        _followStatus[doc.id] = FollowStatus.following;
      }
      for (final doc in requestsSnap.docs) {
        _followStatus[doc.id] = FollowStatus.requested;
      }
    });
  }

  Future<void> _handleFollow(String userId, bool isPrivate) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final currentStatus = _followStatus[userId] ?? FollowStatus.none;
    if (currentStatus != FollowStatus.none) return;

    final currentUserRef = _firestore.collection('users').doc(currentUser.uid);
    final targetUserRef = _firestore.collection('users').doc(userId);
    final timestamp = FieldValue.serverTimestamp();

    setState(() {
      _followStatus[userId] =
      isPrivate ? FollowStatus.requested : FollowStatus.following;
    });

    try {
      if (isPrivate) {
        await targetUserRef
            .collection('follow_requests')
            .doc(currentUser.uid)
            .set({'timestamp': timestamp});

        await currentUserRef
            .collection('follow_requests_sent')
            .doc(userId)
            .set({'timestamp': timestamp});

        await targetUserRef.collection('notifications').add({
          'type': 'follow_request',
          'senderId': currentUser.uid,
          'senderName': currentUser.displayName ?? 'Alguém',
          'photoUrl': currentUser.photoURL,
          'message': 'enviou uma solicitação para seguir você.',
          'timestamp': timestamp,
        });
      } else {
        await currentUserRef
            .collection('following')
            .doc(userId)
            .set({'timestamp': timestamp});

        await targetUserRef
            .collection('followers')
            .doc(currentUser.uid)
            .set({'timestamp': timestamp});

        await targetUserRef.collection('notifications').add({
          'type': 'follow',
          'followerId': currentUser.uid,
          'senderName': currentUser.displayName ?? 'Alguém',
          'photoUrl': currentUser.photoURL,
          'message': 'começou a seguir você.',
          'timestamp': timestamp,
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _followStatus[userId] = FollowStatus.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);
    final currentUserId = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: st.background,
      appBar: AppBar(
        backgroundColor: st.background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: st.accent),
        title: Text(
          'Encontrar pessoas',
          style: TextStyle(
            color: st.foreground,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: _SearchField(
                controller: _searchController,
                onClear: () {
                  _searchController.clear();
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: st.accent),
                    );
                  }

                  final users = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final displayName =
                    (data['displayName'] ?? '').toString().toLowerCase();

                    return displayName.contains(_searchQuery) &&
                        doc.id != currentUserId;
                  }).toList();

                  if (_searchQuery.isNotEmpty && users.isEmpty) {
                    return const _EmptyState();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final userDoc = users[index];
                      final userData = userDoc.data() as Map<String, dynamic>;
                      final userId = userDoc.id;

                      final name =
                      (userData['displayName'] ?? 'Usuário').toString();
                      final email = (userData['email'] ?? '').toString();
                      final photo = (userData['photoURL'] ?? '').toString();

                      final isPrivate = userData['isPrivate'] == true;
                      final status = _followStatus[userId] ?? FollowStatus.none;

                      return _UserCard(
                        name: name,
                        email: email,
                        photoUrl: photo,
                        status: status,
                        isPrivate: isPrivate,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfilePage(userId: userId),
                            ),
                          );
                        },
                        onFollowTap: () => _handleFollow(userId, isPrivate),
                        onCancelRequest: () => _confirmCancelRequest(userId),
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);
    final hasText = controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: st.input,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasText ? st.ring.withOpacity(0.85) : st.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.35), // sombra pode ficar assim
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(color: st.foreground, fontWeight: FontWeight.w600),
        cursorColor: st.accent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Pesquisar por nome…',
          hintStyle: TextStyle(
            color: st.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: Icon(Icons.search_rounded, color: st.mutedForeground),
          suffixIcon: hasText
              ? IconButton(
            onPressed: onClear,
            icon: Icon(Icons.close_rounded, color: st.mutedForeground),
            tooltip: 'Limpar',
          )
              : null,
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String name;
  final String email;
  final String photoUrl;
  final VoidCallback onCancelRequest;

  final FollowStatus status;
  final bool isPrivate;

  final VoidCallback onTap;
  final VoidCallback onFollowTap;

  const _UserCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.status,
    required this.isPrivate,
    required this.onTap,
    required this.onFollowTap,
    required this.onCancelRequest,
  });

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);

    return Material(
      color: st.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: st.border),
          ),
          child: Row(
            children: [
              _Avatar(photoUrl: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: st.cardForeground,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (isPrivate)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 16,
                              color: st.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: st.mutedForeground,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _FollowButton(
                status: status,
                onFollow: onFollowTap,
                onCancelRequest: onCancelRequest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String photoUrl;

  const _Avatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);

    final imageProvider = (photoUrl.trim().isNotEmpty)
        ? NetworkImage(photoUrl)
        : const NetworkImage('https://via.placeholder.com/150');

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: st.accent.withOpacity(0.9), width: 1.4),
      ),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: st.muted.withOpacity(0.25),
        backgroundImage: imageProvider,
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final FollowStatus status;
  final VoidCallback onFollow;
  final VoidCallback onCancelRequest;

  const _FollowButton({
    required this.status,
    required this.onFollow,
    required this.onCancelRequest,
  });

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);

    switch (status) {
      case FollowStatus.following:
        return OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: st.foreground,
            side: BorderSide(color: st.accent.withOpacity(0.85), width: 1.2),
            backgroundColor: st.muted.withOpacity(0.18),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          child: const Text('Seguindo'),
        );

      case FollowStatus.requested:
        return OutlinedButton(
          onPressed: onCancelRequest,
          style: OutlinedButton.styleFrom(
            foregroundColor: st.foreground,
            side: BorderSide(color: st.border, width: 1.2),
            backgroundColor: st.muted.withOpacity(0.18),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          child: const Text('Solicitado'),
        );

      case FollowStatus.none:
      default:
        return ElevatedButton(
          onPressed: onFollow,
          style: ElevatedButton.styleFrom(
            foregroundColor: st.accentForeground,
            backgroundColor: st.accent,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          child: const Text('Seguir'),
        );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final st = SeasonThemeScope.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded, color: st.mutedForeground, size: 44),
            const SizedBox(height: 12),
            Text(
              'Nenhum usuário encontrado.',
              style: TextStyle(
                color: st.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tente outro nome ou verifique a grafia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: st.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
