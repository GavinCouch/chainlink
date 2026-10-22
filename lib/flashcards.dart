import 'package:flutter/material.dart';

import 'study_session.dart';

class Flashcard {
  final String front, back;
  const Flashcard(this.front, this.back);
  Map<String, String> toJson() => {'front': front, 'back': back};
}

class FlashcardSet {
  final String? id;
  final String title, subject;
  final List<Flashcard> cards;
  const FlashcardSet({
    this.id,
    required this.title,
    required this.subject,
    required this.cards,
  });
  factory FlashcardSet.fromJson(Map<String, dynamic> json) => FlashcardSet(
    id: json['id'] as String,
    title: json['title'] as String,
    subject: json['subject'] as String,
    cards: (json['cards'] as List)
        .map((c) => Flashcard(c['front'] as String, c['back'] as String))
        .toList(),
  );
}

class FlashcardsPage extends StatefulWidget {
  final StudyApi api;
  const FlashcardsPage({super.key, required this.api});
  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  List<FlashcardSet> sets = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.request('/flashcards');
      if (!mounted) return;
      setState(
        () => sets = (result['sets'] as List)
            .map((s) => FlashcardSet.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([FlashcardSet? set]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FlashcardEditor(api: widget.api, initial: set),
      ),
    );
    if (changed == true && mounted) await load();
  }

  Future<void> delete(FlashcardSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete set?'),
        content: Text('Delete “${set.title}” and all its cards?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.api.request('/flashcards/delete', {'id': set.id});
      if (mounted) await load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flashcards')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your study sets',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: loading ? null : () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('New set'),
                  ),
                ],
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(error!, semanticsLabel: 'Error: $error'),
                    TextButton(
                      onPressed: loading ? null : load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: !loading && sets.isEmpty && error == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.style_outlined, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'No flashcards yet',
                              style: TextStyle(fontSize: 20),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create a set for a class or topic, then practice at your own pace.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: sets.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final set = sets[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          leading: const Icon(Icons.style_outlined),
                          title: Text(set.title),
                          subtitle: Text(
                            '${set.subject.isEmpty ? 'General' : set.subject} · ${set.cards.length} ${set.cards.length == 1 ? 'card' : 'cards'}',
                          ),
                          onTap: loading
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => FlashcardReview(set: set),
                                  ),
                                ),
                          trailing: PopupMenuButton<String>(
                            enabled: !loading,
                            tooltip: 'Set options',
                            onSelected: (action) =>
                                action == 'edit' ? edit(set) : delete(set),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit set'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete set'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CardFields {
  final TextEditingController front, back;
  _CardFields([Flashcard? card])
    : front = TextEditingController(text: card?.front),
      back = TextEditingController(text: card?.back);
  void dispose() {
    front.dispose();
    back.dispose();
  }
}

class FlashcardEditor extends StatefulWidget {
  final StudyApi api;
  final FlashcardSet? initial;
  const FlashcardEditor({super.key, required this.api, this.initial});
  @override
  State<FlashcardEditor> createState() => _FlashcardEditorState();
}

class _FlashcardEditorState extends State<FlashcardEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, subject;
  late final List<_CardFields> cards;
  bool saving = false, dirty = false;
  String? error;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.initial?.title);
    subject = TextEditingController(text: widget.initial?.subject);
    cards =
        widget.initial?.cards.map(_CardFields.new).toList() ?? [_CardFields()];
  }

  @override
  void dispose() {
    title.dispose();
    subject.dispose();
    for (final card in cards) {
      card.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.request('/flashcards/save', {
        if (widget.initial?.id != null) 'id': widget.initial!.id,
        'title': title.text.trim(),
        'subject': subject.text.trim(),
        'cards': cards
            .map(
              (c) =>
                  Flashcard(c.front.text.trim(), c.back.text.trim()).toJson(),
            )
            .toList(),
      });
      if (!mounted) return;
      setState(() {
        dirty = false;
        saving = false;
      });
      // Let PopScope register the saved state before completing the route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> confirmExit() async {
    if (saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) confirmExit();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New set' : 'Edit set'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: form,
            onChanged: () {
              if (!dirty) setState(() => dirty = true);
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: title,
                    enabled: !saving,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Set title'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a set title.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: subject,
                    enabled: !saving,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Subject (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < cards.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Card ${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove card ${i + 1}',
                          onPressed: saving || cards.length == 1
                              ? null
                              : () {
                                  final removed = cards[i];
                                  setState(() {
                                    cards.removeAt(i);
                                    dirty = true;
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => removed.dispose(),
                                  );
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    TextFormField(
                      key: ObjectKey(cards[i].front),
                      controller: cards[i].front,
                      enabled: !saving,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: 'Question'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a question.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ObjectKey(cards[i].back),
                      controller: cards[i].back,
                      enabled: !saving,
                      minLines: 2,
                      maxLines: 8,
                      maxLength: 1000,
                      decoration: const InputDecoration(labelText: 'Answer'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter an answer.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: saving || cards.length >= 50
                        ? null
                        : () => setState(() {
                            cards.add(_CardFields());
                            dirty = true;
                          }),
                    icon: const Icon(Icons.add),
                    label: Text('Add card (${cards.length}/50)'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(error!, semanticsLabel: 'Error: $error'),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving…' : 'Save set'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class FlashcardReview extends StatefulWidget {
  final FlashcardSet set;
  const FlashcardReview({super.key, required this.set});
  @override
  State<FlashcardReview> createState() => _FlashcardReviewState();
}

class _FlashcardReviewState extends State<FlashcardReview> {
  late List<Flashcard> queue;
  final missed = <Flashcard>[];
  int index = 0, known = 0;
  bool revealed = false;
  @override
  void initState() {
    super.initState();
    queue = List.of(widget.set.cards);
  }

  void restart({bool onlyMissed = false, bool shuffle = false}) => setState(() {
    queue = List.of(onlyMissed ? missed : widget.set.cards);
    if (shuffle) queue.shuffle();
    missed.clear();
    index = 0;
    known = 0;
    revealed = false;
  });

  void grade(bool correct) {
    if (!revealed || index >= queue.length) return;
    setState(() {
      if (correct) {
        known++;
      } else {
        missed.add(queue[index]);
      }
      index++;
      revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final complete = index >= queue.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.set.title),
        actions: [
          if (!complete)
            IconButton(
              tooltip: 'Restart shuffled',
              onPressed: () => restart(shuffle: true),
              icon: const Icon(Icons.shuffle),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: complete
                ? [
                    const Icon(Icons.check_circle_outline, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'Review complete',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$known of ${queue.length} remembered',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (missed.isNotEmpty)
                      FilledButton(
                        onPressed: () => restart(onlyMissed: true),
                        child: Text('Practice missed (${missed.length})'),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: restart,
                      child: const Text('Review all again'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to sets'),
                    ),
                  ]
                : [
                    Text(
                      'Card ${index + 1} of ${queue.length}',
                      semanticsLabel: 'Card ${index + 1} of ${queue.length}',
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: index / queue.length),
                    const SizedBox(height: 32),
                    const Text(
                      'Question',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      queue[index].front,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 32),
                    if (!revealed)
                      FilledButton(
                        onPressed: () => setState(() => revealed = true),
                        child: const Text('Show answer'),
                      )
                    else ...[
                      const Divider(),
                      const SizedBox(height: 20),
                      const Text(
                        'Answer',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: SelectableText(
                          queue[index].back,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: () => grade(true),
                        child: const Text('Got it'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => grade(false),
                        child: const Text('Practice again'),
                      ),
                    ],
                  ],
          ),
        ),
      ),
    );
  }
}
