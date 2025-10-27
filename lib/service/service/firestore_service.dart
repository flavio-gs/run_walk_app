// ✅ ESTE É O CÓDIGO CORRETO PARA O SERVIÇO
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> followUser(String userIdToFollow) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId == userIdToFollow) return;

    final userAuth = FirebaseAuth.instance.currentUser;

    // Ações de seguir (estas já estão certas)
    await _db.collection('users').doc(currentUserId).collection('following').doc(userIdToFollow).set({'timestamp': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(userIdToFollow).collection('followers').doc(currentUserId).set({'timestamp': FieldValue.serverTimestamp()});

    // --- CRIAÇÃO CORRETA DA NOTIFICAÇÃO ---
    final currentUserDoc = await _db.collection('users').doc(currentUserId).get();
    final displayName = currentUserDoc.data()?['displayName'] ?? userAuth?.displayName ?? 'Alguém';
    final photoURL = currentUserDoc.data()?['photoURL'] ?? userAuth?.photoURL;

    // Adiciona a notificação no perfil do usuário que FOI SEGUIDO
    await _db.collection('users').doc(userIdToFollow).collection('notifications').add({
      // ✅ GARANTE QUE OS CAMPOS CORRETOS SEJAM CRIADOS
      'type': 'follow',
      'senderId': currentUserId,       // Cria o campo 'senderId'
      'senderName': displayName,       // Cria o campo 'senderName'
      'senderPhotoUrl': photoURL,      // Cria o campo 'senderPhotoUrl'
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      // O campo 'message' não é mais necessário aqui
    });
  }

  // O resto das funções (unfollowUser, isFollowing) podem permanecer as mesmas
  Future<void> unfollowUser(String userIdToUnfollow) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;
    await _db.collection('users').doc(currentUserId).collection('following').doc(userIdToUnfollow).delete();
    await _db.collection('users').doc(userIdToUnfollow).collection('followers').doc(currentUserId).delete();
  }

  Future<bool> isFollowing(String userIdToCheck) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return false;
    final doc = await _db.collection('users').doc(currentUserId).collection('following').doc(userIdToCheck).get();
    return doc.exists;
  }
}
