import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/features/profile/shared/models/social_link_param.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/features/profile/student/providers/edit_profile_provider.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
import '../widgets/social_link_form_block_ui.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  static const String name = '/edit-profile';

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  Future<void> _showDatePicker() async {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: 450,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Select Date of Birth",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme(
                      brightness: cs.brightness,
                      primary: cs.primary,
                      onPrimary: cs.onPrimary,
                      secondary: cs.secondary,
                      onSecondary: cs.onSecondary,
                      error: cs.error,
                      onError: cs.onError,
                      surface: cs.surface,
                      onSurface: cs.onSurface,
                    ),
                  ),
                  child: CalendarDatePicker(
                    initialDate: _dobController.text.isNotEmpty
                        ? DateTime.parse(_dobController.text)
                        : DateTime.now().subtract(
                            const Duration(days: 365 * 18),
                          ),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    onDateChanged: (DateTime picked) {
                      final formattedDate =
                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                      _dobController.text = formattedDate;
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _dobController;
  late final TextEditingController _professionController;
  late final TextEditingController _bioController;
  late final TextEditingController _countryController;

  final List<_SocialLinkEntry> _socialLinks = [];

  String? _selectedGender;

  String? _nameError;
  String? _usernameError;
  String? _phoneError;
  String? _professionError;
  String? _countryError;

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initControllers();
    }
  }

  void _initControllers() {
    final studentProfile = context.read<StudentProfileProvider>().profile;
    UserProfileEntity? profile;
    if (studentProfile?.role == 'STUDENT') {
      profile = studentProfile;
    } else {
      profile =
          context.read<MentorProfileProvider>().profile ?? studentProfile;
    }

    _nameController = TextEditingController(text: profile?.name ?? '');
    _usernameController = TextEditingController(text: profile?.username ?? '');
    _phoneController = TextEditingController(text: profile?.phone ?? '');
    _dobController = TextEditingController(
      text: profile?.dob != null ? _formatDate(profile!.dob!) : '',
    );
    _professionController = TextEditingController(
      text: profile?.profession ?? '',
    );
    _bioController = TextEditingController(text: profile?.bio ?? '');
    _countryController = TextEditingController(text: profile?.country ?? '');

    if (profile?.gender != null) {
      _selectedGender = profile!.gender == 1 ? 'Male' : 'Female';
    }

    if (profile != null) {
      for (final link in profile.socialLinks) {
        _socialLinks.add(
          _SocialLinkEntry(
            platformController: TextEditingController(text: link.platform),
            urlController: TextEditingController(text: link.url),
          ),
        );
      }
    }
  }

  int _resolveBioMaxLength() {
    final studentProfile = context.read<StudentProfileProvider>().profile;
    if (studentProfile?.role == 'STUDENT') return 80;
    final mentorProfile = context.read<MentorProfileProvider>().profile;
    if (mentorProfile?.role == 'MENTOR') return 300;
    return studentProfile?.role == 'STUDENT' ? 80 : 300;
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _professionController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    for (final entry in _socialLinks) {
      entry.platformController.dispose();
      entry.urlController.dispose();
    }
    super.dispose();
  }

  Future<void> _saveProfileData() async {
    final provider = context.read<EditProfileProvider>();

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final country = _countryController.text.trim();
    final profession = _professionController.text.trim();

    bool hasError = false;

    if (name.isNotEmpty && name.split(' ').length < 2) {
      _nameError = "Please enter at least two names";
      hasError = true;
    } else {
      _nameError = null;
    }

    if (username.isNotEmpty) {
      if (username.length < 3) {
        _usernameError = "Username must be at least 3 characters";
        hasError = true;
      } else if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
        _usernameError = "Only letters, numbers, and underscores allowed";
        hasError = true;
      } else {
        _usernameError = null;
      }
    } else {
      _usernameError = null;
    }

    _countryError = null;

    if (phone.isNotEmpty && !RegExp(r'^01[3-9]\d{8}$').hasMatch(phone)) {
      _phoneError = "Enter a valid 11-digit Bangladeshi number";
      hasError = true;
    } else {
      _phoneError = null;
    }

    if (profession.isNotEmpty && profession.length < 2) {
      _professionError = "Profession must be at least 2 characters";
      hasError = true;
    } else {
      _professionError = null;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    setState(() => _isSaving = true);

    final isMentor =
        context.read<MentorProfileProvider>().profile?.role == 'MENTOR' ||
        context.read<StudentProfileProvider>().profile?.role == 'MENTOR';

    if (isMentor) {
      final success = await context.read<MentorProfileProvider>().updateProfile(
        name: name,
        username: username,
        phone: _phoneController.text.trim(),
        dob: _dobController.text.trim(),
        profession: _professionController.text.trim(),
        bio: _bioController.text.trim(),
        country: _countryController.text.trim(),
        gender: _selectedGender != null
            ? (_selectedGender == 'Male' ? 1 : 0)
            : null,
        socialLinks: () {
          final links = _socialLinks
              .map((entry) => SocialLinkParam(
                    platform: entry.platformController.text.trim(),
                    url: entry.urlController.text.trim(),
                  ))
              .where((link) => link.platform.isNotEmpty || link.url.isNotEmpty)
              .toList();
          return links;
        }(),
      );
      setState(() => _isSaving = false);
      if (success && mounted) {
        Navigator.maybePop(context);
      }
    } else {
      await provider.updateProfile(
        name: name,
        username: username,
        phone: _phoneController.text.trim(),
        dob: _dobController.text.trim(),
        profession: _professionController.text.trim(),
        bio: _bioController.text.trim(),
        country: _countryController.text.trim(),
        gender: _selectedGender != null
            ? (_selectedGender == 'Male' ? 1 : 0)
            : null,
        socialLinks: () {
          final links = _socialLinks
              .map((entry) => SocialLinkParam(
                    platform: entry.platformController.text.trim(),
                    url: entry.urlController.text.trim(),
                  ))
              .where((link) => link.platform.isNotEmpty || link.url.isNotEmpty)
              .toList();
          return links;
        }(),
      );

      setState(() => _isSaving = false);

      if (provider.isSuccess && mounted) {
        if (provider.updatedProfile != null) {
          final merged = provider.updatedProfile!.copyWith(
            name: name,
            username: username,
            phone: phone,
            profession: _professionController.text.trim(),
            bio: _bioController.text.trim(),
            country: country,
          );
          context.read<StudentProfileProvider>().refreshProfile(merged);
        }
        Navigator.maybePop(context);
      }
    }
  }

  void _addSocialLink() {
    setState(() {
      _socialLinks.add(
        _SocialLinkEntry(
          platformController: TextEditingController(),
          urlController: TextEditingController(),
        ),
      );
    });
  }

  void _removeSocialLink(int index) {
    setState(() {
      _socialLinks[index].platformController.dispose();
      _socialLinks[index].urlController.dispose();
      _socialLinks.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EditAppBarModule(),
      body: Consumer<EditProfileProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InputFieldModule(
                  label: "Full name",
                  controller: _nameController,
                  errorText: _nameError,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  onChanged: (value) {
                    setState(() {
                      if (value.trim().isEmpty) {
                        _nameError = null;
                      } else if (value.trim().split(' ').length < 2) {
                        _nameError = "Please enter at least two names";
                      } else {
                        _nameError = null;
                      }
                    });
                    if (value.isNotEmpty) {
                      final words = value.split(' ');
                      final capitalized = words.map((w) {
                        if (w.isEmpty) return w;
                        if (w.length == 1) return w.toUpperCase();
                        return w[0].toUpperCase() + w.substring(1);
                      }).join(' ');
                      if (_nameController.text != capitalized) {
                        _nameController.value = TextEditingValue(
                          text: capitalized,
                          selection: _nameController.selection,
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 20),
                InputFieldModule(
                  label: "Username",
                  controller: _usernameController,
                  errorText: _usernameError,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        _usernameError = null;
                      } else if (value.length < 3) {
                        _usernameError =
                            "Username must be at least 3 characters";
                      } else if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                        _usernameError =
                            "Only letters, numbers, and underscores allowed";
                      } else {
                        _usernameError = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
                InputFieldModule(
                  label: "Country",
                  controller: _countryController,
                  errorText: _countryError,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                ),
                const SizedBox(height: 20),
                InputFieldModule(
                  label: "Phone Number",
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  errorText: _phoneError,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "+88",
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 24,
                          child: VerticalDivider(
                            thickness: 1,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value.trim().isEmpty) {
                        _phoneError = null;
                      } else if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(
                        value.trim(),
                      )) {
                        _phoneError =
                            "Enter a valid 11-digit Bangladeshi number";
                      } else {
                        _phoneError = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
                _DateOfBirthField(
                  controller: _dobController,
                  onTap: _showDatePicker,
                ),
                const SizedBox(height: 20),
                InputFieldModule(
                  label: "Profession",
                  controller: _professionController,
                  errorText: _professionError,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  onChanged: (value) {
                    setState(() {
                      if (value.trim().isEmpty) {
                        _professionError = null;
                      } else if (value.trim().length < 2) {
                        _professionError =
                            "Profession must be at least 2 characters";
                      } else {
                        _professionError = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
                GenderSelectModule(
                  selectedGender: _selectedGender,
                  onChanged: (value) {
                    setState(() => _selectedGender = value);
                  },
                ),
                const SizedBox(height: 20),
                BioFieldModule(
                  label: "Bio",
                  controller: _bioController,
                  maxLength: _resolveBioMaxLength(),
                ),
                const SizedBox(height: 20),
                SocialLinksFormBlockUi(
                  key: ValueKey(_socialLinks.length),
                  platformControllers: _socialLinks
                      .map((e) => e.platformController)
                      .toList(),
                  urlControllers: _socialLinks
                      .map((e) => e.urlController)
                      .toList(),
                  socialPlatforms:
                      (context
                              .read<StudentProfileProvider>()
                              .profile
                              ?.socialPlatforms ??
                          context
                              .read<MentorProfileProvider>()
                              .profile
                              ?.socialPlatforms) ??
                      <String>[],
                  onAdd: _addSocialLink,
                  onRemove: _removeSocialLink,
                ),
                const SizedBox(height: 40),
                if (provider.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      ToastService.friendlyMessage(provider.errorMessage!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                AuthButton(
                  text: 'Save Changes',
                  isLoading: _isSaving || provider.isLoading,
                  onPressed: _saveProfileData,
                  height: 52,
                  borderRadius: 24,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: provider.isLoading ? null : () => Navigator.maybePop(context),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SocialLinkEntry {
  final TextEditingController platformController;
  final TextEditingController urlController;

  _SocialLinkEntry({
    required this.platformController,
    required this.urlController,
  });
}

class _DateOfBirthField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onTap;

  const _DateOfBirthField({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabelLabelAtom(label: "Date of birth"),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: "Select your Date of Birth",
            hintStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class EditAppBarModule extends StatelessWidget implements PreferredSizeWidget {
  const EditAppBarModule({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scBg = Theme.of(context).scaffoldBackgroundColor;
    final iconBg = cs.surfaceContainerHighest;
    return AppBar(
      backgroundColor: scBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: Text(
        "Edit Profile",
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: iconBg,
          child: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 14, color: cs.onSurface),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class InputFieldModule extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;

  const InputFieldModule({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabelLabelAtom(label: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            filled: true,
            prefixIcon: prefixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            errorText: errorText,
            errorMaxLines: 2,
            errorStyle: TextStyle(
              fontSize: 11,
              color: cs.error,
              fontWeight: FontWeight.w400,
            ),
            helperText: errorText == null ? helperText : null,
            helperMaxLines: 1,
            helperStyle: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w400,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.error, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class GenderSelectModule extends StatelessWidget {
  final String? selectedGender;
  final ValueChanged<String?> onChanged;

  const GenderSelectModule({
    super.key,
    required this.selectedGender,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabelLabelAtom(label: "Gender"),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant, width: 1),
          ),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedGender,
                isExpanded: true,
                hint: Text(
                  "Select gender",
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                ],
                onChanged: onChanged,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BioFieldModule extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final int maxLength;

  const BioFieldModule({
    super.key,
    required this.label,
    required this.controller,
    this.maxLength = 300,
  });

  @override
  State<BioFieldModule> createState() => _BioFieldModuleState();
}

class _BioFieldModuleState extends State<BioFieldModule> {
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _charCount = widget.controller.text.length;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newCount = widget.controller.text.length;
    if (newCount != _charCount) {
      setState(() => _charCount = newCount);
    }
  }

  Color _counterColor(int count, int max) {
    final cs = Theme.of(context).colorScheme;
    if (count >= max) return cs.error;
    if (count >= max * 0.8) return cs.error.withValues(alpha: 0.7);
    return cs.onSurface.withValues(alpha: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _charCount;
    final max = widget.maxLength;
    final counterColor = _counterColor(count, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FieldLabelLabelAtom(label: widget.label),
            Text(
              "$count/$max",
              style: TextStyle(
                color: counterColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          textInputAction: TextInputAction.done,
          controller: widget.controller,
          maxLines: 4,
          maxLength: max,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: "Tell us about yourself...",
            hintStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            contentPadding: const EdgeInsets.all(20),
            counterText: "",
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: count >= max
                    ? cs.error
                    : cs.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FieldLabelLabelAtom extends StatelessWidget {
  final String label;
  const FieldLabelLabelAtom({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
