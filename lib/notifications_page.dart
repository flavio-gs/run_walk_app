// lib/notifications_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/service/service/firestore_service.dart'; // Mantido, mesmo que não usado na lógica
import 'package:run_walk_app/widgets/follow_button.dart'; // Mantido
import 'package:timeago/timeago.dart' as timeago;

// ✅ Importe a página de perfil
import 'profile_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Garantia: Verifica se o usuário logado não é nulo antes de acessar .uid
  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    // Configura a localização do timeago (já estava correto)
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  }

  // Marca a notificação como lida no Firebase
  Future<void> _markAsRead(String notificationId) async {
    if (!mounted) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // 🌟 LÓGICA DE NAVEGAÇÃO REVISADA 🌟
  void _handleNotificationTap(Map<String, dynamic> data) {
    // Tenta obter o ID do remetente (pessoa que realizou a ação)
    final senderId = data['followerId'] as String?;

    if (senderId != null) {
      // Se houver um ID de remetente, navega para o perfil dele.
      Navigator.push(
        context,
        MaterialPageRoute(
          // O ProfilePage deve aceitar o 'userId' para carregar o perfil
          builder: (context) => ProfilePage(userId: senderId),
        ),
      );
    }
    // Você pode adicionar outras lógicas aqui, como navegar para um PostDetailsPage
    // se o type for 'like' ou 'comment' e houver um 'postId'.
  }

  // Cria o RichText para a mensagem de notificação (já estava correto)
  RichText _buildNotificationText(Map<String, dynamic> data) {
    final String senderName = data['senderName'] ?? 'Alguém';
    String messageBody;
    switch (data['type']) {
      case 'follow':
        messageBody = 'começou a seguir você.';
        break;
      case 'like':
        messageBody = 'curtiu sua publicação.';
        break;
      default:
        messageBody = 'enviou uma notificação.';
        break;
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        children: [
          TextSpan(text: senderName, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: ' $messageBody'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Notificações', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhuma notificação ainda.', style: TextStyle(color: Colors.white70)));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final notificationId = snapshot.data!.docs[index].id;
              final type = data['type'];
              final senderId = data['senderId'] as String?;
              final senderPhotoUrl = data['senderPhotoUrl'] as String?;
              final isRead = data['isRead'] ?? false;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

              Widget? trailingWidget;
              // Mantém o botão de seguir no trailing se for notificação de follow
              if (type == 'follow' && senderId != null) {
                // Assumindo que FollowButton recebe o userId alvo
                trailingWidget = FollowButton(userId: senderId);
              }

              return Card(
                // Usa uma cor mais escura se a notificação não foi lida
                color: isRead ? Colors.grey[900] : const Color.fromARGB(255, 27, 39, 51),
                margin: EdgeInsets.zero,
                elevation: 0,
                child: ListTile(
                  // 🌟 ONTAP: Marca como lida e tenta navegar para o perfil
                  onTap: () {
                    if (!isRead) _markAsRead(notificationId);
                    _handleNotificationTap(data);
                  },
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey.shade800,
                    backgroundImage: senderPhotoUrl != null ? NetworkImage(senderPhotoUrl) : null,
                    child: senderPhotoUrl == null ? const Icon(Icons.person, color: Colors.white70) : null,
                  ),
                  title: _buildNotificationText(data),
                  subtitle: Text(timeago.format(timestamp, locale: 'pt_BR'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  trailing: trailingWidget,
                ),
              );
            },
          );
        },
      ),
    );
  }
}