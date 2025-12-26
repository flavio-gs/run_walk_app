// lib/notifications_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/service/service/firestore_service.dart';
import 'package:run_walk_app/widgets/follow_button.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'profile_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  }

  Future<void> _markAsRead(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> _deleteNotification(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('notifications')
        .doc(notificationId)
        .delete();
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final senderId = data['senderId'] as String?;
    if (senderId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePage(userId: senderId),
        ),
      );
    }
  }

  RichText _buildNotificationText(Map<String, dynamic> data) {
    final String senderName = data['senderName'] ?? 'Alguém';
    String messageBody;
    switch (data['type']) {
      case 'follow':
        messageBody = 'começou a seguir você.';
        break;
      case 'follow_request':
        messageBody = 'pediu para seguir você.';
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
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final notificationId = doc.id;
              final type = data['type'];
              final senderId = data['senderId'] as String?;
              final senderPhotoUrl = data['senderPhotoUrl'] as String?;
              final isRead = data['isRead'] ?? false;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Card(
                color: isRead ? Colors.grey[900] : const Color.fromARGB(255, 27, 39, 51),
                margin: EdgeInsets.zero,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      ListTile(
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
                        trailing: (type == 'follow' && senderId != null) ? FollowButton(userId: senderId) : null,
                      ),
                      if (type == 'follow_request' && senderId != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 70.0, vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await _firestoreService.acceptFollowRequest(senderId);
                                    await _deleteNotification(notificationId);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitação aceita!')));
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 8)),
                                  child: const Text('Aceitar', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await _firestoreService.declineFollowRequest(senderId);
                                    await _deleteNotification(notificationId);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitação recusada.')));
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), padding: const EdgeInsets.symmetric(vertical: 8)),
                                  child: const Text('Recusar', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
