import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> followUser(String userIdToFollow) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId == userIdToFollow) return;

    final targetUserDoc = await _db.collection('users').doc(userIdToFollow).get();
    final isPrivate = targetUserDoc.data()?['isPrivate'] ?? false;

    if (isPrivate) {
      await _sendFollowRequest(userIdToFollow);
    } else {
      await _executeFollow(userIdToFollow);
    }
  }

  Future<void> _executeFollow(String userIdToFollow) async {
    final currentUserId = _currentUserId!;
    final userAuth = FirebaseAuth.instance.currentUser;

    // Ações de seguir
    await _db.collection('users').doc(currentUserId).collection('following').doc(userIdToFollow).set({'timestamp': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(userIdToFollow).collection('followers').doc(currentUserId).set({'timestamp': FieldValue.serverTimestamp()});

    final currentUserDoc = await _db.collection('users').doc(currentUserId).get();
    final displayName = currentUserDoc.data()?['displayName'] ?? userAuth?.displayName ?? 'Alguém';
    final photoURL = currentUserDoc.data()?['photoURL'] ?? userAuth?.photoURL;

    await _db.collection('users').doc(userIdToFollow).collection('notifications').add({
      'type': 'follow',
      'senderId': currentUserId,
      'senderName': displayName,
      'senderPhotoUrl': photoURL,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> _sendFollowRequest(String userIdToFollow) async {
    final currentUserId = _currentUserId!;
    final userAuth = FirebaseAuth.instance.currentUser;

    // Adiciona na coleção de solicitações
    await _db.collection('users').doc(userIdToFollow).collection('follow_requests').doc(currentUserId).set({
      'timestamp': FieldValue.serverTimestamp(),
    });

    final currentUserDoc = await _db.collection('users').doc(currentUserId).get();
    final displayName = currentUserDoc.data()?['displayName'] ?? userAuth?.displayName ?? 'Alguém';
    final photoURL = currentUserDoc.data()?['photoURL'] ?? userAuth?.photoURL;

    // Notifica o usuário
    await _db.collection('users').doc(userIdToFollow).collection('notifications').add({
      'type': 'follow_request',
      'senderId': currentUserId,
      'senderName': displayName,
      'senderPhotoUrl': photoURL,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> acceptFollowRequest(String followerId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    // 1. Efetiva o follow
    await _db.collection('users').doc(followerId).collection('following').doc(currentUserId).set({'timestamp': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(currentUserId).collection('followers').doc(followerId).set({'timestamp': FieldValue.serverTimestamp()});

    // 2. Remove a solicitação
    await _db.collection('users').doc(currentUserId).collection('follow_requests').doc(followerId).delete();

    // 3. Opcional: Notificar o usuário que ele foi aceito
  }

  Future<void> declineFollowRequest(String followerId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;
    await _db.collection('users').doc(currentUserId).collection('follow_requests').doc(followerId).delete();
  }

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

  Future<bool> isFollowRequested(String userIdToCheck) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return false;
    final doc = await _db.collection('users').doc(userIdToCheck).collection('follow_requests').doc(currentUserId).get();
    return doc.exists;
  }
}
