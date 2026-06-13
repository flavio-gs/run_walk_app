import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isPosting = false;

  // 📸 / 🎥 Picker
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  XFile? _selectedVideo;

  // 📍 Local
  Position? _selectedPosition;

  // 🏃 Corrida
  String? _selectedRunId;
  Map<String, dynamic>? _selectedRunData;

  // 📊 Progresso de upload (0.0 – 1.0)
  double _uploadProgress = 0.0;

  // 🔹 Escolher imagem (galeria)
  Future<void> _pickImageFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null; // só 1 tipo de mídia
      });
    }
  }

  // 🔹 Tirar foto com câmera
  Future<void> _pickImageFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null;
      });
    }
  }

  // 🔹 Escolher vídeo (galeria) – máx. 10s
  Future<void> _pickVideoFromGallery() async {
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 10),
    );
    if (video != null) {
      setState(() {
        _selectedVideo = video;
        _selectedImage = null;
      });
    }
  }

  // 🔹 Gravar vídeo com câmera – máx. 10s
  Future<void> _pickVideoFromCamera() async {
    final video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 10),
    );
    if (video != null) {
      setState(() {
        _selectedVideo = video;
        _selectedImage = null;
      });
    }
  }

  // 🔹 Remover mídia
  void _clearMedia() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
    });
  }

  // 🔹 Compressão de imagem
  Future<File> _compressImage(File file) async {
    final targetPath = '${file.path}_compressed.jpg';

    final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
    );

    if (compressed == null) {
      return file;
    }

    return File(compressed.path);
  }

  // 🔹 Compressão de vídeo (temporariamente desativada)
