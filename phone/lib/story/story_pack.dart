import 'dart:convert';

class StoryChoice {
  const StoryChoice(this.id, this.label, this.next);
  final String id, label, next;
  Map<String, dynamic> get snapshot => {'id': id, 'label': label};
}

class StoryNode {
  const StoryNode(this.id, this.line, this.variant, this.choices);
  final String id, line, variant;
  final List<StoryChoice> choices;
}

class StoryPack {
  const StoryPack(
      {required this.id,
      required this.version,
      required this.title,
      required this.environment,
      required this.invitation,
      required this.visual,
      required this.cardTitle,
      required this.cardText,
      required this.nodes});
  final String id, title, environment, invitation, visual, cardTitle, cardText;
  final int version;
  final Map<String, StoryNode> nodes;
  static List<StoryPack> decodeList(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    if (root['version'] != 1) throw const FormatException('Story version');
    final ids = <String>{};
    return (root['packs'] as List).map((p) {
      final nodes = <String, StoryNode>{};
      for (final n in p['nodes'] as List) {
        final id = n['id'] as String;
        final choices = (n['choices'] as List)
            .map((c) => StoryChoice(
                c['id'] as String, c['label'] as String, c['next'] as String))
            .toList();
        if (nodes.containsKey(id) ||
            choices.isEmpty ||
            choices.length > 2 ||
            choices.map((c) => c.id).toSet().length != choices.length ||
            (n['line'] as String).runes.length > 50) {
          throw const FormatException('Invalid node');
        }
        nodes[id] = StoryNode(id, n['line'] as String, n['variant'] as String,
            List.unmodifiable(choices));
      }
      for (final n in nodes.values) {
        for (final c in n.choices) {
          if (!nodes.containsKey(c.next) &&
              !{'@save', '@close'}.contains(c.next)) {
            throw const FormatException('Dangling choice');
          }
        }
      }
      if (!nodes.containsKey('intro') ||
          !nodes.containsKey('choose') ||
          !nodes.containsKey('saved') ||
          !ids.add(p['id'] as String)) {
        throw const FormatException('Invalid pack');
      }
      return StoryPack(
          id: p['id'] as String,
          version: p['version'] as int,
          title: p['title'] as String,
          environment: p['environment'] as String,
          invitation: p['invitation'] as String,
          visual: p['visual'] as String,
          cardTitle: p['cardTitle'] as String,
          cardText: p['cardText'] as String,
          nodes: Map.unmodifiable(nodes));
    }).toList(growable: false);
  }
}
