import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'custom_video_controls.dart';

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
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    
    // Open the video
    if (widget.url.startsWith('file://')) {
      // Local file
      final filePath = Uri.parse(widget.url).toFilePath();
      player.open(Media(filePath));
    } else {
      // Remote URL
      player.open(Media(widget.url));
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate video width based on available space
              final videoWidth = constraints.maxWidth;
              final videoHeight = videoWidth * 9 / 16; // 16:9 aspect ratio
              
              return SizedBox(
                width: videoWidth,
                height: videoHeight.clamp(0, constraints.maxHeight),
                child: Platform.isAndroid || Platform.isIOS
                    ? Video(
                        controller: controller,
                        controls: (state) => CustomMobileVideoControls(
                          state: state,
                          fileName: widget.fileName,
                        ),
                      )
                    : Video(
                        controller: controller,
                        controls: MaterialVideoControls,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}