// Retorna o vídeo original para evitar problemas com Android 15 / 16 KB
  Future<File> _compressVideo(File file) async {
    return file;
  }

  // 🔹 Upload da mídia com progresso → retorna { mediaType, mediaUrl }
  Future<Map<String, String>> _uploadMediaIfNeeded(
      String postId, String userId) async {
    if (_selectedImage == null && _selectedVideo == null) {
      return {'mediaType': 'none', 'mediaUrl': ''};
    }

    final storage = FirebaseStorage.instance;
    late Reference ref;
    late File file;
    late String mediaType;

    if (_selectedImage != null) {
      mediaType = 'image';
      file = File(_selectedImage!.path);
      file = await _compressImage(file);
      ref = storage
          .ref()
          .child('posts_media')
          .child(userId)
          .child('$postId.jpg');
    } else {
      mediaType = 'video';
      file = File(_selectedVideo!.path);
      file = await _compressVideo(file);
      ref = storage
          .ref()
          .child('posts_media')
          .child(userId)
          .child('$postId.mp4');
    }

    final uploadTask = ref.putFile(file);

    // Atualiza barra de progresso
    uploadTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
      }
    });

    final snapshot = await uploadTask;
    final url = await snapshot.ref.getDownloadURL();

    return {
      'mediaType': mediaType,
      'mediaUrl': url,
    };
  }

  // 📍 Selecionar localização atual
  Future<void> _pickLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Permissão de localização negada. Não foi possível obter o local.'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _selectedPosition = position;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 Local atual anexado à publicação.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao obter localização: $e')),
      );
    }
  }

  // 🏃 Selecionar corrida do histórico (coleção "corridas")
  Future<void> _pickRunFromHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Text(
                  'Escolher corrida para compartilhar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 400,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('corridas')
                        .where('userId', isEqualTo: user.uid)
                        .orderBy('createdAt', descending: true)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'Você ainda não tem corridas para compartilhar.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      String _formatDuration(int totalSeconds) {
                        final d = Duration(seconds: totalSeconds);
                        String two(int n) => n.toString().padLeft(2, '0');
                        final h = d.inHours;
                        final m = d.inMinutes.remainder(60);
                        final s = d.inSeconds.remainder(60);
                        if (h > 0) {
                          return '${two(h)}:${two(m)}:${two(s)}';
                        }
                        return '${two(m)}:${two(s)}';
                      }

                      String _formatPace(double paceMinPerKm) {
                        if (paceMinPerKm <= 0) return '--';
                        final totalSec = (paceMinPerKm * 60).round();
                        final min = totalSec ~/ 60;
                        final sec = totalSec % 60;
                        String two(int n) => n.toString().padLeft(2, '0');
                        return '${two(min)}:${two(sec)} /km';
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};

                          // 🔹 Campos reais da corrida
                          final distanceMeters =
                          (data['distance'] ?? 0.0).toDouble();
                          final distanceKm = distanceMeters / 1000.0;

                          final durationSec =
                          (data['duration'] ?? 0).toInt();

                          final paceMinPerKm =
                          (data['pace'] ?? 0.0).toDouble();

                          final calories =
                          (data['calories'] ?? 0.0).toDouble();

                          final ts =
                              (data['createdAt'] as Timestamp?)?.toDate() ??
                                  DateTime.now();

                          return ListTile(
                            leading: const Icon(Icons.directions_run),
                            title: Text(
                              '${distanceKm.toStringAsFixed(2)} km • '
                                  'Pace ${_formatPace(paceMinPerKm)}',
                            ),
                            subtitle: Text(
                              '${_formatDuration(durationSec)} • '
                                  '${ts.day.toString().padLeft(2, '0')}/'
                                  '${ts.month.toString().padLeft(2, '0')}/'
                                  '${ts.year}',
                            ),
                            onTap: () {
                              setState(() {
                                _selectedRunId = doc.id;
                                _selectedRunData = {
                                  'distanceKm': distanceKm,
                                  'durationSec': durationSec,
                                  'pace': paceMinPerKm,
                                  'calories': calories,
                                  'createdAt': ts,
                                };
                              });

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🏃 Corrida anexada à publicação.'),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  // 📝 Publicar post (texto + mídia + local + corrida)
  Future<void> _publishPost() async {
    if (_textController.text.trim().isEmpty &&
        _selectedImage == null &&
        _selectedVideo == null &&
        _selectedPosition == null &&
        _selectedRunId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A publicação não pode estar vazia.')),
      );
      return;
    }

    setState(() {
      _isPosting = true;
      _uploadProgress = 0.0;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Você precisa estar logado para publicar.')),
      );
      setState(() => _isPosting = false);
      return;
    }

    try {
      final postsRef = FirebaseFirestore.instance.collection('posts');
      final newDoc = postsRef.doc();
      final postId = newDoc.id;

      // ⬇️ Upload da mídia (se houver) com barra de progresso
      final mediaData = await _uploadMediaIfNeeded(postId, user.uid);

      // Finaliza a barra em 100%
      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
        });
      }

      await newDoc.set({
        'text': _textController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Usuário Anônimo',
        'authorPhotoUrl': user.photoURL,
        'likes': [],

        // Tipo default do feed
        'type': 'post',

        // 🔹 Mídia
        'mediaType': mediaData['mediaType'], // 'none' | 'image' | 'video'
        'mediaUrl': mediaData['mediaUrl'],

        // 🔹 dados da corrida (se houver)
        'runId': _selectedRunId,
        'runSummary': _selectedRunData,

        // Compatibilidade com feed atual:
        'imageUrl': mediaData['mediaType'] == 'image'
            ? mediaData['mediaUrl']
            : null,
        'videoUrl': mediaData['mediaType'] == 'video'
            ? mediaData['mediaUrl']
            : null,

        // 🔹 Local (se houver)
        'hasLocation': _selectedPosition != null,
        'location': _selectedPosition != null
            ? {
          'lat': _selectedPosition!.latitude,
          'lng': _selectedPosition!.longitude,
        }
            : null,

        // 🔹 Corrida (se houver)
        'hasRun': _selectedRunId != null,
        'runId': _selectedRunId,
        'runSummary': _selectedRunData != null
            ? {
          'distanceKm': _selectedRunData!['distanceKm'],
          'durationSec': _selectedRunData!['durationSec'],
          'pace': _selectedRunData!['pace'],
          'timestamp': _selectedRunData!['timestamp'],
        }
            : null,
      });

      if (!mounted) return;
      Navigator.pop(context);
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao publicar: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isPosting = false);
    }
  }

  Widget _buildMediaPreview() {
    if (_selectedImage == null && _selectedVideo == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1, // 👈 quadrado
              child: _selectedImage != null
                  ? Image.file(
                File(_selectedImage!.path),
                fit: BoxFit.cover,
              )
                  : Container(
                alignment: Alignment.center,
                color: Colors.black26,
                child: const Icon(
                  Icons.videocam,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _clearMedia,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_selectedVideo != null)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Vídeo (máx. 10s)',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsChips() {
    final chips = <Widget>[];

    if (_selectedPosition != null) {
      chips.add(
        Chip(
          label: const Text('Local anexado'),
          avatar: const Icon(Icons.place, size: 18),
          deleteIcon: const Icon(Icons.close),
          onDeleted: () {
            setState(() {
              _selectedPosition = null;
            });
          },
        ),
      );
    }

    if (_selectedRunId != null && _selectedRunData != null) {
      chips.add(
        Chip(
          label: Text(
              'Corrida: ${(_selectedRunData!['distanceKm'] as double).toStringAsFixed(2)} km'),
          avatar: const Icon(Icons.directions_run, size: 18),
          deleteIcon: const Icon(Icons.close),
          onDeleted: () {
            setState(() {
              _selectedRunId = null;
              _selectedRunData = null;
            });
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                const Icon(Icons.photo_camera, color: Colors.white70),
                title: const Text('Tirar foto',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future.delayed(const Duration(milliseconds: 250));
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.photo_library, color: Colors.white70),
                title: const Text('Escolher da galeria',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future.delayed(const Duration(milliseconds: 250));
                  _pickImageFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                const Icon(Icons.videocam, color: Colors.white70),
                title: const Text('Gravar vídeo',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future.delayed(const Duration(milliseconds: 250));
                  _pickVideoFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library,
                    color: Colors.white70),
                title: const Text('Escolher da galeria',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future.delayed(const Duration(milliseconds: 250));
                  _pickVideoFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Publicação'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: _isPosting ? null : _publishPost,
              child: _isPosting
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Text(
                'Publicar',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 📊 Barra de progresso no topo do body
          if (_isPosting)
            LinearProgressIndicator(
              value: _uploadProgress > 0 ? _uploadProgress : null,
              minHeight: 3,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // 📝 Texto do post
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      autofocus: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style:
                      const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'No que você está pensando?',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  // 📸/🎥 Preview da mídia
                  _buildMediaPreview(),

                  // 📍 / 🏃 Chips de anexos
                  _buildAttachmentsChips(),

                  const SizedBox(height: 16),

                  // Barra de ações
                  Row(
                    children: [
                      IconButton(
                        onPressed: _isPosting ? null : _showImageSourceSheet,
                        icon: Icon(Icons.photo, color: primary),
                        tooltip: 'Adicionar foto',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isPosting ? null : _showVideoSourceSheet,
                        icon: Icon(Icons.videocam, color: primary),
                        tooltip: 'Adicionar vídeo (até 10s)',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isPosting ? null : _pickLocation,
                        icon: const Icon(Icons.place, color: Colors.orange),
                        tooltip: 'Compartilhar local atual',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isPosting ? null : _pickRunFromHistory,
                        icon: const Icon(Icons.directions_run,
                            color: Colors.lightBlueAccent),
                        tooltip: 'Compartilhar corrida do histórico',
                      ),
                      const Spacer(),
                      if (_selectedImage != null || _selectedVideo != null)
                        TextButton.icon(
                          onPressed: _isPosting ? null : _clearMedia,
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          label: const Text(
                            'Remover mídia',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
