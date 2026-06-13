import 'dart:io';
import 'dart:ui' as ui;

import 'package:dotted_border/dotted_border.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Full-screen interactive crop UI with pinch-zoom, pan, and dotted-border guide.
///
/// Uses purely manual dart:ui crop (PictureRecorder + drawImageRect) — native
/// ImageCropper.cropImage() is skipped because it crashes on Android 16 (API 36).
class CustomCropScreen extends StatefulWidget {
  /// The image file to crop, picked at full phone quality.
  final XFile imageFile;

  /// Desired output aspect ratio (e.g. 1:1 for avatar, 16:9 for cover).
  final CropAspectRatio aspectRatio;

  /// Maximum output width for the cropped image in pixels.
  final double outputMaxWidth;

  /// Maximum output height for the cropped image in pixels.
  final double outputMaxHeight;

  /// JPEG quality (1-100) for the cropped output.
  final int outputQuality;

  /// Whether to show a circular (avatar) or rectangular (cover) crop guide.
  final bool isCircular;

  /// Title shown in the app bar.
  final String toolbarTitle;

  const CustomCropScreen({
    super.key,
    required this.imageFile,
    required this.aspectRatio,
    required this.outputMaxWidth,
    required this.outputMaxHeight,
    required this.outputQuality,
    this.isCircular = false,
    this.toolbarTitle = 'Crop Image',
  });

  @override
  State<CustomCropScreen> createState() => _CustomCropScreenState();
}

class _CustomCropScreenState extends State<CustomCropScreen> {
  /// Decoded full-resolution image for the manual crop fallback.
  ui.Image? _image;

  /// Native pixel size of the loaded image.
  Size _imageNativeSize = Size.zero;

  /// On-screen display size of the image.
  Size _imageDisplaySize = Size.zero;

  bool _isProcessing = false;

  /// Controller for InteractiveViewer pan/zoom.
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _image = frame.image;
        _imageNativeSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ToastService.showError('Failed to load image. Please try again.');
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Crop logic
  // ───────────────────────────────────────────────────────────────────────────

  /// Called when the user taps "Crop" — uses manual [dart:ui] pixel extraction.
  ///
  /// The native [ImageCropper] plugin is intentionally skipped because it
  /// crashes on Android 16 (API 36).  The manual path uses only Dart code
  /// and is compatible across all Android versions.
  Future<void> _onCrop() async {
    if (_image == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final manualResult = await _tryManualCrop();
      if (manualResult != null && mounted) {
        Navigator.pop(context, CroppedFile(manualResult.path));
        return;
      }
    } catch (_) {
      // fall through to error display
    }

    if (mounted) {
      setState(() => _isProcessing = false);
      ToastService.showError('Failed to crop image. Please try again.');
    }
  }

