import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_page.dart'; // 👈 importa o perfil existente

class FollowersPage extends StatefulWidget {
  final String userId;
  final String displayName;

  const FollowersPage({
    super.key,
    required this.userId,
    required this.displayName,
  });

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage>
    with SingleTickerProviderStateMixin {
  final Color orange = const Color(0xFFFF6D00);
  late TabController _tabController;
  final currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        title: Text(
          widget.displayName,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: orange,
          tabs: const [
            Tab(text: "Seguidores"),
            Tab(text: "Seguindo"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList('followers'),
          _buildList('following'),
        ],
      ),
    );
  }

  Widget _buildList(String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection(type)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erro ao carregar.'));
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              type == 'followers'
                  ? 'Nenhum seguidor ainda'
                  : 'Não está seguindo ninguém',
              style: const TextStyle(color: Colors.black54),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final id = docs[index].id;
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(id)
                  .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) {
                  return const ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.grey),
                    title: Text('Carregando...'),
                  );
                }

                final data =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final name = data['displayName'] ?? 'Usuário';
                final username =
                data['username'] != null ? '@${data['username']}' : '';
                final photoURL = data['photoURL'] ?? '';

                final isCurrent = currentUser?.uid == id;

                return ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: photoURL.isNotEmpty
                        ? NetworkImage(photoURL)
                        : null,
                    child: photoURL.isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    username,
                    style: const TextStyle(color: Colors.black54),
                  ),

                  // 👉 abre o perfil ao tocar
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(userId: id),
                      ),
                    );
                  },

                  // botão seguir/deixar de seguir
                  trailing: !isCurrent
                      ? _FollowButton(targetId: id)
                      : const SizedBox.shrink(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FollowButton extends StatefulWidget {
  final String targetId;
  const _FollowButton({required this.targetId});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  final user = FirebaseAuth.instance.currentUser!;
  bool _loading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('following')
        .doc(widget.targetId)
        .get();
    setState(() {
      _isFollowing = doc.exists;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    setState(() => _loading = true);
    final myRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final targetRef =
    FirebaseFirestore.instance.collection('users').doc(widget.targetId);

    if (_isFollowing) {
      await myRef.collection('following').doc(widget.targetId).delete();
      await targetRef.collection('followers').doc(user.uid).delete();
    } else {
      await myRef
          .collection('following')
          .doc(widget.targetId)
          .set({'timestamp': FieldValue.serverTimestamp()});
      await targetRef
          .collection('followers')
          .doc(user.uid)
          .set({'timestamp': FieldValue.serverTimestamp()});
    }

    setState(() {
      _isFollowing = !_isFollowing;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return ElevatedButton(
      onPressed: _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor:
        _isFollowing ? Colors.grey[700] : const Color(0xFFFF6D00),
        foregroundColor: _isFollowing ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(90, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(_isFollowing ? 'Seguindo' : 'Seguir'),
    );
  }
}
