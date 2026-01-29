import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_page.dart';
import 'widgets/follow_button.dart';

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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        final docs = snapshot.data?.docs ?? [];
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
            return _UserTile(userId: id);
          },
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final String userId;
  const _UserTile({required this.userId});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const ListTile(
            leading: CircleAvatar(backgroundColor: Colors.grey),
            title: Text('Carregando...'),
          );
        }

        if (!userSnap.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = userSnap.data!.data() as Map<String, dynamic>;
        final name = data['displayName'] ?? 'Usuário';
        final username = data['username'] != null ? '@${data['username']}' : '';
        final photoURL = data['photoURL'] ?? '';

        final isCurrent = currentUser?.uid == userId;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade300,
            backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
            child: photoURL.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          subtitle: Text(
            username,
            style: const TextStyle(color: Colors.black54),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(userId: userId),
              ),
            );
          },
          trailing: !isCurrent ? FollowButton(userId: userId) : null,
        );
      },
    );
  }
}
