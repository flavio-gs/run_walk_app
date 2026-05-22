import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:run_walk_app/service/story_upload_service.dart';

class CreateStoryPage extends StatefulWidget {
  final String type; // 'image', 'video', 'poll', 'text'
  final ImageSource source;
  const CreateStoryPage({super.key, required this.type, this.source = ImageSource.gallery});

  @override
  State<CreateStoryPage> createState() => _CreateStoryPageState();
}

class _CreateStoryPageState extends State<CreateStoryPage> {
  final _picker = ImagePicker();
  File? _mediaFile;
  VideoPlayerController? _videoController;
  bool _isUploading = false;

  // Personalização
  Color _backgroundColor = Colors.blueGrey[900]!;
  List<EditableItem> _items = [];
  
  // Poll fields
  final TextEditingController _pollQuestionController = TextEditingController();
  final TextEditingController _option1Controller = TextEditingController(text: 'Sim');
  final TextEditingController _option2Controller = TextEditingController(text: 'Não');

  // Music fields
  Map<String, dynamic>? _selectedMusic;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'image' || widget.type == 'video') {
      _pickMedia();
    }
  }

  Future<void> _pickMedia() async {
    XFile? file;
    if (widget.type == 'image') {
      file = await _picker.pickImage(source: widget.source);
    } else if (widget.type == 'video') {
      file = await _picker.pickVideo(source: widget.source);
    }

    if (file != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = "story_tmp_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}";
      final savedFile = await File(file.path).copy('${directory.path}/$fileName');

      setState(() {
        _mediaFile = savedFile;
      });
      if (widget.type == 'video') {
        _videoController = VideoPlayerController.file(_mediaFile!)
          ..initialize().then((_) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
          });
      }
    } else if (widget.type != 'poll' && widget.type != 'text') {
      if (mounted) Navigator.pop(context);
    }
  }

  void _addText() {
    TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Escreva algo", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 22),
          decoration: const InputDecoration(border: InputBorder.none, hintText: "Toque para digitar...", hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                setState(() {
                  _items.add(EditableItem(
                    content: textController.text,
                    type: ItemType.text,
                    position: const Offset(100, 200),
                  ));
                });
              }
              Navigator.pop(context);
            },
            child: const Text("Adicionar"),
          ),
        ],
      ),
    );
  }

  void _addEmoji() {
    final emojis = ["🔥", "❤️", "😍", "😂", "🙌", "🏃", "👟", "🏆", "💪", "✨", "💯", "📍"];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
        itemCount: emojis.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () {
            setState(() {
              _items.add(EditableItem(
                content: emojis[index],
                type: ItemType.emoji,
                position: const Offset(150, 300),
              ));
            });
            Navigator.pop(context);
          },
          child: Center(child: Text(emojis[index], style: const TextStyle(fontSize: 40))),
        ),
      ),
    );
  }

  Future<void> _uploadStory() async {
    if (widget.type != 'poll' && widget.type != 'text' && _mediaFile == null) return;
    
    // Inicia o upload em segundo plano e volta para o feed
    StoryUploadService().uploadStory(
      mediaFile: _mediaFile,
      type: widget.type,
      selectedMusic: _selectedMusic,
      backgroundColor: _backgroundColor.value.toString(),
      items: _items.map((i) => i.toMap()).toList(),
      pollQuestion: _pollQuestionController.text,
      option1: _option1Controller.text,
      option2: _option2Controller.text,
    ).catchError((e) {
      debugPrint("Erro no upload do story: $e");
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Postando seu story... 🔥')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _mediaFile == null ? _backgroundColor : Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.text_fields, color: Colors.white), onPressed: _addText),
          IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white), onPressed: _addEmoji),
          if (_mediaFile == null) 
            IconButton(
              icon: const Icon(Icons.color_lens_outlined, color: Colors.white), 
              onPressed: () => setState(() => _backgroundColor = (Colors.primaries..shuffle()).first)
            ),
          IconButton(
            icon: Icon(Icons.music_note, color: _selectedMusic != null ? Colors.blueAccent : Colors.white),
            onPressed: () => showModalBottomSheet(
              context: context, 
              isScrollControlled: true, 
              backgroundColor: Colors.grey[900],
              builder: (context) => _MusicSearchModal(onMusicSelected: (m) => setState(() => _selectedMusic = m))
            ),
          ),
          TextButton(onPressed: _uploadStory, child: const Text('Compartilhar', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
        ],
      ),
      body: Stack(
        children: [
          if (_mediaFile != null)
            Center(child: widget.type == 'video' ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)) : Image.file(_mediaFile!)),
          if (widget.type == 'poll') _buildPollCreator(),
          
          ..._items.map((item) => Positioned(
            left: item.position.dx,
            top: item.position.dy,
            child: GestureDetector(
              onPanUpdate: (details) => setState(() => item.position += details.delta),
              onLongPress: () => setState(() => _items.remove(item)),
              child: Transform.scale(
                scale: item.scale,
                child: Text(item.content, style: TextStyle(color: Colors.white, fontSize: item.type == ItemType.text ? 28 : 50, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 10, color: Colors.black45)])),
              ),
            ),
          )),

          if (_selectedMusic != null) Positioned(bottom: 50, left: 0, right: 0, child: Center(child: Chip(label: Text("${_selectedMusic!['trackName']} - ${_selectedMusic!['artistName']}")))),
          if (_isUploading) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildPollCreator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _pollQuestionController, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: "Pergunta...")),
            Row(children: [
              Expanded(child: TextField(controller: _option1Controller, textAlign: TextAlign.center)),
              Expanded(child: TextField(controller: _option2Controller, textAlign: TextAlign.center)),
            ])
          ],
        ),
      ),
    );
  }
}

