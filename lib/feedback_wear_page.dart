import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedbackWearPage extends StatefulWidget {
  const FeedbackWearPage({super.key});

  @override
  State<FeedbackWearPage> createState() => _FeedbackWearPageState();
}

class _FeedbackWearPageState extends State<FeedbackWearPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  Future<void> _sendFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _controller.text.isEmpty) return;

    setState(() => _sending = true);

    await FirebaseFirestore.instance.collection('feedbacks').add({
      'userId': user.uid,
      'message': _controller.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'source': 'Wear OS',
    });

    setState(() {
      _sending = false;
      _controller.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('✅ Feedback enviado!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "💬 Envie um feedback rápido",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 11),
                maxLines: 3,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white10,
                  hintText: 'Digite aqui...',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _sending ? null : _sendFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                child: Text(
                  _sending ? "Enviando..." : "Enviar",
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
