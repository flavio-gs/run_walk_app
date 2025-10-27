
// lib/widgets/follow_button.dart
import 'package:flutter/material.dart';
import '../service/service/firestore_service.dart';

class FollowButton extends StatefulWidget {
  final String userId;
  const FollowButton({super.key, required this.userId});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isFollowing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    if (!mounted) return;
    final isFollowing = await _firestoreService.isFollowing(widget.userId);
    if (mounted) {
      setState(() {
        _isFollowing = isFollowing;
        _isLoading = false;
      });
    }
  }

  void _onButtonPressed() {
    if (!mounted) return;
    setState(() => _isLoading = true);

    if (_isFollowing) {
      _firestoreService.unfollowUser(widget.userId).then((_) {
        if (mounted) setState(() => _isFollowing = false);
      }).whenComplete(() {
        if (mounted) setState(() => _isLoading = false);
      });
    } else {
      _firestoreService.followUser(widget.userId).then((_) {
        if (mounted) setState(() => _isFollowing = true);
      }).whenComplete(() {
        if (mounted) setState(() => _isLoading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 100,
        height: 35,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      );
    }

    return _isFollowing
        ? OutlinedButton(
      onPressed: _onButtonPressed,
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey)),
      child: const Text('Seguindo', style: TextStyle(color: Colors.white)),
    )
        : ElevatedButton(
      onPressed: _onButtonPressed,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
      child: const Text('Seguir'),
    );
  }
}
