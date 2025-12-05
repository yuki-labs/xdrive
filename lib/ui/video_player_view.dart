import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerView extends StatefulWidget {
  final String url;
  final String fileName;

  const VideoPlayerView({
    super.key,
    required this.url,
    required this.fileName,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Create video player controller with optimized settings
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(
        // Allow mixed content (important for localhost proxy)
        mixWithOthers: true,
        // Set HTTP headers if needed
        allowBackgroundPlayback: false,
      ),
    );

    try {
      await _videoPlayerController.initialize();
      
      // Create chewie controller with minimal buffering for fast seeking
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        autoPlay: true,
        looping: false,
        // Return to portrait after exiting fullscreen
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        // Styled progress bar
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF2196F3),
          handleColor: Colors.white,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2196F3),
            ),
          ),
        ),
        autoInitialize: true,
        // Show controls immediately
        showControlsOnInitialize: true,
        // Hide controls after 3 seconds
        hideControlsTimer: const Duration(seconds: 3),
      );

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _videoPlayerController.pause();
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _isInitialized && _chewieController != null
            ? Padding(
                // Add padding in landscape mode for centered UI
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 24.0 : 0.0,  // Side padding
                  vertical: isLandscape ? 24.0 : 0.0,     // Top/bottom padding
                ),
                child: AspectRatio(
                  aspectRatio: _videoPlayerController.value.aspectRatio,
                  child: Chewie(controller: _chewieController!),
                ),
              )
            : const CircularProgressIndicator(
                color: Color(0xFF2196F3),
              ),
      ),
    );
  }
}