enum ItemType { text, emoji }

class EditableItem {
  String content;
  ItemType type;
  Offset position;
  double scale;

  EditableItem({required this.content, required this.type, required this.position, this.scale = 1.0});

  Map<String, dynamic> toMap() => {'content': content, 'type': type.index, 'dx': position.dx, 'dy': position.dy, 'scale': scale};
}

class _MusicSearchModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onMusicSelected;
  const _MusicSearchModal({required this.onMusicSelected});
  @override State<_MusicSearchModal> createState() => _MusicSearchModalState();
}

class _MusicSearchModalState extends State<_MusicSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _results = [];
  bool _isLoading = false;
  int? _playingIndex;

  @override void initState() { 
    super.initState(); 
    _searchMusic("Top Hits", isInitial: true); 
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _playingIndex = null);
    });
  }
  @override void dispose() { _audioPlayer.dispose(); _searchController.dispose(); super.dispose(); }

  Future<void> _togglePreview(int index, String url) async {
    if (_playingIndex == index) {
      await _audioPlayer.stop();
      setState(() => _playingIndex = null);
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      setState(() => _playingIndex = index);
    }
  }

  Future<void> _searchMusic(String query, {bool isInitial = false}) async {
    if (query.isEmpty) return;
    if (!isInitial) setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse("https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=20"));
      if (response.statusCode == 200) {
        if (mounted) setState(() {
          _results = jsonDecode(response.body)['results'];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          TextField(controller: _searchController, onSubmitted: (v) => _searchMusic(v), style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Buscar música...", hintStyle: const TextStyle(color: Colors.white54), prefixIcon: const Icon(Icons.search, color: Colors.white54), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
          const SizedBox(height: 20),
          Text(_searchController.text.isEmpty ? "Recomendados" : "Resultados", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          if (_isLoading) const Expanded(child: Center(child: CircularProgressIndicator(color: Colors.blueAccent)))
          else Expanded(child: ListView.builder(itemCount: _results.length, itemBuilder: (context, index) {
            final t = _results[index];
            final isPlaying = _playingIndex == index;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(t['artworkUrl100'], width: 50, height: 50, fit: BoxFit.cover)),
                  GestureDetector(
                    onTap: () => _togglePreview(index, t['previewUrl']),
                    child: Container(width: 50, height: 50, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.rectangle), child: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 30)),
                  ),
                ],
              ),
              title: Text(t['trackName'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(t['artistName'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              trailing: const Icon(Icons.add_circle_outline, color: Colors.white54, size: 24),
              onTap: () {
                _audioPlayer.stop();
                widget.onMusicSelected({'trackName': t['trackName'], 'artistName': t['artistName'], 'previewUrl': t['previewUrl']});
                Navigator.pop(context);
              },
            );
          }))
        ],
      ),
    );
  }
}
