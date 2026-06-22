import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/cancel_button.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/features/profile/shared/models/social_link_param.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/features/profile/student/providers/edit_profile_provider.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
import '../widgets/edit_app_bar.dart';
import '../widgets/input_field_module.dart';
import '../widgets/gender_select_module.dart';
import '../widgets/bio_field_module.dart';
import '../widgets/date_of_birth_field.dart';
import '../widgets/social_link_form_block_ui.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  static const String name = '/edit-profile';

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ValueNotifier<int> _resetNotifier = ValueNotifier(0);
  Timer? _errorTimer;

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _nameError = null;
        _usernameError = null;
        _phoneError = null;
        _professionError = null;
        _countryError = null;
        _dobError = null;
      });
    });
  }

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _dobController;
  late final TextEditingController _professionController;
  late final TextEditingController _bioController;
  late final TextEditingController _countryController;

  final List<TextEditingController> _platformControllers = [];
  final List<TextEditingController> _urlControllers = [];

  String? _selectedGender;

  String? _nameError;
  String? _usernameError;
  String? _phoneError;
  String? _professionError;
  String? _countryError;
  String? _dobError;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initControllers();
    }
  }

  UserProfileEntity? _resolveProfile() {
    final studentProfile = context.read<StudentProfileProvider>().profile;
    if (studentProfile != null && studentProfile.role == 'STUDENT') {
      return studentProfile;
    }
    return context.read<MentorProfileProvider>().profile ?? studentProfile;
  }

  void _initControllers() {
    final profile = _resolveProfile();

    _nameController = TextEditingController(text: profile?.name ?? '');
    _usernameController = TextEditingController(text: profile?.username ?? '');
    _phoneController = TextEditingController(text: profile?.phone ?? '');
    _dobController = TextEditingController(
      text: profile?.dob != null ? _formatDate(profile!.dob!) : '',
    );
    _professionController = TextEditingController(text: profile?.profession ?? '');
    _bioController = TextEditingController(text: profile?.bio ?? '');
    _countryController = TextEditingController(text: profile?.country ?? '');

    if (profile?.gender != null) {
      _selectedGender = profile!.gender == 1 ? 'Male' : 'Female';
    }

    if (profile != null) {
      for (final link in profile.socialLinks) {
        _platformControllers.add(TextEditingController(text: link.platform));
        _urlControllers.add(TextEditingController(text: link.url));
      }
    }
  }

  int _resolveBioMaxLength() {
    final profile = _resolveProfile();
    return profile?.role == 'STUDENT' ? 80 : 300;
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

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
                        : DateTime.now().subtract(const Duration(days: 365 * 18)),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    onDateChanged: (DateTime picked) {
                      _dobController.text = _formatDate(picked);
                      setState(() => _dobError = null);
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

  bool _validate() {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final profession = _professionController.text.trim();
    final dob = _dobController.text.trim();

    bool hasError = false;

    if (name.isNotEmpty && name.split(' ').length < 2) {
      _nameError = "Please enter at least two names";
      hasError = true;
    } else {
      _nameError = null;
    }

    if (username.isNotEmpty && username.length < 3) {
      _usernameError = "Username must be at least 3 characters";
      hasError = true;
    } else if (username.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _usernameError = "Only letters, numbers, and underscores allowed";
      hasError = true;
    } else {
      _usernameError = null;
    }

    _countryError = null;

    if (phone.isNotEmpty && !RegExp(r'^\+?\d{10,15}$').hasMatch(phone)) {
      _phoneError = "Enter a valid phone number";
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

    if (dob.isEmpty) {
      _dobError = "Date of birth is required";
      hasError = true;
    } else {
      final parts = dob.split('-');
      final year = int.tryParse(parts[0]) ?? 0;
      final month = int.tryParse(parts[1]) ?? 0;
      final day = int.tryParse(parts[2]) ?? 0;
      if (DateTime(year, month, day).isAfter(DateTime.now())) {
        _dobError = "Date of birth cannot be in the future";
        hasError = true;
      } else {
        _dobError = null;
      }
    }

    setState(() {});
    return !hasError;
  }

  List<SocialLinkParam> _buildSocialLinks() {
    return List.generate(_platformControllers.length, (i) {
      return SocialLinkParam(
        platform: _platformControllers[i].text.trim(),
        url: _urlControllers[i].text.trim(),
      );
    }).where((link) => link.platform.isNotEmpty || link.url.isNotEmpty).toList();
  }

  Future<void> _saveProfileData() async {
    if (!_validate()) {
      _scheduleErrorClear();
      return;
    }

    final isMentor =
        context.read<MentorProfileProvider>().profile?.role == 'MENTOR' ||
        context.read<StudentProfileProvider>().profile?.role == 'MENTOR';

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final dob = _dobController.text.trim();
    final profession = _professionController.text.trim();
    final bio = _bioController.text.trim();
    final country = _countryController.text.trim();
    final gender = _selectedGender != null ? (_selectedGender == 'Male' ? 1 : 0) : null;
    final socialLinks = _buildSocialLinks();

    bool success;
    if (isMentor) {
      success = await context.read<MentorProfileProvider>().updateProfile(
        name: name,
        username: username,
        phone: phone,
        dob: dob.isNotEmpty ? dob : null,
        profession: profession,
        bio: bio,
        country: country,
        gender: gender,
        socialLinks: socialLinks,
      );
    } else {
      await context.read<EditProfileProvider>().updateProfile(
        name: name,
        username: username,
        phone: phone,
        dob: dob.isNotEmpty ? dob : null,
        profession: profession,
        bio: bio,
        country: country,
        gender: gender,
        socialLinks: socialLinks,
      );

      final editProvider = context.read<EditProfileProvider>();
      success = editProvider.isSuccess;
      if (success && editProvider.updatedProfile != null) {
        context.read<StudentProfileProvider>().refreshProfile(
          editProvider.updatedProfile!.copyWith(
            name: name,
            username: username,
            phone: phone,
            profession: profession,
            bio: bio,
            country: country,
          ),
        );
      }
    }

    if (success && mounted) {
      Navigator.maybePop(context);
    }
  }

  void _addSocialLink() {
    setState(() {
      _platformControllers.add(TextEditingController());
      _urlControllers.add(TextEditingController());
    });
  }

  void _removeSocialLink(int index) {
    setState(() {
      _platformControllers[index].dispose();
      _urlControllers[index].dispose();
      _platformControllers.removeAt(index);
      _urlControllers.removeAt(index);
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _resetNotifier.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _professionController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    for (final c in _platformControllers) { c.dispose(); }
    for (final c in _urlControllers) { c.dispose(); }
    super.dispose();
  }

  List<String> _socialPlatforms() {
    return _resolveProfile()?.socialPlatforms ?? <String>[];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EditAppBarModule(),
      body: Consumer<EditProfileProvider>(
        builder: (context, provider, _) {
          final isLoading = provider.isLoading ||
              context.watch<MentorProfileProvider>().isLoading;

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.horizontalPadding,
                vertical: 8,
              ),
              child: Form(
                key: _formKey,
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
                        if (value.trim().isEmpty || value.trim().split(' ').length >= 2) {
                          _nameError = null;
                        } else {
                          _nameError = "Please enter at least two names";
                        }
                      });
                      if (value.isNotEmpty) {
                        _capitalizeName(value);
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
                          _usernameError = "Username must be at least 3 characters";
                        } else if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                          _usernameError = "Only letters, numbers, and underscores allowed";
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
                        } else if (!RegExp(r'^\+?\d{10,15}$').hasMatch(value.trim())) {
                          _phoneError = "Enter a valid phone number";
                        } else {
                          _phoneError = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  DateOfBirthField(
                    controller: _dobController,
                    onTap: _showDatePicker,
                    errorText: _dobError,
                  ),
                  const SizedBox(height: 20),
                  InputFieldModule(
                    label: "Profession",
                    controller: _professionController,
                    errorText: _professionError,
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                    onChanged: (value) {
                      setState(() {
                        if (value.trim().isEmpty || value.trim().length >= 2) {
                          _professionError = null;
                        } else {
                          _professionError = "Profession must be at least 2 characters";
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  GenderSelectModule(
                    selectedGender: _selectedGender,
                    onChanged: (value) => setState(() => _selectedGender = value),
                  ),
                  const SizedBox(height: 20),
                  BioFieldModule(
                    label: "Bio",
                    controller: _bioController,
                    maxLength: _resolveBioMaxLength(),
                  ),
                  const SizedBox(height: 20),
                  SocialLinksFormBlockUi(
                    key: ValueKey(_platformControllers.length),
                    resetNotifier: _resetNotifier,
                    platformControllers: _platformControllers,
                    urlControllers: _urlControllers,
                    socialPlatforms: _socialPlatforms(),
                    onAdd: _addSocialLink,
                    onRemove: _removeSocialLink,
                  ),
                  const SizedBox(height: 40),
                  AuthButton(
                    text: 'Save Changes',
                    isLoading: isLoading,
                    onPressed: _saveProfileData,
                    height: 52,
                    borderRadius: 24,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: CancelButton(
                      onPressed: isLoading
                          ? null
                          : () => Navigator.maybePop(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
          },
        ),
      );
  }

  void _capitalizeName(String value) {
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
}
