#!/usr/bin/env python3
"""디자인 토큰 검사기 (docs/design-system.md 2절).

art/design/tokens.json 을 바꾼 뒤 한 번 돌린다. 표준 라이브러리만 쓴다.
  python3 scripts/check_design_tokens.py

1. 모든 별칭({color.ivory.100} 같은)이 실제 값으로 풀리는지
2. 글자·배경 조합이 WCAG 대비 기준을 넘는지 (본문 4.5:1, 큰 글자·UI 요소 3:1)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / "art" / "design" / "tokens.json"
ALIAS = re.compile(r"^\{([^}]+)\}$")

# (글자 또는 요소, 배경, 최소 대비, 왜)
PAIRS = [
    ("semantic.text.primary", "semantic.bg.canvas", 4.5, "본문"),
    ("semantic.text.primary", "semantic.bg.soft", 4.5, "본문, 옅은 녹색 면"),
    ("semantic.text.secondary", "semantic.bg.canvas", 4.5, "보조 글자"),
    ("semantic.text.secondary", "semantic.bg.soft", 4.5, "보조 글자, 옅은 녹색 면"),
    ("semantic.text.action", "semantic.bg.success", 4.5, "완료 면 글자"),
    ("semantic.text.error", "semantic.bg.error", 4.5, "오류 면 글자"),
    ("semantic.text.inverse", "semantic.action.primary", 4.5, "주 버튼 글자 (가이드 6.50:1)"),
    ("semantic.text.inverse", "semantic.action.primary-pressed", 4.5, "주 버튼 글자, 눌림"),
    ("semantic.text.on-yellow", "semantic.action.discovery", 4.5, "노란 버튼·라벨 글자 (가이드 12.46:1)"),
    ("semantic.text.on-yellow", "semantic.action.discovery-pressed", 4.5, "노란 버튼 글자, 눌림"),
    ("semantic.text.primary", "semantic.action.secondary-pressed", 4.5, "보조 버튼 글자, 눌림"),
    ("semantic.border.control", "semantic.bg.canvas", 3.0, "입력 테두리 (WCAG 1.4.11)"),
    ("semantic.border.focus", "semantic.bg.canvas", 3.0, "포커스 링"),
    ("semantic.progress.fill", "semantic.progress.track", 3.0, "진행바 채움과 트랙"),
    ("semantic.progress.fill", "semantic.bg.canvas", 3.0, "진행바 채움과 바탕"),
    ("semantic.car.text", "semantic.car.bg", 4.5, "Pleos 글자"),
    ("semantic.car.progress", "semantic.car.bg", 3.0, "Pleos 진행바"),
    ("semantic.car.accent", "semantic.car.bg", 3.0, "Pleos 강조"),
    ("semantic.tag.fg", "semantic.tag.bg", 4.5, "환경 태그"),
] + [
    (f"semantic.tier.{t}-fg", f"semantic.tier.{t}-bg", 4.5, f"등급 배지 {t}")
    for t in ("common", "rare", "epic", "special")
] + [
    # 도감 카드: 종 이름은 tint 배경 위에 text.primary
    ("semantic.text.primary", f"species.{s}.tint", 4.5, f"도감 카드 {s}")
    for s in ("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist",
              "ember_crab", "dewcap", "cloud_strider", "pebble_orbit", "breeze_wyrm", "dune_roller")
]

# 가이드가 명시한 대비. 값이 바뀌면 문서도 같이 고친다
GUIDE = [("color.white", "color.action-green", 6.50), ("color.ink", "color.shell-yellow", 12.46), ("color.white", "color.growth-green", 3.62)]


def lookup(tree, path):
    node = tree
    for key in path.split("."):
        node = node[key]
    return node


def resolve(tree, path, seen=()):
    if path in seen:
        raise ValueError(f"순환 별칭: {' -> '.join(seen + (path,))}")
    value = lookup(tree, path)["$value"]
    m = ALIAS.match(value) if isinstance(value, str) else None
    return resolve(tree, m.group(1), seen + (path,)) if m else value


def alias_targets(node):
    """모든 토큰 값(타이포 객체 안 포함)에 든 별칭 대상 경로"""
    if not isinstance(node, dict):
        return
    if "$value" in node:
        v = node["$value"]
        for s in (v.values() if isinstance(v, dict) else [v]):
            m = ALIAS.match(s) if isinstance(s, str) else None
            if m:
                yield m.group(1)
    for k, v in node.items():
        if not k.startswith("$"):
            yield from alias_targets(v)


def luminance(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def main():
    tree = json.loads(TOKENS.read_text(encoding="utf-8"))
    errors = []
    for target in alias_targets(tree):
        try:
            resolve(tree, target)
        except (KeyError, ValueError) as e:
            errors.append(f"{{{target}}}: 별칭을 풀 수 없음 ({e})")
    for fg, bg, minimum, why in PAIRS:
        try:
            ratio = contrast(resolve(tree, fg), resolve(tree, bg))
        except KeyError as e:
            errors.append(f"{fg} / {bg}: 토큰 없음 ({e})")
            continue
        mark = "ok  " if ratio >= minimum else "FAIL"
        print(f"{mark} {ratio:5.2f}:1 (>= {minimum}) {why}: {fg} on {bg}")
        if ratio < minimum:
            errors.append(f"{why}: {ratio:.2f}:1 < {minimum}:1")
    for fg, bg, stated in GUIDE:
        ratio = contrast(resolve(tree, fg), resolve(tree, bg))
        if abs(ratio - stated) > 0.01:
            errors.append(f"가이드 수치 불일치: {fg} on {bg} = {ratio:.2f}:1, 문서 {stated}:1")
    if errors:
        print("\n".join(["", "실패:"] + errors))
        sys.exit(1)
    print(f"\n대비 {len(PAIRS)}쌍 통과, 별칭 모두 풀림")


if __name__ == "__main__":
    main()
