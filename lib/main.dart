import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'study_session.dart';

const ink = Color(0xFF18191C);
const muted = Color(0xFF6B6E76);
const line = Color(0xFFE7E8EB);
const accent = Color(0xFF3159CF);
const surface = Color(0xFFF5F6F8);
const titleStyle = TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.w600,
  letterSpacing: -.7,
);
const sectionStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChainlinkApp());
}

class ChainlinkApp extends StatelessWidget {
  final StudySession? session;
  const ChainlinkApp({super.key, this.session});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chainlink',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: ink,
        secondaryContainer: surface,
        onSecondaryContainer: ink,
        surface: Colors.white,
        onSurface: ink,
        outline: Color(0xFFC9CBD1),
        surfaceContainerHighest: surface,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: muted, fontSize: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: ink,
        thumbColor: ink,
        inactiveTrackColor: line,
        trackHeight: 3,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? ink : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : ink,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: ink,
        dividerColor: line,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: StudyHome(session: session),
  );
}

class StudyHome extends StatefulWidget {
  final StudySession? session;
  const StudyHome({super.key, this.session});
  @override
  State<StudyHome> createState() => _StudyHomeState();
}

class _StudyHomeState extends State<StudyHome> {
  late final StudySession session;
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  final code = TextEditingController(), message = TextEditingController();
  final chatScroll = ScrollController();
  final form = GlobalKey<FormState>();
  final music = AudioPlayer(), chime = AudioPlayer();
  StreamSubscription<Uri>? links;
  Timer? clock;
  bool register = true,
      hidePassword = true,
      musicPlaying = false,
      musicBusy = false;
  bool musicMuted = false,
      chatMuted = false,
      shareBreak = true,
      stopwatch = false;
  double musicVolume = .35, chatVolume = .5;
  int breakMinutes = 5, lastMessage = 0;
  String? lastRoom, displayedError, pendingInvite;
  Set<String> breakingMembers = {};
  DateTime serverClock = DateTime.now(),
      receivedClock = DateTime.now(),
      joinedAt = DateTime.now();
  Object? lastSnapshot;

