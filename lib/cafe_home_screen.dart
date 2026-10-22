import 'package:flutter/material.dart';

import 'study_session.dart';

/// A warm, mobile-first dashboard for the existing Chainlink lobby.
/// Room creation, matching and joining still go through StudySession.
/// Classes are an editable *UI preview* until a class storage API is added.
class CafeHomeScreen extends StatefulWidget {
  const CafeHomeScreen({
    super.key,
    required this.session,
    required this.onJoinCode,
    this.inviteCode,
    required this.onLogout,
    required this.onToast,
  });

  final StudySession session;
  final Future<void> Function(String code) onJoinCode;
  final String? inviteCode;
  final VoidCallback onLogout;
  final void Function(String message) onToast;

  @override
  State<CafeHomeScreen> createState() => _CafeHomeScreenState();
}

class _CafeHomeScreenState extends State<CafeHomeScreen> {
  static const background = Color(0xFFF8F5EE);
  static const paper = Color(0xFFFFFDF9);
  static const espresso = Color(0xFF4B3B34);
  static const coffee = Color(0xFF8B654D);
  static const sage = Color(0xFF75876B);
  static const border = Color(0xFFEAE2D6);
  static const subtle = Color(0xFF92867A);

  int page = 0;
  bool searching = false;
  String search = '';
  final queryController = TextEditingController();
  final List<String> classes = ['Biology 101', 'Math 1201', 'History 105'];
  late Future<List<Map<String, dynamic>>> rooms;