  /// Manual crop using [dart:ui] — entirely in Dart, no native code.
  ///
  /// Calculates the portion of the original image visible within the crop
  /// guide (or the circular container for avatar mode), extracts it, and
  /// saves as PNG.
  Future<File?> _tryManualCrop() async {
    try {
      final image = _image!;
      final nativeSize = _imageNativeSize;

      // ── Compute display size matching _buildBody ──
      final viewport = MediaQuery.of(context).size;
      const double appBarHeight = kToolbarHeight;
      final bodyHeight =
          viewport.height -
          appBarHeight -
          MediaQuery.of(context).padding.top;
      final bodyWidth = viewport.width;

      final imageAspect = nativeSize.width / nativeSize.height;
      final double displayW, displayH;
      if (widget.isCircular) {
        const double guideFraction = 0.75;
        final double circleSize = bodyWidth * guideFraction;
        if (imageAspect > 1) {
          displayH = circleSize;
          displayW = circleSize * imageAspect;
        } else {
          displayW = circleSize;
          displayH = circleSize / imageAspect;
        }
      } else {
        if (imageAspect > bodyWidth / bodyHeight) {
          displayW = bodyWidth;
          displayH = bodyWidth / imageAspect;
        } else {
          displayH = bodyHeight;
          displayW = bodyHeight * imageAspect;
        }
      }

      if (displayW <= 0 || displayH <= 0) return null;

      // ── Determine the visible rect (crop area) in screen coordinates ──
      final Rect visibleScreenRect;
      if (widget.isCircular) {
        // Avatar mode: the visible area is the circular container.
        // Same size calculation as _buildBody.
        const double guideFraction = 0.75;
        final double circleSize = bodyWidth * guideFraction;
        visibleScreenRect = Rect.fromCenter(
          center: Offset(bodyWidth / 2, bodyHeight / 2),
          width: circleSize,
          height: circleSize,
        );
      } else {
        // Rectangular mode: existing guide rect.
        const double guideFraction = 0.75;
        final double guideW = bodyWidth * guideFraction;
        final double guideH =
            guideW * widget.aspectRatio.ratioY / widget.aspectRatio.ratioX;
        visibleScreenRect = Rect.fromCenter(
          center: Offset(bodyWidth / 2, bodyHeight / 2),
          width: guideW,
          height: guideH,
        );
      }

      // ── Map visible rect from screen → image pixel coordinates ──
      final imageLeft = (bodyWidth - displayW) / 2;
      final imageTop = (bodyHeight - displayH) / 2;

      final inverse = Matrix4.inverted(_transformController.value);
      final topLeft = MatrixUtils.transformPoint(
        inverse,
        Offset(
          visibleScreenRect.left - imageLeft,
          visibleScreenRect.top - imageTop,
        ),
      );
      final bottomRight = MatrixUtils.transformPoint(
        inverse,
        Offset(
          visibleScreenRect.right - imageLeft,
          visibleScreenRect.bottom - imageTop,
        ),
      );

      final scaleX = nativeSize.width / displayW;
      final scaleY = nativeSize.height / displayH;

      // Unclamped source rect in native pixels (may extend beyond image bounds
      // when the user zooms out — the black background should fill that space).
      final rawSrcX = topLeft.dx * scaleX;
      final rawSrcY = topLeft.dy * scaleY;
      final rawSrcW = (bottomRight.dx - topLeft.dx) * scaleX;
      final rawSrcH = (bottomRight.dy - topLeft.dy) * scaleY;

      // Output dimensions (output canvas = visible rect).
      final outW = rawSrcW < widget.outputMaxWidth
          ? rawSrcW.toDouble().round()
          : widget.outputMaxWidth.toInt();
      final outH = rawSrcH < widget.outputMaxHeight
          ? rawSrcH.toDouble().round()
          : widget.outputMaxHeight.toInt();
      if (outW <= 0 || outH <= 0) return null;

      // Intersection: what portion of the source rect actually has image data.
      final imageSrcRect = Rect.fromLTWH(0, 0, nativeSize.width, nativeSize.height);
      final requestedSrcRect = Rect.fromLTWH(rawSrcX, rawSrcY, rawSrcW, rawSrcH);
      final overlap = imageSrcRect.intersect(requestedSrcRect);

      // Map the overlap back to destination coordinates.
      final destLeft = ((overlap.left - rawSrcX) / rawSrcW * outW).round();
      final destTop = ((overlap.top - rawSrcY) / rawSrcH * outH).round();
      final destW = (overlap.width / rawSrcW * outW).round();
      final destH = (overlap.height / rawSrcH * outH).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Fill the entire output with black (matches the Scaffold backgroundColor
      // shown behind the image when zoomed out).
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..color = const Color(0xFF000000),
      );

      // Draw the overlapping image portion at the correct position.
      if (overlap.width > 0 && overlap.height > 0) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(overlap.left, overlap.top, overlap.width, overlap.height),
          Rect.fromLTWH(destLeft.toDouble(), destTop.toDouble(), destW.toDouble(), destH.toDouble()),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(outW.round(), outH.round());

      // Encode as PNG (dart:ui has no built-in JPEG encoder).
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      final dir = widget.imageFile.path.substring(
        0,
        widget.imageFile.path.lastIndexOf(Platform.pathSeparator),
      );
      final outPath =
          '$dir/cropped_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(outPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        title: Text(
          widget.toolbarTitle,
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        actions: [
          _isProcessing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _onCrop,
                  child: const Text(
                    'Crop',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        final viewportH = constraints.maxHeight;
        if (widget.isCircular) {
          // ── Avatar mode: CoverRepositionScreen-style circular crop ──
          const double guideFraction = 0.75;
          final double circleSize = viewportW * guideFraction;

          // Size the image to FILL the circle (like BoxFit.cover), so on first
          // open the avatar area is fully covered — no empty space.
          final imageAspect = _imageNativeSize.width / _imageNativeSize.height;
          double displayW, displayH;
          if (imageAspect > 1) {
            displayH = circleSize;
            displayW = circleSize * imageAspect;
          } else {
            displayW = circleSize;
            displayH = circleSize / imageAspect;
          }

          // Center the image vertically within the circle on first render,
          // matching WhatsApp-style "fill then reposition" behavior.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_transformController.value == Matrix4.identity()) {
              final dx = (circleSize - displayW) / 2;
              final dy = (circleSize - displayH) / 2;
              _transformController.value = Matrix4.translationValues(dx, dy, 0);
            }
            if (_imageDisplaySize != Size(displayW, displayH)) {
              setState(() => _imageDisplaySize = Size(displayW, displayH));
            }
          });

          return Stack(
            children: [
              Center(
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.themeColor, width: 2.5),
                  ),
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 0.5,
                    maxScale: 4.0,
                    constrained: false,
                    boundaryMargin: EdgeInsets.all(
                      (displayW - circleSize).clamp(50, 2000) + 100,
                    ),
                    child: RawImage(
                      image: _image,
                      width: displayW,
                      height: displayH,
                      filterQuality: FilterQuality.high,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: const Text(
                  'Pinch to zoom, drag to reposition',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          );
        }

        // ── Rectangular mode: existing overlay approach ──
        final imageAspectRect = _imageNativeSize.width / _imageNativeSize.height;
        final double rectDisplayW, rectDisplayH;
        if (imageAspectRect > viewportW / viewportH) {
          rectDisplayW = viewportW;
          rectDisplayH = viewportW / imageAspectRect;
        } else {
          rectDisplayH = viewportH;
          rectDisplayW = viewportH * imageAspectRect;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_imageDisplaySize != Size(rectDisplayW, rectDisplayH)) {
            setState(() => _imageDisplaySize = Size(rectDisplayW, rectDisplayH));
          }
        });
        return Stack(
          children: [
            // ── Interactive image (pan / zoom) ──
            Center(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.5,
                maxScale: 4.0,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(200),
                child: SizedBox(
                  width: rectDisplayW,
                  height: rectDisplayH,
                  child: RawImage(
                    image: _image,
                    width: rectDisplayW,
                    height: rectDisplayH,
                    filterQuality: FilterQuality.high,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // ── Dim overlay with cutout + dotted border guide ──
            _buildGuideOverlay(
              viewportW: viewportW,
              viewportH: viewportH,
              guideFraction: 0.75,
            ),

            // ── Hint text ──
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: const Text(
                'Pinch to zoom, drag to reposition',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuideOverlay({
    required double viewportW,
    required double viewportH,
    required double guideFraction,
  }) {
    final guideW = viewportW * guideFraction;
    final guideH =
        guideW * widget.aspectRatio.ratioY / widget.aspectRatio.ratioX;
    final centerX = viewportW / 2;
    final centerY = viewportH / 2;
    final left = centerX - guideW / 2;
    final top = centerY - guideH / 2;

    return Stack(
      children: [
        // ── Semi-transparent dim with cutout ──
        ClipPath(
          clipper: widget.isCircular
              ? CircleCutoutClipper(
                  center: Offset(centerX, centerY),
                  radius: guideW / 2,
                )
              : RectCutoutClipper(
                  cutoutRect: Rect.fromLTWH(left, top, guideW, guideH),
                ),
          child: Container(color: Colors.black.withValues(alpha: 0.65)),
        ),

        // ── Dotted border guide (circular for avatar, rounded-rect for cover) ──
        if (widget.isCircular)
          Positioned(
            left: left - 1,
            top: top - 1,
            child: DottedBorder(
              color: AppColors.themeColor,
              strokeWidth: 2.5,
              dashPattern: const [8, 4],
              borderType: BorderType.Circle,
              child: SizedBox(width: guideW + 2, height: guideW + 2),
            ),
          )
        else
          Positioned(
            left: left - 1,
            top: top - 1,
            child: DottedBorder(
              color: AppColors.themeColor,
              strokeWidth: 2.5,
              dashPattern: const [8, 4],
              borderType: BorderType.RRect,
              radius: const Radius.circular(6),
              child: SizedBox(width: guideW + 2, height: guideH + 2),
            ),
          ),

        // ── Rule-of-thirds grid inside the guide ──
        if (!widget.isCircular)
          IgnorePointer(
            child: Positioned.fill(
              child: CustomPaint(
                painter: GridPainter(
                  guideRect: Rect.fromLTWH(left, top, guideW, guideH),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom clippers for the dim overlay cutout
// ─────────────────────────────────────────────────────────────────────────────

/// Clips a circular hole out of a full-screen dim overlay.
class CircleCutoutClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  const CircleCutoutClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) {
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(PathOperation.reverseDifference, outer, inner);
  }

  @override
  bool shouldReclip(covariant CircleCutoutClipper old) =>
      old.center != center || old.radius != radius;
}

/// Clips a rectangular hole out of a full-screen dim overlay.
class RectCutoutClipper extends CustomClipper<Path> {
  final Rect cutoutRect;

  const RectCutoutClipper({required this.cutoutRect});

  @override
  Path getClip(Size size) {
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()..addRect(cutoutRect);
    return Path.combine(PathOperation.reverseDifference, outer, inner);
  }

  @override
  bool shouldReclip(covariant RectCutoutClipper old) =>
      old.cutoutRect != cutoutRect;
}

// ─────────────────────────────────────────────────────────────────────────────
/// Paints a "rule-of-thirds" grid inside the guide rectangle.
// ─────────────────────────────────────────────────────────────────────────────
class GridPainter extends CustomPainter {
  final Rect guideRect;

  const GridPainter({required this.guideRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (guideRect.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final x1 = guideRect.left + guideRect.width / 3;
    final x2 = guideRect.left + guideRect.width * 2 / 3;
    final y1 = guideRect.top + guideRect.height / 3;
    final y2 = guideRect.top + guideRect.height * 2 / 3;

    canvas.drawLine(
      Offset(x1, guideRect.top),
      Offset(x1, guideRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(x2, guideRect.top),
      Offset(x2, guideRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(guideRect.left, y1),
      Offset(guideRect.right, y1),
      paint,
    );
    canvas.drawLine(
      Offset(guideRect.left, y2),
      Offset(guideRect.right, y2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant GridPainter old) => old.guideRect != guideRect;
}
