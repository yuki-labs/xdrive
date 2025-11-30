import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:shelf/shelf.dart';

/// Handles thumbnail generation for images and videos
class ThumbnailGenerator {
  // Cache for thumbnails (path -> thumbnail bytes)
  final Map<String, Uint8List> _thumbnailCache = {};

  /// Generate thumbnail for a file
  Future<Response> generateThumbnail(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    // Check if thumbnail is cached
    if (_thumbnailCache.containsKey(path)) {
      return Response.ok(
        _thumbnailCache[path],
        headers: {'content-type': 'image/jpeg'},
      );
    }

    try {
      // Get file extension
      final ext = path.split('.').last.toLowerCase();
      
      // Check if it's an image file
      final imageFormats = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'tif'];
      
      if (imageFormats.contains(ext)) {
        return await _generateImageThumbnail(path, file);
      }
      
      // Check if it's a video file
      final videoFormats = ['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp', '3g2', 'vob', 'ts', 'mts', 'm2ts', 'mpg', 'mpeg', 'ogv'];
      
      if (videoFormats.contains(ext)) {
        return await _generateVideoThumbnail(path);
      }
      
      // For unsupported file types
      return Response.notFound('Thumbnail generation not supported for this file type');
      
    } catch (e) {
      print('Error generating thumbnail: $e');
      return Response.internalServerError(body: 'Error generating thumbnail: $e');
    }
  }

  Future<Response> _generateImageThumbnail(String path, File file) async {
    // Read and decode image
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) {
      return Response.internalServerError(body: 'Failed to decode image');
    }

    // Generate thumbnail (200x200 max, maintain aspect ratio)
    final thumbnail = img.copyResize(
      image,
      width: 200,
      height: 200,
      maintainAspect: true,
    );

    // Encode as JPEG
    final thumbnailBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));

    // Cache it
    _thumbnailCache[path] = thumbnailBytes;

    return Response.ok(
      thumbnailBytes,
      headers: {'content-type': 'image/jpeg'},
    );
  }

  Future<Response> _generateVideoThumbnail(String path) async {
    try {
      // Try video_thumbnail first (works on mobile)
      try {
        final thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: path,
          thumbnailPath: (await Directory.systemTemp.createTemp()).path,
          imageFormat: ImageFormat.PNG,
          maxWidth: 200,
          quality: 80,
        );
        
        if (thumbnailPath != null) {
          final thumbnailFile = File(thumbnailPath);
          final thumbnailData = await thumbnailFile.readAsBytes();
          
          final decodedImage = img.decodePng(thumbnailData);
          if (decodedImage != null) {
            final resized = img.copyResize(
              decodedImage,
              width: 200,
              height: 200,
              maintainAspect: true,
            );
            
            final thumbnailBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
            await thumbnailFile.delete();
            _thumbnailCache[path] = thumbnailBytes;
            
            return Response.ok(
              thumbnailBytes,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          await thumbnailFile.delete();
        }
      } on MissingPluginException {
        // Fall through to FFmpeg method
      }
      
      // Try FFmpeg (works on Windows/Desktop)
      final thumbnailBytes = await _extractVideoThumbnailWithFFmpeg(path);
      if (thumbnailBytes != null) {
        _thumbnailCache[path] = thumbnailBytes;
        return Response.ok(
          thumbnailBytes,
          headers: {'content-type': 'image/jpeg'},
        );
      }
      
      return Response.notFound('Video thumbnail generation not available');
      
    } catch (e) {
      print('Error extracting video thumbnail: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Extract video thumbnail using bundled FFmpeg
  Future<Uint8List?> _extractVideoThumbnailWithFFmpeg(String videoPath) async {
    try {
      final ffmpegPath = await _getBundledFFmpegPath();
      if (ffmpegPath == null) {
        print('Bundled FFmpeg not available on this platform');
        return null;
      }

      final tempDir = await Directory.systemTemp.createTemp('video_thumb_');
      final outputPath = '${tempDir.path}${Platform.pathSeparator}thumb.jpg';

      final result = await Process.run(
        ffmpegPath,
        [
          '-i', videoPath,
          '-ss', '00:00:01.000',
          '-vframes', '1',
          '-vf', 'scale=200:200:force_original_aspect_ratio=decrease',
          '-y',
          outputPath,
        ],
      );

      if (result.exitCode == 0) {
        final thumbnailFile = File(outputPath);
        if (await thumbnailFile.exists()) {
          final bytes = await thumbnailFile.readAsBytes();
          await tempDir.delete(recursive: true);
          return bytes;
        }
      }

      await tempDir.delete(recursive: true);
      return null;
    } catch (e) {
      print('Error using FFmpeg: $e');
      return null;
    }
  }

  /// Get FFmpeg path, downloading automatically if needed
  Future<String?> _getBundledFFmpegPath() async {
    try {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        return null;
      }

      String binaryName;
      String downloadUrl;

      if (Platform.isWindows) {
        binaryName = 'ffmpeg.exe';
        // FFmpeg Windows build from official GitHub releases
        downloadUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';
      } else if (Platform.isMacOS) {
        binaryName = 'ffmpeg';
        // FFmpeg macOS from evermeet.cx
        downloadUrl = 'https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip';
      } else {
        binaryName = 'ffmpeg';
        // For Linux, try system ffmpeg first
        final systemResult = await Process.run('which', ['ffmpeg']);
        if (systemResult.exitCode == 0) {
          return systemResult.stdout.toString().trim();
        }
        downloadUrl = 'https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz';
      }

      final appDir = Directory.current;
      final ffmpegDir = Directory('${appDir.path}${Platform.pathSeparator}.ffmpeg');
      
      if (!await ffmpegDir.exists()) {
        await ffmpegDir.create(recursive: true);
      }

      final ffmpegPath = '${ffmpegDir.path}${Platform.pathSeparator}$binaryName';
      final ffmpegFile = File(ffmpegPath);
      
      // If FFmpeg already exists, return it
      if (await ffmpegFile.exists()) {
        return ffmpegPath;
      }

      // Download FFmpeg
      print('FFmpeg not found, downloading from $downloadUrl...');
      
      try {
        final http = await Process.start('curl', [
          '-L',  // Follow redirects
          '-o',
          '${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download',
          downloadUrl,
        ]);
        
        await http.exitCode;
        
        print('FFmpeg downloaded, extracting...');
        
        // Extract based on platform
        if (Platform.isWindows) {
          // Extract zip using PowerShell
          await Process.run('powershell', [
            '-Command',
            'Expand-Archive -Path "${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download" -DestinationPath "${ffmpegDir.path}${Platform.pathSeparator}temp"',
          ]);
          
          // Find and move ffmpeg.exe from nested folder
          final tempDir = Directory('${ffmpegDir.path}${Platform.pathSeparator}temp');
          final files = await tempDir.list(recursive: true).toList();
          for (final file in files) {
            if (file.path.endsWith('ffmpeg.exe')) {
              await File(file.path).copy(ffmpegPath);
              break;
            }
          }
          
          // Cleanup
          await tempDir.delete(recursive: true);
          await File('${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download').delete();
          
        } else if (Platform.isMacOS) {
          // Extract zip
          await Process.run('unzip', [
            '${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download',
            '-d',
            ffmpegDir.path,
          ]);
          
          await File('${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download').delete();
          await Process.run('chmod', ['+x', ffmpegPath]);
          
        } else {
          // Linux: Extract tar.xz
          await Process.run('tar', [
            '-xJf',
            '${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download',
            '-C',
            ffmpegDir.path,
          ]);
          
          // Find and move ffmpeg from nested folder
          final tempDir = Directory(ffmpegDir.path);
          final files = await tempDir.list(recursive: true).toList();
          for (final file in files) {
            if (file.path.endsWith('/ffmpeg') && file is File) {
              await file.copy(ffmpegPath);
              break;
            }
          }
          
          await File('${ffmpegDir.path}${Platform.pathSeparator}ffmpeg_download').delete();
          await Process.run('chmod', ['+x', ffmpegPath]);
        }
        
        if (await ffmpegFile.exists()) {
          print('FFmpeg installed successfully!');
          return ffmpegPath;
        } else {
          print('Failed to extract FFmpeg');
          return null;
        }
        
      } catch (e) {
        print('Error downloading FFmpeg: $e');
        return null;
      }
      
    } catch (e) {
      print('Error getting FFmpeg: $e');
      return null;
    }
  }

  void clearCache() {
    _thumbnailCache.clear();
  }
}
