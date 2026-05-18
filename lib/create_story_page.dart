import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';
import 'package:video_player/video_player.dart';

class CreateStoryPage extends StatefulWidget {
  final String type; // 'image', 'video', 'poll'
  const CreateStoryPage({super.key, required this.type});

  @override
  State<CreateStoryPage> createState() => _CreateStoryPageState();
}

class _CreateStoryPageState extends State<CreateStoryPage> {
  final _picker = ImagePicker();
  File? _mediaFile;
  VideoPlayerController? _videoController;
  bool _isUploading = false;

  // Poll fields
  final TextEditingController _pollQuestionController = TextEditingController();
  final TextEditingController _option1Controller = TextEditingController(text: 'Sim');
  final TextEditingController _option2Controller = TextEditingController(text: 'Não');

  @override
  void initState() {
    super.initState();
    if (widget.type != 'poll') {
      _pickMedia();
    }
  }

  Future<void> _pickMedia() async {
    XFile? file;
    if (widget.type == 'image') {
      file = await _picker.pickImage(source: ImageSource.gallery);
    } else if (widget.type == 'video') {
      file = await _picker.pickVideo(source: ImageSource.gallery);
    }

    if (file != null) {
      setState(() {
        _mediaFile = File(file!.path);
      });
      if (widget.type == 'video') {
        _videoController = VideoPlayerController.file(_mediaFile!)
          ..initialize().then((_) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
          });
      }
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pollQuestionController.dispose();
    _option1Controller.dispose();
    _option2Controller.dispose();
    super.dispose();
  }

  Future<void> _uploadStory() async {
    if (widget.type != 'poll' && _mediaFile == null) return;
    if (widget.type == 'poll' && _pollQuestionController.text.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      String? mediaUrl;

      if (_mediaFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('posts_media')
            .child(user.uid)
            .child('story_${DateTime.now().millisecondsSinceEpoch}');
        await ref.putFile(_mediaFile!);
        mediaUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('stories').add({
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Usuário',
        'authorPhoto': user.photoURL ?? '',
        'type': widget.type,
        'mediaUrl': mediaUrl,
        'timestamp': FieldValue.serverTimestamp(),
        if (widget.type == 'poll') ...{
          'question': _pollQuestionController.text,
          'options': [_option1Controller.text, _option2Controller.text],
          'votes': {
            '0': [],
            '1': [],
          },
        }
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story postado com sucesso! 🔥')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao postar story: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isUploading)
            TextButton(
              onPressed: _uploadStory,
              child: const Text(
                'Compartilhar',
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (widget.type == 'image' && _mediaFile != null)
            Center(child: Image.file(_mediaFile!, fit: BoxFit.contain)),
          if (widget.type == 'video' && _videoController != null && _videoController!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),
          if (widget.type == 'poll')
            _buildPollCreator(),
          if (_isUploading)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
            ),
        ],
      ),
    );
  }

  Widget _buildPollCreator() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _pollQuestionController,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20),
                decoration: const InputDecoration(
                  hintText: 'Faça uma pergunta...',
                  hintStyle: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                  border: InputBorder.none,
                ),
              ),
              const Divider(height: 30),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _option1Controller,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.3)),
                  Expanded(
                    child: TextField(
                      controller: _option2Controller,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
