import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../data/entities/user_profile_entity.dart';
import 'video_player_screen.dart';

bool _isVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mkv');
}

class VideosHorizontalListView extends StatefulWidget {
  final List<ProfileVideo> videos;

  const VideosHorizontalListView({super.key, required this.videos});

  @override
  State<VideosHorizontalListView> createState() =>
      _VideosHorizontalListViewState();
}

class _VideosHorizontalListViewState extends State<VideosHorizontalListView> {
  int _activeIndex = -1;

  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isDisposed = false;
  bool _hasError = false;
  bool _showControls = true;

  final Map<int, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _generateThumbnails();
  }

  @override
  void didUpdateWidget(VideosHorizontalListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videos != widget.videos) {
      _thumbnailCache.clear();
      _generateThumbnails();
    }
  }

  Future<void> _generateThumbnails() async {
    for (int i = 0; i < widget.videos.length; i++) {
      if (_thumbnailCache.containsKey(i)) continue;
      if (!_isVideoUrl(widget.videos[i].video)) continue;

      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: widget.videos[i].video,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 218,
          quality: 80,
        );
        if (bytes != null && mounted) {
          _thumbnailCache[i] = bytes;
          setState(() {});
        }
      } catch (_) {
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _player?.dispose();
    super.dispose();
  }

  void _startControlHideTimer() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isPlaying && !_isDisposed) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startControlHideTimer();
  }

  void _playAtIndex(int index) {
    if (index == _activeIndex) return;

    final video = widget.videos[index];
    if (!_isVideoUrl(video.video)) return;

    _player?.pause();
    _player?.dispose();
    _player = null;
    _videoController = null;
    _isInitialized = false;
    _isPlaying = false;
    _hasError = false;
    setState(() => _activeIndex = index);

    final player = Player();
    _player = player;
    _videoController = VideoController(player);

    player.stream.playing.listen((playing) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _isInitialized = true;
        _isPlaying = playing;
        _showControls = true;
      });
      if (playing) _startControlHideTimer();
    });

    player.stream.error.listen((_) {
      if (mounted && !_isDisposed) {
        setState(() => _hasError = true);
      }
    });

    player
        .open(Media(video.video))
        .then((_) {
          player.play();
        })
        .catchError((_) {
          if (mounted && !_isDisposed) {
            setState(() => _hasError = true);
          }
        });
  }

  void _stopActive() {
    _player?.pause();
    _player?.dispose();
    _player = null;
    _videoController = null;
    if (mounted) {
      setState(() {
        _activeIndex = -1;
        _isInitialized = false;
        _isPlaying = false;
        _hasError = false;
      });
    }
  }

  void _togglePlayPause() {
    if (_player == null || !_isInitialized) return;
    if (_isPlaying) {
      _player!.pause();
      setState(() {
        _isPlaying = false;
        _showControls = true;
      });
    } else {
      _player!.play();
      setState(() => _isPlaying = true);
      _startControlHideTimer();
    }
  }

  void _openFullScreen() {
    if (_activeIndex < 0 || _player == null) return;

    _player!.pause();
    setState(() {
      _isPlaying = false;
      _showControls = true;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: widget.videos[_activeIndex].video,
          title: widget.videos[_activeIndex].title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 71 + 8 + 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.videos.length,
        itemBuilder: (context, index) {
          final video = widget.videos[index];
          final isLast = index == widget.videos.length - 1;
          final isActive = index == _activeIndex;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 109,
                  height: 71,
                  child: _VideoCard(
                    video: video,
                    thumbnailBytes: _thumbnailCache[index],
                    isActive: isActive,
                    isInitialized: _isInitialized,
                    isPlaying: _isPlaying,
                    hasError: _hasError,
                    showControls: _showControls,
                    videoController: _videoController,
                    onTap: () => _playAtIndex(index),
                    onPlayPause: isActive ? _togglePlayPause : null,
                    onFullScreen: isActive ? _openFullScreen : null,
                    onClose: isActive ? _stopActive : null,
                    onToggleControls: isActive ? _toggleControls : null,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 109,
                  child: Text(
                    video.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final ProfileVideo video;
  final Uint8List? thumbnailBytes;
  final bool isActive;
  final bool isInitialized;
  final bool isPlaying;
  final bool hasError;
  final bool showControls;
  final VideoController? videoController;
  final VoidCallback onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFullScreen;
  final VoidCallback? onClose;
  final VoidCallback? onToggleControls;

  const _VideoCard({
    required this.video,
    this.thumbnailBytes,
    required this.isActive,
    required this.isInitialized,
    required this.isPlaying,
    required this.hasError,
    required this.showControls,
    required this.videoController,
    required this.onTap,
    this.onPlayPause,
    this.onFullScreen,
    this.onClose,
    this.onToggleControls,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 71,
      child: isActive ? _buildActivePlayer(cs) : _buildPlaceholder(cs),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailBytes != null)
              Image.memory(
                thumbnailBytes!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xCC000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlayer(ColorScheme cs) {
    return GestureDetector(
      onTap: onToggleControls,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasError)
              const Center(
                child: Icon(
                  Icons.videocam_off,
                  color: Colors.white54,
                  size: 20,
                ),
              )
            else if (isInitialized && videoController != null)
              Video(
                controller: videoController!,
                fit: BoxFit.cover,
                controls: null,
              )
            else
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),

            if (showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ),

              Center(
                child: GestureDetector(
                  onTap: onPlayPause,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: isPlaying ? 16 : 18,
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onFullScreen,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
