import 'ffmpeg_manager.dart';

/// Detects video codecs and determines if transcoding is needed
/// 
/// This is a lightweight wrapper around FFmpegManager for backward compatibility
class CodecDetector {
  /// Check if FFmpeg is available
  static Future<bool> isFFmpegAvailable() async {
    return await FFmpegManager.instance.isAvailable();
  }

  /// Probe video file to get codec information
  static Future<Map<String, dynamic>?> probeVideo(String filePath) async {
    return await FFmpegManager.instance.probeVideo(filePath);
  }

  /// Check if video needs transcoding for ExoPlayer compatibility
  static Future<bool> needsTranscoding(String filePath) async {
    return await FFmpegManager.instance.needsTranscoding(filePath);
  }

  /// Get recommended FFmpeg transcode arguments
  static List<String> getTranscodeArgs(String inputPath, {
    String codec = 'libx264',
    String preset = 'veryfast',
    String audioCodec = 'aac',
  }) {
    return FFmpegManager.instance.getTranscodeArgs(
      inputPath,
      codec: codec,
      preset: preset,
      audioCodec: audioCodec,
    );
  }
}
