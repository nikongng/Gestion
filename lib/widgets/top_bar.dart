import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'notification_bell_button.dart';
import 'profile_avatar.dart';
import 'theme_mode_menu_button.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onOpenAlerts,
  });

  final UserProfile profile;
  final VoidCallback onLogout;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher une transaction, une taxe...',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const ThemeModeMenuButton(),
          const SizedBox(width: 4),
          NotificationBellButton(profile: profile, onOpenAlerts: onOpenAlerts),
          const SizedBox(width: 8),
          ProfileAvatar(
            fullName: profile.fullName,
            avatarUrl: profile.avatarUrl,
            radius: 16,
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(
              '${profile.rolesLabel} · ${profile.fullName.split(' ').first}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
    );
  }
}
