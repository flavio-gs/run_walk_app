import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StoryUploadService {
  static final StoryUploadService _instance = StoryUploadService._internal();
  factory StoryUploadService() => _instance;
  StoryUploadService._internal();

  final ValueNotifier<double?> uploadProgress = ValueNotifier<double?>(null);

  Future<void> uploadStory({
    required File? mediaFile,
    required String type,
    required Map<String, dynamic>? selectedMusic,
    required String backgroundColor,
    required List<Map<String, dynamic>> items,
    required String pollQuestion,
    required String option1,
    required String option2,
  }) async {
    try {
      uploadProgress.value = 0.0;
      final user = FirebaseAuth.instance.currentUser!;
      String? mediaUrl;

      if (mediaFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('posts_media')
            .child(user.uid)
            .child('story_${DateTime.now().millisecondsSinceEpoch}');
        
        final uploadTask = ref.putFile(mediaFile);
        
        uploadTask.snapshotEvents.listen((snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          uploadProgress.value = progress.clamp(0.0, 0.99); // Deixa 1% para o Firestore
        });

        await uploadTask;
        mediaUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('stories').add({
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Usuário',
        'authorPhoto': user.photoURL ?? '',
        'type': type,
        'mediaUrl': mediaUrl,
        'backgroundColor': backgroundColor,
        'items': items,
        'timestamp': FieldValue.serverTimestamp(),
        if (selectedMusic != null) 'music': selectedMusic,
        if (type == 'poll') ...{
          'question': pollQuestion,
          'options': [option1, option2],
          'votes': {'0': [], '1': []},
        }
      });

      uploadProgress.value = null; // Finalizado
    } catch (e) {
      uploadProgress.value = null;
      rethrow;
    }
  }
}
