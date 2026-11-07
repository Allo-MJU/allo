import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';

/// D의 species.sprite 경로로 에셋을 읽고 미제공 시 임시 아이콘을 표시한다.
class SpeciesArt extends StatelessWidget {
  const SpeciesArt({super.key, required this.species, this.size = 100});
  final Species species;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/${species.sprite}',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: species.nameKo,
        errorBuilder: (_, __, ___) => Icon(Icons.pets,
            size: size,
            semanticLabel: species.nameKo,
            color: switch (species.attribute) {
              Attribute.water => Colors.blue,
              Attribute.dark => Colors.deepPurple,
              Attribute.normal => Colors.teal,
            }),
      );
}
