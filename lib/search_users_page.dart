import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/profile_page.dart';

// 1. A classe StatefulWidget (a estrutura principal)
class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

// 2. A classe State (onde toda a lógica e a UI ficam)
class _SearchUsersPageState extends State<SearchUsersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Map<String, bool> _followingStatus = {};

  @override
  void initState() {
    super.initState();
    _loadFollowingStatus();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowingStatus() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final followingSnapshot = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('following')
        .get();
        
    final followingIds = followingSnapshot.docs.map((doc) => doc.id).toSet();
    
    if (mounted) {
      setState(() {
        for (var id in followingIds) {
          _followingStatus[id] = true;
        }
      });
    }
  }

  Future<void> _toggleFollow(String userId, bool isCurrentlyFollowing) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final currentUserRef = _firestore.collection('users').doc(currentUser.uid);
    final targetUserRef = _firestore.collection('users').doc(userId);

    setState(() {
      _followingStatus[userId] = !isCurrentlyFollowing;
    });

    try {
      if (isCurrentlyFollowing) {
        // Deixar de seguir
        await currentUserRef.collection('following').doc(userId).delete();
        await targetUserRef.collection('followers').doc(currentUser.uid).delete();
      } else {
        // Seguir
        final timestamp = FieldValue.serverTimestamp();
        await currentUserRef.collection('following').doc(userId).set({'timestamp': timestamp});
        await targetUserRef.collection('followers').doc(currentUser.uid).set({'timestamp': timestamp});

        // Gerar notificação
        await targetUserRef.collection('notifications').add({
          'type': 'follow',
          'followerId': currentUser.uid,
          'message': '${currentUser.displayName ?? 'Alguém'} começou a seguir você.',
          'timestamp': timestamp,
        });
      }
    } catch (e) {
        setState(() {
          _followingStatus[userId] = isCurrentlyFollowing;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encontrar Pessoas'),
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Pesquisar por nome...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final displayName = (data['displayName'] ?? '').toLowerCase();
                  return displayName.contains(_searchQuery) && doc.id != currentUserId;
                }).toList();

                if (users.isEmpty && _searchQuery.isNotEmpty) {
                  return const Center(
                      child: Text('Nenhum usuário encontrado.', style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final userDoc = users[index];
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final userId = userDoc.id;
                    final isFollowing = _followingStatus[userId] ?? false;

                    return ListTile(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)));
                      },
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(userData['photoURL'] ?? 'https://via.placeholder.com/150'),
                        radius: 25,
                      ),
                      title: Text(userData['displayName'] ?? 'Usuário Anônimo', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(userData['email'] ?? '', style: const TextStyle(color: Colors.white70)),
                      trailing: ElevatedButton(
                        onPressed: () => _toggleFollow(userId, isFollowing),
                        child: Text(isFollowing ? 'Seguindo' : 'Seguir'),
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
