import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class AudioPlayerView extends StatefulWidget {
  final String url;
  final String fileName;

  const AudioPlayerView({
    super.key,
    required this.url,
    required this.fileName,
  });

  @override
  State<AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<AudioPlayerView> {
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    
    // Load audio file
    player.open(Media(widget.url));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = duration.inHours > 0 ? '${duration.inHours}:' : '';
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.black87,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Audio icon
              Icon(
                Icons.music_note_rounded,
                size: 120,
                color: Colors.white.withOpacity(0.8),
              ),
              const SizedBox(height: 40),
              
              // File name
              Text(
                widget.fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              
              // Progress slider
              StreamBuilder<Duration>(
                stream: player.stream.position,
                builder: (context, posSnapshot) {
                  return StreamBuilder<Duration>(
                    stream: player.stream.duration,
                    builder: (context, durSnapshot) {
                      final position = posSnapshot.data ?? Duration.zero;
                      final duration = durSnapshot.data ?? Duration.zero;
                      final value = duration.inMilliseconds > 0
                          ? position.inMilliseconds / duration.inMilliseconds
                          : 0.0;
                      
                      return Column(
                        children: [
                          Slider(
                            value: value.clamp(0.0, 1.0),
                            onChanged: (newValue) {
                              final newPosition = Duration(
                                milliseconds: (newValue * duration.inMilliseconds).round(),
                              );
                              player.seek(newPosition);
                            },
                            activeColor: Colors.blue,
                            inactiveColor: Colors.white.withOpacity(0.3),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 40),
              
              // Playback controls
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Skip backward 10s
                      IconButton(
                        icon: const Icon(Icons.replay_10, size: 32),
                        color: Colors.white,
                        onPressed: () async {
                          final position = player.state.position;
                          await player.seek(position - const Duration(seconds: 10));
                        },
                      ),
                      const SizedBox(width: 20),
                      
                      // Play/Pause button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 48,
                          ),
                          color: Colors.white,
                          onPressed: () {
                            player.playOrPause();
                          },
                        ),
                      ),
                      const SizedBox(width: 20),
                      
                      // Skip forward 10s
                      IconButton(
                        icon: const Icon(Icons.forward_10, size: 32),
                        color: Colors.white,
                        onPressed: () async {
                          final position = player.state.position;
                          await player.seek(position + const Duration(seconds: 10));
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              
              // Volume control
              StreamBuilder<double>(
                stream: player.stream.volume,
                builder: (context, snapshot) {
                  final volume = snapshot.data ?? 100.0;
                  
                  return Row(
                    children: [
                      Icon(
                        volume > 0 ? Icons.volume_up : Icons.volume_off,
                        color: Colors.white70,
                      ),
                      Expanded(
                        child: Slider(
                          value: volume,
                          min: 0,
                          max: 100,
                          onChanged: (value) {
                            player.setVolume(value);
                          },
                          activeColor: Colors.blue,
                          inactiveColor: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      Text(
                        '${volume.round()}%',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
