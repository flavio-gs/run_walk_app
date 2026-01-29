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

  // Paleta do app (igual SearchUsersPage)
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  bool _sending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    if (_sending) return;

    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    try {
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
          'isRead': false,
        });
      }
    } catch (_) {
      // se quiser, pode mostrar snackbar
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMyCommentMenu({
    required BuildContext context,
    required String commentId,
    required String currentText,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: kOrange),
                  title: const Text(
                    'Editar comentário',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Altere o texto e salve',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openEditCommentDialog(commentId: commentId, currentText: currentText);
                  },
                ),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                  title: const Text(
                    'Excluir comentário',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Essa ação não pode ser desfeita',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _confirmDeleteComment(commentId: commentId);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditCommentDialog({
    required String commentId,
    required String currentText,
  }) async {
    final controller = TextEditingController(text: currentText);
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: kCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text(
                'Editar comentário',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              content: TextField(
                controller: controller,
                cursorColor: kOrange,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Digite seu comentário…',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF0F0F16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: kOrange.withOpacity(0.9), width: 1.2),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                    final newText = controller.text.trim();
                    if (newText.isEmpty) return;

                    setStateDialog(() => saving = true);

                    try {
                      await FirebaseFirestore.instance
                          .collection('posts')
                          .doc(widget.postId)
                          .collection('comments')
                          .doc(commentId)
                          .update({
                        'text': newText,
                        'editedAt': FieldValue.serverTimestamp(),
                      });
                      if (mounted) Navigator.pop(ctx);
                    } finally {
                      setStateDialog(() => saving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOrange,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                      : const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteComment({required String commentId}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Excluir comentário?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Tem certeza que deseja excluir? Essa ação não pode ser desfeita.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Excluir', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ Comentário excluído.')),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOrange),
        title: const Text(
          'Comentários',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCommentsList()),
            _buildCommentInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: kOrange),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return const _EmptyComments();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final comment = snapshot.data!.docs[index];
            final data = comment.data() as Map<String, dynamic>;
            final time =
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            final authorId = (data['authorId'] ?? '').toString();
            final text = (data['text'] ?? '').toString();

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(authorId)
                  .snapshots(),
              builder: (context, userSnapshot) {
                final userData =
                userSnapshot.data?.data() as Map<String, dynamic>?;
                final photoUrl = (userData?['photoURL'] ?? '').toString();
                final authorName =
                (userData?['displayName'] ?? 'Usuário').toString();

                final isMe = authorId == _currentUser.uid;

                return _CommentCard(
                  authorName: authorName,
                  photoUrl: photoUrl,
                  text: text,
                  timeLabel: timeago.format(time, locale: 'pt_BR'),
                  isMe: isMe,
                  onLongPress: isMe
                      ? () => _showMyCommentMenu(
                    context: context,
                    commentId: comment.id,
                    currentText: text,
                  )
                      : null,
                );

              },
            );
          },
        );
      },
    );
  }

  Widget _buildCommentInputField() {
    final hasText = _commentController.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: kBg,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hasText ? kOrange.withOpacity(0.75) : Colors.white12,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _commentController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _postComment(),
                  cursorColor: kOrange,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Adicionar um comentário…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white60,
                      size: 20,
                    ),
                    suffixIcon: hasText
                        ? IconButton(
                      tooltip: 'Limpar',
                      onPressed: () {
                        _commentController.clear();
                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                      ),
                    )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              enabled: hasText && !_sending,
              loading: _sending,
              onTap: _postComment,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyComments extends StatelessWidget {
  const _EmptyComments();

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_rounded, color: Colors.white.withOpacity(0.25), size: 46),
            const SizedBox(height: 12),
            const Text(
              'Ainda não tem comentários.',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Seja o primeiro a comentar e ganhar moral no RunFeed 🧡',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kOrange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kOrange.withOpacity(0.35)),
              ),
              child: const Text(
                'Dica: comentários curtos = mais interação ⚡',
                style: TextStyle(color: kOrange, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final String authorName;
  final String photoUrl;
  final String text;
  final String timeLabel;
  final bool isMe;
  final VoidCallback? onLongPress;

  const _CommentCard({
    required this.authorName,
    required this.photoUrl,
    required this.text,
    required this.timeLabel,
    required this.isMe,
    this.onLongPress,
  });

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kCard = Color(0xFF12121A);

  @override
  Widget build(BuildContext context) {
    final imageProvider = (photoUrl.trim().isNotEmpty)
        ? NetworkImage(photoUrl)
        : const AssetImage('assets/icon/logo_principal.png') as ImageProvider;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onLongPress: onLongPress,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                offset: const Offset(0, 8),
                color: Colors.black.withOpacity(0.28),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (isMe ? kOrange : Colors.white24).withOpacity(0.9),
                    width: 1.2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white10,
                  backgroundImage: imageProvider,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: kOrange.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: kOrange.withOpacity(0.45), width: 1),
                            ),
                            child: const Text(
                              'VOCÊ',
                              style: TextStyle(
                                color: kOrange,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (isMe && onLongPress != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Segure para editar/excluir',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _SendButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: enabled ? kOrange : kOrange.withOpacity(0.35),
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                BoxShadow(
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                  color: kOrange.withOpacity(0.18),
                ),
              ]
                  : null,
            ),
            child: loading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
            )
                : const Icon(Icons.send_rounded, color: Colors.black, size: 20),
          ),
        ),
      ),
    );
  }
}
