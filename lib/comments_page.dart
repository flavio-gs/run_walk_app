import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;

class CommentsPage extends StatefulWidget {
  final String postId;
  final String postAuthorId;

  const CommentsPage({
    super.key,
    required this.postId,
    required this.postAuthorId,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final TextEditingController _commentController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser!;

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    await postRef.collection('comments').add({
      'text': text,
      'authorId': _currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _commentController.clear();

    // Notificação para o autor do post (se não for o próprio)
    if (_currentUser.uid != widget.postAuthorId) {
      final notificationRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.postAuthorId)
          .collection('notifications');

      await notificationRef.add({
        'type': 'comment',
        'commenterId': _currentUser.uid,
        'postId': widget.postId,
        'message':
        '${_currentUser.displayName ?? 'Alguém'} comentou na sua publicação.',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comentários')),
      backgroundColor: Colors.white,
      // Isso faz o layout se ajustar automaticamente quando o teclado aparece
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Lista de comentários
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('comments')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('Nenhum comentário ainda.',
                          style: TextStyle(color: Colors.black)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final comment = snapshot.data!.docs[index];
                      final data = comment.data() as Map<String, dynamic>;
                      final time =
                          (data['timestamp'] as Timestamp?)?.toDate() ??
                              DateTime.now();
                      final authorId = data['authorId'];

                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(authorId)
                            .snapshots(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData ||
                              !userSnapshot.data!.exists) {
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundImage:
                                AssetImage('assets/icon/logo_principal.png'),
                                radius: 20,
                              ),
                              title: const Text('Usuário desconhecido',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black)),
                              subtitle: Text(data['text'] ?? '',
                                  style:
                                  const TextStyle(color: Colors.black)),
                            );
                          }

                          final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>;
                          final photoUrl = userData['photoURL'];
                          final authorName =
                              userData['displayName'] ?? 'Usuário Anônimo';

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundImage:
                              (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : const AssetImage(
                                  'assets/icon/logo_principal.png')
                              as ImageProvider,
                            ),
                            title: Text(
                              authorName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['text'] ?? '',
                                    style:
                                    const TextStyle(color: Colors.black)),
                                const SizedBox(height: 4),
                                Text(
                                  timeago.format(time, locale: 'pt_BR'),
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black54),
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
            ),

            // Campo de comentário fixo acima do teclado
            _buildCommentInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentInputField() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _postComment(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Adicionar um comentário...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.grey[850],
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
              onPressed: _postComment,
            ),
          ],
        ),
      ),
    );
  }
}
