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

  // FIX 1: Função de publicar corrigida para ser mais robusta
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você precisa estar logado para publicar.')),
        );
        setState(() => _isPosting = false);
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'text': _textController.text,
        'timestamp': FieldValue.serverTimestamp(), 
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Usuário Anônimo',
        'authorPhotoUrl': user.photoURL,
        'likes': [], // Inicializa o campo de curtidas para evitar erros
      });

      if (mounted) {
        Navigator.pop(context); // Fecha a tela de criação após publicar
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $e')),
        );
      }
    } finally {
      // Garante que o estado de carregamento seja sempre desativado
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Publicar',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary, // Usa a cor do tema
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // FIX 2: Campo de texto corrigido para melhor digitação
        child: TextField(
          controller: _textController,
          autofocus: true,
          maxLines: null, // Permite que o campo cresça indefinidamente
          keyboardType: TextInputType.multiline, // Garante o teclado correto
          textCapitalization: TextCapitalization.sentences, // Capitaliza o início das frases
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'No que você está pensando?',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
