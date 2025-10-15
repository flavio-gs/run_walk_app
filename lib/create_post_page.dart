import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isPosting = false;

  Future<void> _publishPost() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A publicação não pode estar vazia.')),
      );
      return;
    }

    setState(() {
      _isPosting = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar logado para publicar.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'text': _textController.text,
        'timestamp': FieldValue.serverTimestamp(), // Usa o tempo do servidor
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Usuário Anônimo',
        'authorPhotoUrl': user.photoURL,
        // Futuramente, podemos adicionar campos para imagem, dados de corrida, etc.
      });

      if (mounted) {
        Navigator.pop(context); // Fecha a tela de criação após publicar
      }
    } catch (e) {
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao publicar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Publicação'),
        backgroundColor: Colors.grey[900],
        actions: [
          // Botão de Publicar na AppBar
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: _isPosting ? null : _publishPost,
              child: _isPosting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Publicar',
                      style: TextStyle(
                          color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _textController,
          autofocus: true,
          maxLines: 10, // Define um bom espaço para escrever
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'No que você está pensando?',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none, // Borda limpa
          ),
        ),
      ),
    );
  }
}
