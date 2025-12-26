// lib/widgets/follow_button.dart
import 'package:flutter/material.dart';
import '../service/service/firestore_service.dart';

class FollowButton extends StatefulWidget {
  final String userId;
  final VoidCallback? onStatusChanged;
  const FollowButton({super.key, required this.userId, this.onStatusChanged});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isFollowing = false;
  bool _isRequested = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    final isFollowing = await _firestoreService.isFollowing(widget.userId);
    bool isRequested = false;
    if (!isFollowing) {
      isRequested = await _firestoreService.isFollowRequested(widget.userId);
    }
    
    if (mounted) {
      setState(() {
        _isFollowing = isFollowing;
        _isRequested = isRequested;
        _isLoading = false;
      });
    }
  }

  void _onButtonPressed() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    if (_isFollowing) {
      await _firestoreService.unfollowUser(widget.userId);
      if (mounted) {
        setState(() {
          _isFollowing = false;
          _isRequested = false;
        });
      }
    } else if (_isRequested) {
      // Se já solicitou e clicar de novo, talvez queira cancelar? 
      // Por enquanto vamos apenas manter ou implementar cancelRequest no service.
      // Vou manter como solicitado por enquanto.
    } else {
      await _firestoreService.followUser(widget.userId);
      await _checkStatus(); // Re-checa para ver se virou following ou requested
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
      if (widget.onStatusChanged != null) widget.onStatusChanged!();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 100,
        height: 35,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))),
      );
    }

    if (_isFollowing) {
      return OutlinedButton(
        onPressed: _onButtonPressed,
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey)),
        child: const Text('Seguindo', style: TextStyle(color: Colors.grey)),
      );
    }

    if (_isRequested) {
      return OutlinedButton(
        onPressed: null, // Desabilitado ou permitir cancelar?
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
        child: const Text('Solicitado', style: TextStyle(color: Colors.orange)),
      );
    }

    return ElevatedButton(
      onPressed: _onButtonPressed,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
      child: const Text('Seguir', style: TextStyle(color: Colors.white)),
    );
  }
}
