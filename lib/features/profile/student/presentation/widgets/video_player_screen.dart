import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final Duration initialPosition;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.initialPosition = Duration.zero,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late Player _player;
  late VideoController _videoController;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterFullScreen());
    _initPlayer();
  }

  void _enterFullScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _exitFullScreen();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
          _isInitialized = true;
        });
        if (playing) _startControlHideTimer();
      }
    });
    _player.stream.error.listen((err) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    });

    try {
      await _player.open(Media(widget.videoUrl));
      if (widget.initialPosition > Duration.zero) {
        _player.seek(widget.initialPosition);
      }
      _player.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          // error: ${e.toString()}
        });
      }
    }
  }

  void _startControlHideTimer() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startControlHideTimer();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
      setState(() {
        _showControls = true;
      });
    } else {
      _player.play();
      _startControlHideTimer();
    }
  }

  void _skipBack() {
    final newPos = _position - const Duration(seconds: 5);
    _player.seek(newPos >= Duration.zero ? newPos : Duration.zero);
    _showControls = true;
    _startControlHideTimer();
  }

  void _skipForward() {
    final newPos = _position + const Duration(seconds: 5);
    _player.seek(newPos <= _duration ? newPos : _duration);
    _showControls = true;
    _startControlHideTimer();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isInitialized && !_hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Loading video…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : _hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off, size: 48, color: Colors.white54),
                        const SizedBox(height: 16),
                        Text(
                          'Unable to play video',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          label: const Text('Go Back', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _toggleControls,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Video(controller: _videoController, fit: BoxFit.contain, controls: null),
                      ),

                      if (_showControls)
                        Positioned(
                          top: 0, left: 0, right: 0,
                          child: Container(
                            padding: EdgeInsets.only(
                              top: MediaQuery.of(context).padding.top + 8,
                              left: 8, right: 16, bottom: 16,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (_showControls)
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SkipButton(icon: Icons.replay_10, onTap: _skipBack),
                              const SizedBox(width: 24),
                              GestureDetector(
                                onTap: _togglePlayPause,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white, size: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              _SkipButton(icon: Icons.forward_10, onTap: _skipForward),
                            ],
                          ),
                        ),

                      if (_showControls && _isInitialized)
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: EdgeInsets.only(
                              left: 16, right: 16,
                              bottom: MediaQuery.of(context).padding.bottom + 16,
                              top: 24,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white30,
                                    thumbColor: Colors.white,
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    overlayShape: SliderComponentShape.noOverlay,
                                  ),
                                  child: Slider(
                                    value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                    min: 0,
                                    max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                    onChanged: (value) {
                                      _player.seek(Duration(milliseconds: value.toInt()));
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(_position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    Text(_formatDuration(_duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SkipButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
