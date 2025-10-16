import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;

class CommentsPage extends StatefulWidget {
  final String postId;
  final String postAuthorId;

  const CommentsPage({super.key, required this.postId, required this.postAuthorId});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final TextEditingController _commentController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser!;

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    // Adiciona o comentário na sub-coleção do post
    await postRef.collection('comments').add({
      'text': text,
      'authorId': _currentUser.uid,
      'authorName': _currentUser.displayName ?? 'Usuário Anônimo',
      'authorPhotoUrl': _currentUser.photoURL ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _commentController.clear();

    // Gera a notificação para o autor do post (se não for o próprio usuário)
    if (_currentUser.uid != widget.postAuthorId) {
      final notificationRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.postAuthorId)
          .collection('notifications');
      
      await notificationRef.add({
        'type': 'comment',
        'commenterId': _currentUser.uid,
        'postId': widget.postId,
        'message': '${_currentUser.displayName ?? 'Alguém'} comentou na sua publicação.',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comentários')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Nenhum comentário ainda.', style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final comment = snapshot.data!.docs[index];
                    final data = comment.data() as Map<String, dynamic>;
                    final time = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

                    return ListTile(
                      leading: CircleAvatar(backgroundImage: NetworkImage(data['authorPhotoUrl'])),
                      title: Text(data['authorName'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['text'], style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(timeago.format(time, locale: 'pt_BR'), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildCommentInputField(),
        ],
      ),
    );
  }

  Widget _buildCommentInputField() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Adicionar um comentário...',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
            onPressed: _postComment,
          ),
        ],
      ),
    );
  }
}
