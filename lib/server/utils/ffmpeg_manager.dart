import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Centralized FFmpeg manager for video operations
class FFmpegManager {
  static FFmpegManager? _instance;
  static FFmpegManager get instance => _instance ??= FFmpegManager._();
  
  FFmpegManager._();
  
  bool? _isAvailable;
  String? _ffmpegPath;
  String? _ffprobePath;
  
  /// Check if FFmpeg is available on the system
  Future<bool> isAvailable() async {
    if (_isAvailable != null) return _isAvailable!;
    
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _isAvailable = result.exitCode == 0;
      _ffmpegPath = 'ffmpeg';
      return _isAvailable!;
    } catch (e) {
      // Try common paths on Windows
      if (Platform.isWindows) {
        final commonPaths = [
          'C:\\ffmpeg\\bin\\ffmpeg.exe',
          'C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe',
          Platform.environment['USERPROFILE'] != null
              ? '${Platform.environment['USERPROFILE']}\\ffmpeg\\bin\\ffmpeg.exe'
              : null,
        ];
        
        for (final path in commonPaths) {
          if (path != null && await File(path).exists()) {
            try {
              final result = await Process.run(path, ['-version']);
              if (result.exitCode == 0) {
                _isAvailable = true;
                _ffmpegPath = path;
                _ffprobePath = path.replaceAll('ffmpeg.exe', 'ffprobe.exe');
                return true;
              }
            } catch (_) {}
          }
        }
      }
      
      _isAvailable = false;
      return false;
    }
  }
  
  /// Check if FFprobe is available
  Future<bool> isFFprobeAvailable() async {
    if (_ffprobePath != null) {
      try {
        final result = await Process.run(_ffprobePath!, ['-version']);
        return result.exitCode == 0;
      } catch (_) {}
    }
    
    try {
      final result = await Process.run('ffprobe', ['-version']);
      if (result.exitCode == 0) {
        _ffprobePath = 'ffprobe';
        return true;
      }
    } catch (_) {}
    
    return false;
  }
  
  /// Probe video file to get codec and stream information
  Future<Map<String, dynamic>?> probeVideo(String filePath) async {
    if (!await isFFprobeAvailable()) return null;
    
    try {
      final result = await Process.run(_ffprobePath ?? 'ffprobe', [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        filePath,
      ]);

      if (result.exitCode == 0) {
        return jsonDecode(result.stdout);
      }
    } catch (e) {
      print('Error probing video: $e');
    }
    return null;
  }
  
  /// Check if video needs transcoding for ExoPlayer compatibility
  Future<bool> needsTranscoding(String filePath) async {
    final info = await probeVideo(filePath);
    if (info == null) return false;

    final streams = info['streams'] as List?;
    if (streams == null) return false;

    // Find video stream
    final videoStream = streams.firstWhere(
      (s) => s['codec_type'] == 'video',
      orElse: () => null,
    );

    if (videoStream == null) return false;

    final videoCodec = videoStream['codec_name'] as String?;
    
    // ExoPlayer-supported codecs
    const supportedCodecs = [
      'h264',      // H.264/AVC
      'hevc',      // H.265/HEVC
      'vp8',       // VP8
      'vp9',       // VP9
      'av1',       // AV1
    ];

    return videoCodec != null && !supportedCodecs.contains(videoCodec.toLowerCase());
  }
  
  /// Generate video thumbnail
  Future<Uint8List?> generateVideoThumbnail(
    String filePath, {
    int? timeMs,
    int? width,
    int? height,
  }) async {
    if (!await isAvailable()) return null;
    
    try {
      final time = timeMs != null ? (timeMs / 1000).toString() : '1';
      final size = width != null && height != null ? '${width}x$height' : '320x240';
      
      final result = await Process.run(_ffmpegPath ?? 'ffmpeg', [
        '-ss', time,
        '-i', filePath,
        '-vframes', '1',
        '-s', size,
        '-f', 'image2pipe',
        '-vcodec', 'mjpeg',
        '-'
      ]);
      
      if (result.exitCode == 0 && result.stdout is List<int>) {
        return Uint8List.fromList(result.stdout as List<int>);
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
    }
    return null;
  }
  
  /// Get transcode arguments for streaming
  List<String> getTranscodeArgs(
    String inputPath, {
    String codec = 'libx264',
    String preset = 'veryfast',
    String audioCodec = 'aac',
  }) {
    return [
      '-i', inputPath,
      '-c:v', codec,
      '-preset', preset,
      '-crf', '23',
      '-c:a', audioCodec,
      '-b:a', '128k',
      '-movflags', 'frag_keyframe+empty_moov+faststart',
      '-f', 'mp4',
      'pipe:1',
    ];
  }
  
  /// Start transcoding process
  Future<Process?> startTranscode(String inputPath) async {
    if (!await isAvailable()) return null;
    
    try {
      final args = getTranscodeArgs(inputPath);
      return await Process.start(_ffmpegPath ?? 'ffmpeg', args);
    } catch (e) {
      print('Error starting transcode: $e');
      return null;
    }
  }
  
  /// Get FFmpeg path (for debugging)
  String? get ffmpegPath => _ffmpegPath;
  
  /// Get FFprobe path (for debugging)
  String? get ffprobePath => _ffprobePath;
}
