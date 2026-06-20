import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/features/courses/providers/video_post_provider.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/upload_zone.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});
  static const String name = '/upload-video-page';

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final TextEditingController _titleController = TextEditingController();
  int _characterCount = 0;
  bool _didReset = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() {
      setState(() => _characterCount = _titleController.text.length);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didReset) {
      _didReset = true;
      final provider = context.read<VideoPostProvider>();
      if (!provider.isLoading) {
        provider.reset();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _handleUpload(VideoPostProvider provider) async {
    if (_titleController.text.trim().isEmpty) {
      ToastService.showError('Title is required');
      return;
    }
    if (provider.videoFile == null) {
      ToastService.showError('Please select a video file');
      return;
    }

    if (mounted) {
      Navigator.of(context).pop();
      ToastService.showSuccess('Your Video is being uploaded');
    }

    provider.uploadVideoPost(
      title: _titleController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: AppBackButton(),
        ),
        title: Text('Upload Video', style: TextStyle(fontSize: 20, color: cs.onSurface)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Consumer<VideoPostProvider>(
                      builder: (context, provider, _) {
                        return UploadZone(
                          cs: cs,
                          isDark: isDark,
                          isPicking: provider.isPicking,
                          onTap: provider.isPicking ? null : () => provider.pickVideo(),
                          selectedFileName: provider.videoFile?.name,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Title', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        Text(
                          '$_characterCount/60',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      maxLines: 4,
                      maxLength: 60,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Enter your video title',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark ? cs.outlineVariant : AppColors.border,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.themeColor, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Consumer<VideoPostProvider>(
                builder: (context, provider, _) {
                  return AuthButton(
                    text: provider.buttonText,
                    borderRadius: 28,
                    onPressed: provider.isLoading ? null : () => _handleUpload(provider),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