  @override
  void initState() {
    super.initState();
    session = widget.session ?? StudySession();
    session.addListener(onSession);
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && session.room != null) setState(() {});
    });
    if (widget.session == null) {
      links = AppLinks().uriLinkStream.listen(receiveInvite, onError: (_) {});
      if (kIsWeb) receiveInvite(Uri.base);
    }
  }

  void receiveInvite(Uri uri) {
    final invite = roomCodeFrom(uri.toString());
    if (invite == null || invite == session.room?['code']) return;
    setState(() {
      pendingInvite = invite;
      code.text = invite;
    });
    if (session.room != null) {
      toast('Invite to $invite. Leave the current room to join.');
    }
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void onSession() {
    if (!mounted) return;
    final currentRoom = session.room?['code'] as String?;
    final changedRoom = currentRoom != lastRoom;
    final incoming = session.messages;
    final maxMessage = incoming.isEmpty ? 0 : incoming.last['id'] as int;
    final breaking = session.members
        .where(
          (m) => m['id'] != session.user?['id'] && m['break_start'] != null,
        )
        .map((m) => m['id'] as String)
        .toSet();
    if (!changedRoom) {
      if (incoming.any(
        (m) =>
            (m['id'] as int) > lastMessage &&
            m['user_id'] != session.user?['id'],
      )) {
        unawaited(playChime());
      }
      for (final member in session.members) {
        if (breaking.contains(member['id']) &&
            !breakingMembers.contains(member['id'])) {
          toast('${member['name']} is taking a break.');
        }
      }
    }
    if (changedRoom) {
      if (currentRoom == null) {
        unawaited(music.stop().catchError((_) {}));
        musicPlaying = false;
      } else {
        pendingInvite = null;
        joinedAt = DateTime.now();
      }
      message.clear();
    }
    if (session.room != null && !identical(lastSnapshot, session.room)) {
      serverClock = DateTime.fromMillisecondsSinceEpoch(
        ((session.room!['server_time'] as num) * 1000).round(),
      );
      receivedClock = DateTime.now();
      lastSnapshot = session.room;
    }
    if (session.error != null && session.error != displayedError) {
      toast(session.error!);
    }
    displayedError = session.error;
    final shouldScroll = changedRoom || maxMessage != lastMessage;
    lastRoom = currentRoom;
    lastMessage = maxMessage;
    breakingMembers = breaking;
    setState(() {});
    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (chatScroll.hasClients) {
          chatScroll.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> playChime() async {
    if (chatMuted || chatVolume == 0) return;
    try {
      await chime.setVolume(chatVolume);
      await chime.play(AssetSource('audio/message.wav'));
    } catch (_) {
      /* An unavailable audio device must not interrupt room updates. */
    }
  }

  Future<void> toggleMusic() async {
    if (musicBusy) return;
    setState(() => musicBusy = true);
    try {
      if (musicPlaying) {
        await music.pause();
      } else {
        await music.setReleaseMode(ReleaseMode.loop);
        await music.setVolume(musicMuted ? 0 : musicVolume);
        await music.play(AssetSource('audio/quiet_hours.wav'));
      }
      if (mounted) setState(() => musicPlaying = !musicPlaying);
    } catch (_) {
      toast('Audio could not start. Please try again.');
    } finally {
      if (mounted) setState(() => musicBusy = false);
    }
  }

  Future<void> updateMusicVolume() async {
    try {
      await music.setVolume(musicMuted ? 0 : musicVolume);
    } catch (_) {
      toast('Could not adjust audio. Try restarting the music.');
    }
  }

  @override
  void dispose() {
    clock?.cancel();
    links?.cancel();
    session.removeListener(onSession);
    if (widget.session == null) session.dispose();
    for (final controller in [name, email, password, code, message]) {
      controller.dispose();
    }
    chatScroll.dispose();
    music.dispose();
    chime.dispose();
    super.dispose();
  }

  Future<void> serverSettings() async {
    final controller = TextEditingController(text: session.api.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Study server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use the same server on every device. For a phone, use your computer’s local network address.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.10:8080',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (value != null) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          (uri.path != '' && uri.path != '/')) {
        toast('Enter a valid http or https server address without a path.');
      } else {
        setState(
          () => session.api.baseUrl = value.trim().replaceFirst(
            RegExp(r'/$'),
            '',
          ),
        );
        toast('Server address updated.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 26, color: ink),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Chainlink',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.4,
                        ),
                      ),
                    ),
                    if (session.user == null)
                      IconButton(
                        onPressed: session.busy ? null : serverSettings,
                        tooltip: 'Server settings',
                        icon: const Icon(Icons.settings_outlined, size: 21),
                      )
                    else
                      PopupMenuButton<String>(
                        tooltip: 'Account',
                        enabled: !session.busy,
                        onSelected: (_) => session.logout(),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'logout',
                            child: Text('Log out (${session.user!['name']})'),
                          ),
                        ],
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: surface,
                          foregroundColor: ink,
                          child: Text(
                            (session.user!['name'] as String).characters.first
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (session.busy)
                const LinearProgressIndicator(minHeight: 1, color: accent)
              else
                const Divider(),
              Expanded(
                child: session.user == null
                    ? authView()
                    : session.room == null
                    ? lobbyView()
                    : roomView(),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget authView() => SingleChildScrollView(
    key: const ValueKey('auth'),
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(register ? 'Create account' : 'Log in', style: titleStyle),
            const SizedBox(height: 8),
            const Text(
              'Study alone or join a group.',
              style: TextStyle(color: muted, fontSize: 15),
            ),
            if (pendingInvite != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  'Room invite: $pendingInvite',
                  style: const TextStyle(color: accent),
                ),
              ),
            const SizedBox(height: 32),
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (register) ...[
                    fieldLabel('Name'),
                    TextFormField(
                      controller: name,
                      maxLength: 30,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.nickname],
                      decoration: const InputDecoration(
                        hintText: 'Display name',
                        counterText: '',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                  ],
                  fieldLabel('Email'),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      hintText: 'you@example.com',
                    ),
                    validator: (v) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid email.',
                  ),
                  const SizedBox(height: 20),
                  fieldLabel('Password'),
                  TextFormField(
                    controller: password,
                    obscureText: hidePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      hintText: register ? 'At least 8 characters' : 'Password',
                      suffixIcon: IconButton(
                        tooltip: hidePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () =>
                            setState(() => hidePassword = !hidePassword),
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                        ? null
                        : 'Use 8–128 characters.',
                    onFieldSubmitted: (_) => authenticate(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: session.busy ? null : authenticate,
              child: Text(register ? 'Sign up' : 'Log in'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: session.busy
                  ? null
                  : () => setState(() {
                      register = !register;
                      form.currentState?.reset();
                    }),
              child: Text(
                register
                    ? 'Already have an account? Log in'
                    : 'Create an account',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> authenticate() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (await session.authenticate(
      email.text.trim(),
      password.text,
      register ? name.text.trim() : null,
    )) {
      password.clear();
    }
  }

  Widget lobbyView() => SingleChildScrollView(
    key: const ValueKey('lobby'),
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Study rooms', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          'Join with a code, or start a session.',
          style: TextStyle(color: muted, fontSize: 15),
        ),
        const SizedBox(height: 32),
        fieldLabel('Room code or invite link'),
        TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Enter code',
            prefixIcon: Icon(Icons.tag, size: 20),
          ),
          onSubmitted: (_) => joinCode(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: session.busy ? null : joinCode,
          child: const Text('Join room'),
        ),
        const SizedBox(height: 36),
        const Divider(),
        roomOption(
          Icons.add,
          'Create room',
          'Invite your group with a code.',
          'group',
        ),
        const Divider(),
        roomOption(
          Icons.people_outline,
          'Find a group',
          'Join an available public room.',
          'random',
        ),
        const Divider(),
        roomOption(
          Icons.person_outline,
          'Study solo',
          'Start a private session.',
          'solo',
        ),
        const Divider(),
      ],
    ),
  );

  Widget roomOption(
    IconData icon,
    String title,
    String subtitle,
    String mode,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    leading: Icon(icon, color: ink, size: 23),
    minLeadingWidth: 24,
    horizontalTitleGap: 16,
    title: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        subtitle,
        style: const TextStyle(color: muted, fontSize: 13, height: 1.4),
      ),
    ),
    trailing: const Icon(Icons.chevron_right, size: 20, color: muted),
    onTap: session.busy ? null : () => session.join(mode),
  );

  void joinCode() {
    final parsed = roomCodeFrom(code.text);
    if (parsed == null) {
      toast('Enter a valid 6-character code or invite link.');
      return;
    }
    session.join('join', code: parsed);
  }

  Widget roomView() {
    final room = session.room!;
    final solo = room['kind'] == 'solo';
    final kind = solo
        ? 'Solo session'
        : room['kind'] == 'random'
        ? 'Public room'
        : 'Private room';
    return DefaultTabController(
      key: ValueKey(room['code']),
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: session.busy ? null : () => session.leave(),
                  tooltip: 'Leave room',
                  icon: const Icon(Icons.arrow_back, size: 21),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          solo ? 'Solo session' : room['code'] as String,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          solo
                              ? 'Only you'
                              : '$kind · ${session.members.length} ${session.members.length == 1 ? 'person' : 'people'}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!solo)
                  PopupMenuButton<String>(
                    tooltip: 'Invite',
                    icon: const Icon(Icons.ios_share, size: 21),
                    onSelected: (value) async {
                      final invite = value == 'code'
                          ? room['code'] as String
                          : kIsWeb
                          ? Uri.base
                                .replace(
                                  queryParameters: {
                                    'code': room['code'] as String,
                                  },
                                  fragment: '',
                                )
                                .toString()
                          : 'chainlink://join?code=${room['code']}';
                      await Clipboard.setData(ClipboardData(text: invite));
                      toast(
                        value == 'code' ? 'Code copied.' : 'Invite copied.',
                      );
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'code',
                        child: Text('Copy room code'),
                      ),
                      PopupMenuItem(
                        value: 'link',
                        child: Text('Copy invite link'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (session.connectionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                session.connectionError!,
                style: const TextStyle(color: Color(0xFFA2342F), fontSize: 12),
              ),
            ),
          const TabBar(
            tabs: [
              Tab(text: 'Study'),
              Tab(text: 'Chat'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  key: const PageStorageKey('study'),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      focusSection(),
                      const SizedBox(height: 28),
                      const Divider(),
                      musicSection(),
                      const Divider(),
                      const SizedBox(height: 24),
                      membersSection(),
                    ],
                  ),
                ),
                chatView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String timeText(int seconds) {
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget focusSection() {
    final me = session.me;
    final isBreak = me?['break_start'] != null;
    var seconds = DateTime.now().difference(joinedAt).inSeconds;
    if (isBreak) {
      final now =
          serverClock
              .add(DateTime.now().difference(receivedClock))
              .millisecondsSinceEpoch /
          1000;
      final elapsed = math.max(0, now - (me!['break_start'] as num)).floor();
      final duration = me['break_seconds'] as int;
      seconds = duration == 0 ? elapsed : math.max(0, duration - elapsed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          isBreak ? 'Break' : 'Time in room',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: muted),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            timeText(seconds),
            style: const TextStyle(
              fontSize: 68,
              fontWeight: FontWeight.w400,
              letterSpacing: -2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: session.busy
              ? null
              : isBreak
              ? () => session.setBreak(active: false)
              : startBreak,
          child: Text(isBreak ? 'End break' : 'Take a break'),
        ),
        if (isBreak)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              me!['share_break'] == true
                  ? 'Visible to the group'
                  : 'Private break',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> startBreak() async {
    var useStopwatch = stopwatch;
    var minutes = breakMinutes;
    var share = shareBreak;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Take a break',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Countdown')),
                  ButtonSegment(value: true, label: Text('Stopwatch')),
                ],
                selected: {useStopwatch},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    update(() => useStopwatch = value.first),
              ),
              const SizedBox(height: 20),
              if (!useStopwatch)
                DropdownButtonFormField<int>(
                  initialValue: minutes,
                  decoration: const InputDecoration(labelText: 'Duration'),
                  items: [
                    for (final value in [5, 10, 15])
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value minutes'),
                      ),
                  ],
                  onChanged: (value) => update(() => minutes = value!),
                ),
              SwitchListTile.adaptive(
                activeTrackColor: accent,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                title: const Text(
                  'Share break status',
                  style: TextStyle(fontSize: 15),
                ),
                subtitle: const Text(
                  'Let the group know you’re away.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                value: share,
                onChanged: (value) => update(() => share = value),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start break'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted && session.room != null) {
      setState(() {
        stopwatch = useStopwatch;
        breakMinutes = minutes;
        shareBreak = share;
      });
      await session.setBreak(
        active: true,
        seconds: stopwatch ? 0 : minutes * 60,
        share: share,
      );
    }
  }

  Widget musicSection() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.headphones_outlined, size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lo-fi', style: sectionStyle),
                  SizedBox(height: 3),
                  Text(
                    'Quiet hours',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: musicBusy ? null : toggleMusic,
              tooltip: musicPlaying ? 'Pause music' : 'Play music',
              icon: Icon(
                musicPlaying ? Icons.pause : Icons.play_arrow,
                size: 26,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() => musicMuted = !musicMuted);
                updateMusicVolume();
              },
              tooltip: musicMuted ? 'Unmute music' : 'Mute music',
              icon: Icon(
                musicMuted
                    ? Icons.volume_off_outlined
                    : Icons.volume_down_outlined,
                size: 20,
              ),
            ),
            Expanded(
              child: Slider(
                value: musicVolume,
                label: '${(musicVolume * 100).round()}%',
                onChanged: (v) {
                  setState(() => musicVolume = v);
                  updateMusicVolume();
                },
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(musicVolume * 100).round()}%',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget membersSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('People', style: sectionStyle),
      const SizedBox(height: 12),
      for (final member in session.members)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: surface,
                foregroundColor: ink,
                child: Text(
                  (member['name'] as String).characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${member['name']}${member['id'] == session.user!['id'] ? ' (you)' : ''}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Text(
                member['break_start'] == null ? 'Studying' : 'On break',
                style: TextStyle(
                  fontSize: 12,
                  color: member['break_start'] == null ? muted : accent,
                ),
              ),
            ],
          ),
        ),
      if (session.members.length == 1 && session.room!['kind'] == 'random')
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Waiting for others to join.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
    ],
  );

  Widget chatView() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 12, 6),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Room chat',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            IconButton(
              onPressed: chatSettings,
              tooltip: 'Chat sound settings',
              icon: Icon(
                chatMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none,
                size: 20,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: session.messages.isEmpty
            ? const Center(
                child: Text(
                  'No messages yet.',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              )
            : ListView.builder(
                controller: chatScroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                itemCount: session.messages.length,
                itemBuilder: (context, index) {
                  final item =
                      session.messages[session.messages.length - 1 - index];
                  final own = item['user_id'] == session.user!['id'];
                  final sent = DateTime.fromMillisecondsSinceEpoch(
                    ((item['created'] as num) * 1000).round(),
                  ).toLocal();
                  return Align(
                    alignment: own
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: const BoxConstraints(maxWidth: 360),
                      decoration: BoxDecoration(
                        color: own ? surface : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            children: [
                              Text(
                                own ? 'You' : item['name'] as String,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${sent.hour.toString().padLeft(2, '0')}:${sent.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            item['body'] as String,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: message,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  counterText: '',
                ),
                onSubmitted: (_) => sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: session.busy ? null : sendMessage,
              tooltip: 'Send message',
              style: IconButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.arrow_upward, size: 20),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> chatSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chat notifications',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SwitchListTile.adaptive(
                activeTrackColor: accent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Mute sound'),
                value: chatMuted,
                onChanged: (value) {
                  setState(() => chatMuted = value);
                  update(() {});
                },
              ),
              const Text(
                'Volume',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              Slider(
                value: chatVolume,
                label: '${(chatVolume * 100).round()}%',
                onChanged: (value) {
                  setState(() => chatVolume = value);
                  update(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> sendMessage() async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    if (await session.send(text) && message.text.trim() == text) {
      message.clear();
    }
  }
}

Widget fieldLabel(String label) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    label,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
  ),
);
