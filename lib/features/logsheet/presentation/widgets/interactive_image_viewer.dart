import 'package:flutter/material.dart';

/// Full-screen interactive image viewer with native 2-finger pinch-to-zoom,
/// double-tap zoom, pan, and smooth controls.
class InteractiveImageViewer extends StatefulWidget {
  const InteractiveImageViewer({
    super.key,
    required this.imageUrl,
    this.title = 'Photo View',
    this.subtitle,
  });

  final String imageUrl;
  final String title;
  final String? subtitle;

  /// Helper to open the full-screen zoom viewer modally
  static void show(
    BuildContext context, {
    required String imageUrl,
    String title = 'Photo View',
    String? subtitle,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => InteractiveImageViewer(
          imageUrl: imageUrl,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  State<InteractiveImageViewer> createState() => _InteractiveImageViewerState();
}

class _InteractiveImageViewerState extends State<InteractiveImageViewer>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformController.value = _zoomAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onDoubleTap(TapDownDetails details) {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final targetMatrix = Matrix4.identity();

    if (currentScale < 2.0) {
      // Zoom in to tap point
      final position = details.localPosition;
      targetMatrix
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    } // else zoom out to identity (1.0)

    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward(from: 0);
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Zoomable Interactive Image
          GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: _onDoubleTap,
            onDoubleTap: () {},
            child: Center(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 5.0,
                clipBehavior: Clip.none,
                panEnabled: true,
                scaleEnabled: true,
                child: Hero(
                  tag: widget.imageUrl,
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 54),
                          SizedBox(height: 12),
                          Text(
                            'Could not load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top Header (AppBar overlay)
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  bottom: 12,
                  left: 8,
                  right: 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white),
                      tooltip: 'Reset Zoom',
                      onPressed: () {
                        _zoomAnimation = Matrix4Tween(
                          begin: _transformController.value,
                          end: Matrix4.identity(),
                        ).animate(
                            CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
                        _animController.forward(from: 0);
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Hint
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                  top: 12,
                  left: 16,
                  right: 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: const Text(
                  '💡 Tip: Pinch with two fingers or double-tap to zoom up to 5x. Tap anywhere to toggle controls.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
