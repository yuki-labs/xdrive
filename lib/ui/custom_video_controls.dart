import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Custom video controls that add a filename overlay at the top
class CustomMobileVideoControls extends StatelessWidget {
  final VideoState state;
  final String fileName;

  const CustomMobileVideoControls({
    super.key,
    required this.state,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        padding: const EdgeInsets.only(bottom: 24.0), // Raise controls from bottom
        topButtonBar: [
          // Add filename to top button bar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0),
              child: Text(
                fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      fullscreen: MaterialVideoControlsThemeData(
        padding: const EdgeInsets.only(bottom: 40.0), // More padding in fullscreen
        topButtonBar: [
          // Add filename to top button bar in fullscreen
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0),
              child: Text(
                fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      child: MaterialVideoControls(state),
    );
  }
}