  @override
  void initState() {
    super.initState();
    refreshRooms();
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  void refreshRooms() {
    rooms = widget.session.api.request('/public-rooms').then((json) {
      return (json['rooms'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    });
  }

  Future<void> reloadRooms() async {
    setState(refreshRooms);
    try {
      await rooms;
    } catch (_) {
      // The in-page error widget handles unreachable servers.
    }
  }

  Future<void> promptForCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a study room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Room code or invitation link',
            hintText: 'ABC234',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Join room'),
          ),
        ],
      ),
    );
    // Let the route close before disposing a controller still used in a pop animation.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (code == null || !mounted) return;
    final valid = roomCodeFrom(code);
    if (valid == null) {
      widget.onToast('Enter a valid 6-character code or invite link.');
      return;
    }
    await widget.onJoinCode(valid);
  }

  Future<void> addClass() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a class'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 28,
          decoration: const InputDecoration(
            hintText: 'e.g. CSC 4330',
            labelText: 'Class name',
            prefixIcon: Icon(Icons.menu_book_outlined),
          ),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add class'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (!mounted || title == null || title.isEmpty) return;
    if (classes.contains(title)) {
      widget.onToast('That class is already on your dashboard.');
      return;
    }
    setState(() => classes.add(title));
    widget.onToast('Added for this session. Class sync is coming later.');
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Column(
        children: [
          _header(),
          if (searching) _searchField(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: reloadRooms,
              color: sage,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                children: [
                  if (page == 0) _homeContent(),
                  if (page == 1) _studyContent(),
                  if (page == 2) _groupsContent(),
                  if (page == 3) _profileContent(),
                ],
              ),
            ),
          ),
          _bottomNavigation(),
        ],
      ),
    );
  }

  Widget _header() => Container(
    color: paper,
    padding: const EdgeInsets.fromLTRB(20, 9, 12, 9),
    child: Row(
      children: [
        const Icon(Icons.local_cafe_rounded, color: coffee, size: 23),
        const SizedBox(width: 9),
        const Text(
          'Chainlink',
          style: TextStyle(
            color: espresso,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Search classes and rooms',
          onPressed: () => setState(() {
            searching = !searching;
            if (!searching) {
              search = '';
              queryController.clear();
            }
          }),
          icon: const Icon(Icons.search_rounded, color: espresso),
        ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Notifications'),
              content: const Text(
                'You are all caught up! Group break updates and chat sounds appear while you are in a study room.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          ),
          icon: const Icon(Icons.notifications_none_rounded, color: espresso),
        ),
        InkWell(
          onTap: () => setState(() => page = 3),
          borderRadius: BorderRadius.circular(30),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFE8EADD),
            child: Text(
              (widget.session.user?['name'] as String? ?? 'S')
                  .characters.first.toUpperCase(),
              style: const TextStyle(color: espresso, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _searchField() => Container(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
    color: paper,
    child: TextField(
      controller: queryController,
      autofocus: true,
      onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Search your classes or room codes',
      ),
    ),
  );

  Widget _homeContent() {
    final username = (widget.session.user?['name'] as String? ?? 'friend').split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 11),
        Text(
          'Good ${_partOfDay()}, $username ☕',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: espresso,
            letterSpacing: -.65,
          ),
        ),
        const SizedBox(height: 5),
        const Text('Settle in, find your flow, and study at your pace.',
            style: TextStyle(fontSize: 13, color: subtle)),
        if (widget.inviteCode != null) ...[
          const SizedBox(height: 14),
          _surfaceCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline_rounded, color: sage),
              title: const Text('You have a study room invite!',
                  style: TextStyle(fontWeight: FontWeight.w700, color: espresso)),
              subtitle: Text('Room ${widget.inviteCode}'),
              trailing: const Icon(Icons.arrow_forward_rounded, color: coffee),
              onTap: () => widget.onJoinCode(widget.inviteCode!),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _actionCard(
                title: 'Study Alone',
                subtitle: 'A quiet corner, just for you',
                icon: Icons.menu_book_rounded,
                color: const Color(0xFFF1E6D5),
                onTap: () => widget.session.join('solo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                title: 'Study with Friends',
                subtitle: 'A table for your study crew',
                icon: Icons.groups_2_rounded,
                color: const Color(0xFFE5EBDF),
                onTap: () => setState(() => page = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _classesPanel()),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: _chatPanel()),
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeading('Active Study Rooms', action: 'See all', onTap: () => setState(() => page = 2)),
        const SizedBox(height: 10),
        _roomList(compact: true),
        const SizedBox(height: 10),
        const Center(
          child: Text('One task at a time. You’ve got this. ✨',
              style: TextStyle(fontSize: 12, color: subtle)),
        ),
      ],
    );
  }

  String _partOfDay() {
    final hour = DateTime.now().hour;
    return hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => Material(
    color: color,
    borderRadius: BorderRadius.circular(21),
    child: InkWell(
      borderRadius: BorderRadius.circular(21),
      onTap: widget.session.busy ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 165),
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                color: paper.withValues(alpha: .68),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, size: 27, color: coffee),
            ),
            const SizedBox(height: 17),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: espresso)),
            const SizedBox(height: 5),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, height: 1.25, color: coffee)),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.arrow_forward_rounded, size: 18, color: espresso),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _classesPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Your Classes', action: '+ Add', onTap: addClass),
      const SizedBox(height: 9),
      _surfaceCard(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          children: [
            for (final subject in classes.where((c) => c.toLowerCase().contains(search))) ...[
              _classTile(subject),
              const SizedBox(height: 7),
            ],
            if (classes.where((c) => c.toLowerCase().contains(search)).isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No matching classes.', style: TextStyle(color: subtle, fontSize: 12)),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Sample classes · local preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: subtle)),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _classTile(String title) => Material(
    color: const Color(0xFFF6F2EB),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => widget.onToast('Class pages are planned for a future update.'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.auto_stories_rounded, size: 19, color: sage),
            const SizedBox(width: 7),
            Expanded(
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: espresso)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 16, color: coffee),
          ],
        ),
      ),
    ),
  );

  Widget _chatPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Chat', action: 'Open', onTap: () => setState(() => page = 2)),
      const SizedBox(height: 9),
      _surfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const CircleAvatar(
              radius: 23,
              backgroundColor: Color(0xFFE9EBE2),
              child: Icon(Icons.chat_bubble_outline_rounded, color: sage, size: 23),
            ),
            const SizedBox(height: 13),
            const Text('Your study circle',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: espresso)),
            const SizedBox(height: 7),
            const Text(
              'Join a room to chat with classmates. Messages stay inside that room.',
              style: TextStyle(fontSize: 11, color: subtle, height: 1.4),
            ),
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => setState(() => page = 2),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Find a group', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sectionHeading(String title, {String? action, VoidCallback? onTap}) => Row(
    children: [
      Expanded(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: espresso, fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      if (action != null)
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Text(action,
                style: const TextStyle(fontSize: 11, color: coffee, fontWeight: FontWeight.w700)),
          ),
        ),
    ],
  );

  Widget _roomList({bool compact = false}) => FutureBuilder<List<Map<String, dynamic>>>(
    future: rooms,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return _surfaceCard(
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      }
      if (snapshot.hasError) {
        return _surfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not load public rooms.', style: TextStyle(color: espresso)),
              TextButton(onPressed: reloadRooms, child: const Text('Try again')),
            ],
          ),
        );
      }
      final found = snapshot.data!
          .where((r) => (r['code'] as String? ?? '').toLowerCase().contains(search))
          .take(compact ? 2 : 20)
          .toList();
      if (found.isEmpty) {
        return _surfaceCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFE9EBE2),
                child: Icon(Icons.groups_outlined, color: sage),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No open public rooms yet',
                        style: TextStyle(color: espresso, fontWeight: FontWeight.w700, fontSize: 12)),
                    SizedBox(height: 4),
                    Text('Start one and invite someone to join.',
                        style: TextStyle(color: subtle, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.session.busy ? null : () => widget.session.join('random'),
                child: const Text('Start'),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final room in found) ...[
            _surfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFE9EBE2),
                    child: Icon(Icons.groups_2_outlined, size: 20, color: sage),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Community room · ${room['code']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: espresso)),
                        const SizedBox(height: 3),
                        Text('${room['members']} / 8 members online',
                            style: const TextStyle(color: subtle, fontSize: 11)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.session.busy
                        ? null
                        : () => widget.onJoinCode(room['code'] as String),
                    child: const Text('Join'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );
    },
  );

  Widget _studyContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      const Text('Your study nook', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: espresso)),
      const SizedBox(height: 6),
      const Text('Choose the kind of focus session you need today.',
          style: TextStyle(color: subtle, fontSize: 13)),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _actionCard(
          title: 'Quiet solo', subtitle: 'Just you and your goals', icon: Icons.self_improvement_rounded,
          color: const Color(0xFFF1E6D5), onTap: () => widget.session.join('solo'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _actionCard(
          title: 'Study group', subtitle: 'Build your own room', icon: Icons.diversity_3_rounded,
          color: const Color(0xFFE5EBDF), onTap: () => widget.session.join('group'),
        )),
      ]),
      const SizedBox(height: 18),
      _surfaceCard(child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.vpn_key_outlined, color: coffee),
        title: const Text('Have an invite code?', style: TextStyle(fontWeight: FontWeight.w700, color: espresso)),
        subtitle: const Text('Jump into a classmate’s room.'),
        trailing: const Icon(Icons.arrow_forward_rounded, color: coffee),
        onTap: promptForCode,
      )),
    ],
  );

  Widget _groupsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      const Text('Study together', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: espresso)),
      const SizedBox(height: 7),
      const Text('Like a shared coffee-shop table, but wherever you are.',
          style: TextStyle(color: subtle, fontSize: 13)),
      const SizedBox(height: 20),
      _surfaceCard(child: Column(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.group_add_outlined, color: sage),
          title: const Text('Create a private group', style: TextStyle(fontWeight: FontWeight.w700, color: espresso)),
          subtitle: const Text('Invite your friends with a shareable code.'),
          onTap: widget.session.busy ? null : () => widget.session.join('group'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tag_rounded, color: coffee),
          title: const Text('Join with a code', style: TextStyle(fontWeight: FontWeight.w700, color: espresso)),
          subtitle: const Text('Enter the code your friend shared.'),
          onTap: promptForCode,
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.travel_explore_rounded, color: sage),
          title: const Text('Find a study group', style: TextStyle(fontWeight: FontWeight.w700, color: espresso)),
          subtitle: const Text('Match with an open public room.'),
          onTap: widget.session.busy ? null : () => widget.session.join('random'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ])),
      const SizedBox(height: 22),
      _sectionHeading('Public rooms', action: 'Refresh', onTap: reloadRooms),
      const SizedBox(height: 10),
      _roomList(),
    ],
  );

  Widget _profileContent() {
    final name = (widget.session.user?['name'] as String?) ?? 'Student';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('Your profile', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: espresso)),
      const SizedBox(height: 18),
      _surfaceCard(child: Row(children: [
        CircleAvatar(radius: 28, backgroundColor: const Color(0xFFE8EADD),
          child: Text(name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 22, color: espresso, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: espresso)),
          const SizedBox(height: 5),
          const Text('Ready for your next study session', style: TextStyle(fontSize: 12, color: subtle)),
        ])),
      ])),
      const SizedBox(height: 18),
      _surfaceCard(child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.logout_rounded, color: coffee),
        title: const Text('Log out', style: TextStyle(color: espresso, fontWeight: FontWeight.w700)),
        onTap: widget.session.busy ? null : widget.onLogout,
      )),
    ]);
  }

  Widget _surfaceCard({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: paper,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(17),
      boxShadow: const [
        BoxShadow(color: Color(0x0A4B3B34), blurRadius: 14, offset: Offset(0, 5)),
      ],
    ),
    child: child,
  );

  Widget _bottomNavigation() => Container(
    decoration: const BoxDecoration(
      color: paper,
      border: Border(top: BorderSide(color: border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 4, 5, 3),
        child: Row(children: [
          _nav(0, Icons.home_rounded, 'Home'),
          _nav(1, Icons.menu_book_rounded, 'Study'),
          _nav(2, Icons.groups_2_rounded, 'Groups'),
          _nav(3, Icons.person_outline_rounded, 'Profile'),
        ]),
      ),
    ),
  );

  Widget _nav(int index, IconData icon, String title) {
    final active = page == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => page = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: active ? coffee : subtle, size: 22),
            const SizedBox(height: 3),
            Text(title,
                style: TextStyle(fontSize: 11, color: active ? coffee : subtle,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
