#!/usr/bin/env python3
"""대사 뱅크 검증기 (docs/ai-dialogue-design.md 6절, docs/dialogue-style.md 1절).

빌드 전에 한 번 돌린다. 표준 라이브러리만 쓴다.
  python3 scripts/validate_dialogue.py                # data/dialogue.json 검사
  python3 scripts/validate_dialogue.py --strict       # reviewedBy 없는 항목도 실패로 (CI 용)
  python3 scripts/validate_dialogue.py path/to.json

종 id·영어 이름은 data/species.json 에서 읽는다. 종 키가 species.json 에 없으면 실패.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_CHARS = 50          # 폰 말풍선
MAX_CHARS_CAR = 45      # 차 음성 (car_*). 운전자가 듣는 말. 약 9초
MAX_CHARS_CAR_SUGGEST = 80  # 목적지 제안만 예외 (장소·거리가 들어간다)
MAX_SENTENCES = 3   # 50자 안의 짧은 문장. '비! 영어로 rain이야. 세어 볼래?' 패턴이 3문장
MIN_HANGUL_RATIO = 0.90

QUESTION_IDS = {"ask_name", "ask_origin", "ask_like", "ask_mood", "ask_window", "ask_eta", "ask_want", "say_bored", "say_bye"}
# 아이의 질문이 아닌 상황 대사 (폰) + 차 음성 (car_*)
SITUATION_IDS = {"hatch", "look_out", "look_out_done", "env_change", "care",
                 "car_egg_status", "car_hatch", "car_suggest", "car_suggest_none", "car_accept", "car_unknown"}
SITUATIONS = {"hatched", "incubating", "harsh", "rain", "tunnel", "highway", "coast", "city", "night", "none", "eta", "distance", "driving", "*",
              "idle", "not_yet", "first", "unvisited", "alt", "all_visited", "none_nearby", "exhausted", "ok",
              "route_active", "not_ready"}

# 길이 계산용 예시값. 플레이스홀더를 이 값으로 바꿔서 잰다
SAMPLES = {"{name}": "별부엉이", "{eta_min}": "15", "{progress}": "62", "{word_en}": "bridge", "{word_ko}": "다리",
           "{tier_word}": "중간", "{attr_word}": "물 속성", "{region_word}": "바다", "{place}": "을왕리해수욕장", "{km}": " 직선으로 약 65km예요."}
# 조사 플레이스홀더: {name:이/가} = 받침 있으면 앞, 없으면 뒤. 바로 앞에 같은 {name} 이 와야 한다
JOSA = re.compile(r"\{([a-z_]+):([^/{}]+)/([^/{}]+)\}")
ATTRIBUTES = {"normal", "water", "dark"}

# 창밖 사물 영어 단어 (영어 팩). 한글 비율 계산에서 제외한다. 늘어나면 여기에 추가.
ENGLISH_PACK = {"bridge", "mountain", "rain", "river", "sea", "tunnel", "fog", "light", "star", "highway", "building", "night", "sign", "cloud", "car", "tree", "moon"}

# 아이에게 되묻기 (개인정보). 물음표 문장에 이 단어가 있으면 실패
COUNTER_QUESTION = re.compile(r"(이름|어디 살|몇 살|학교|집이 어디|엄마|아빠|전화|주소)")
# 금칙어 (아동용, 보조 수단). 팀 검수로 계속 보강
# 한국어는 띄어쓰기 경계가 약해서 한 글자 금칙어는 오탐이 난다 ("피어났어"의 "피"). 조사가 붙은 꼴로 쓴다
FORBIDDEN = re.compile(r"(피가|피를|피투성|죽어|죽이|죽을|괴물|귀신|칼로|칼을|불태|때려|바보|멍청|사 줘|사면 |결제|비밀이야|말하지 마|나만 |혼자 두면|가지 마|없으면 안|쫓아와|널 보고 있|따라오고 있)")
# 운전 개입
DRIVING = re.compile(r"(앞을 봐|앞에 .*봐|피해|브레이크|핸들|운전자|빨리 달|더 밟)")
# 외모 평가 (아이에게)
APPEARANCE = re.compile(r"(생겼다|생겼네|귀엽게 생|뚱뚱|날씬|키가 작|키가 크|못생|예쁘|잘생)")
# 지어낸 장소: 슬롯에 장소 이름이 들어오는 질문은 없다 (ask_want 도 지역 태그뿐). 이름이 나오면 실패.
# 차량 앱 DestinationSuggester 후보 + 주요 도시. 늘어나면 추가
PLACES = re.compile(r"(강릉|속초|부산|서울|경포|을왕리|만리포|대천|해운대|협재|북한산|계룡산|속리산|설악산|지리산|한라산|수원|대전|대구|광주|제주|인천|울산|여수|통영|거제|판교)")
EMOJI = re.compile(r"[\U0001F300-\U0001FAFF☀-➿]")
URL = re.compile(r"https?://|www\.")
DIGIT = re.compile(r"\d")
PLACEHOLDER = re.compile(r"\{[a-z_]+\}")
HANGUL = re.compile(r"[가-힣]")


def load_species():
    data = json.loads((ROOT / "data" / "species.json").read_text(encoding="utf-8"))
    ids = {s["id"] for s in data["species"]}
    words = {w.lower() for s in data["species"] for w in s["nameEn"].split()}
    return ids, words


def sentences(text: str) -> int:
    parts = [p for p in re.split(r"(?<=[.!?…])\s+", text.strip()) if p]
    return len(parts)


def render_sample(line: str) -> str:
    out = JOSA.sub(lambda m: m.group(2), line)
    for k, v in SAMPLES.items():
        out = out.replace(k, v)
    return out


def check_line(key: str, line: str, placeholders: set, english_ok: set) -> list:
    errs = []
    q = key.split("|")[0]
    car = q.startswith("car_")
    limit = MAX_CHARS_CAR_SUGGEST if q == "car_suggest" else (MAX_CHARS_CAR if car else MAX_CHARS)
    for m in JOSA.finditer(line):
        if "{" + m.group(1) + "}" not in placeholders:
            errs.append(f"모르는 조사 플레이스홀더 {m.group(0)}")
        elif not line[:m.start()].endswith("{" + m.group(1) + "}"):
            errs.append(f"조사 플레이스홀더 {m.group(0)} 앞에 {{{m.group(1)}}} 이 없다")
    line_josa_free = JOSA.sub("", line)
    sample = render_sample(line)
    if len(sample) > limit:
        errs.append(f"길이 {len(sample)}자 > {limit} (예시값 대입)")
    max_sent = 4 if q == "car_suggest" else MAX_SENTENCES   # 제안은 지역·장소·거리·대안 안내가 들어가 가장 길다
    if sentences(sample) > max_sent:
        errs.append(f"문장 {sentences(sample)}개 > {max_sent}")
    if car:
        for sent in re.split(r"(?<=[.!?…])\s+", sample.strip()):
            if sent and not re.search(r"(요|다)[.!?]?$", sent.strip()):
                errs.append(f"차 음성은 존댓말: '{sent.strip()}'")
    line = line_josa_free
    if EMOJI.search(line):
        errs.append("이모지")
    if URL.search(line):
        errs.append("URL")
    if line.count("!") > 2:
        errs.append("느낌표 과다")

    # 플레이스홀더가 아닌 숫자는 지어낸 숫자로 본다
    stripped = PLACEHOLDER.sub("", line)
    for ph in PLACEHOLDER.findall(line):
        if ph not in placeholders:
            errs.append(f"모르는 플레이스홀더 {ph}")
    if DIGIT.search(stripped):
        errs.append("플레이스홀더 아닌 숫자")

    # 한글 비율 (영어 팩 단어·플레이스홀더 제외)
    body = stripped
    for w in re.findall(r"[A-Za-z]+", body):
        if w.lower() in english_ok:
            body = body.replace(w, "", 1)
        else:
            errs.append(f"영어 단어 '{w}' (영어 팩 아님)")
    letters = [c for c in body if c.isalpha()]
    if letters:
        ratio = sum(1 for c in letters if HANGUL.match(c)) / len(letters)
        if ratio < MIN_HANGUL_RATIO:
            errs.append(f"한글 비율 {ratio:.2f} < {MIN_HANGUL_RATIO}")

    for s in re.split(r"(?<=[.!?…])\s+", line):
        if s.strip().endswith("?") and COUNTER_QUESTION.search(s):
            errs.append(f"아이에게 되묻기: '{s.strip()}'")
    m = FORBIDDEN.search(line)
    if m:
        errs.append(f"금칙어 '{m.group(0)}'")
    m = DRIVING.search(line)
    if m:
        errs.append(f"운전 개입 '{m.group(0)}'")
    m = APPEARANCE.search(line)
    if m:
        errs.append(f"외모 평가 '{m.group(0)}'")
    m = PLACES.search(line)
    if m:
        errs.append(f"지어낸 장소 '{m.group(0)}' (장소는 슬롯에 없다)")
    return errs


def check_key(key: str, species_ids: set) -> list:
    parts = key.split("|")
    if len(parts) != 3:
        return [f"키 형식 아님 (질문ID|대상|상황): {key}"]
    q, target, situation = parts
    errs = []
    if q not in QUESTION_IDS and q not in SITUATION_IDS:
        errs.append(f"모르는 질문 ID {q}")
    if target != "*" and not (target.startswith("@") and target[1:] in ATTRIBUTES) and target not in species_ids:
        errs.append(f"모르는 대상 {target} (species.json 에 없음)")
    if situation not in SITUATIONS:
        errs.append(f"모르는 상황 {situation}")
    return errs


def main(argv):
    strict = "--strict" in argv
    paths = [a for a in argv if not a.startswith("--")]
    path = Path(paths[0]) if paths else ROOT / "data" / "dialogue.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    species_ids, species_words = load_species()
    english_ok = ENGLISH_PACK | species_words
    placeholders = set(data.get("placeholders", []))

    failures = 0
    lines_total = 0
    unreviewed = 0
    seen = set()
    for e in data["entries"]:
        key = e.get("key", "?")
        errs = check_key(key, species_ids)
        if key in seen:
            errs.append("중복 키")
        seen.add(key)
        if not e.get("lines"):
            errs.append("lines 비어 있음")
        if not e.get("reviewedBy"):
            unreviewed += 1
            if strict:
                errs.append("reviewedBy 없음")
        for err in errs:
            print(f"FAIL {key}: {err}")
            failures += 1
        for line in e.get("lines", []):
            lines_total += 1
            for err in check_line(key, line, placeholders, english_ok):
                print(f"FAIL {key}: {err} ← {line}")
                failures += 1

    covered = {k.split("|")[0] for k in seen}
    missing_q = (QUESTION_IDS | SITUATION_IDS) - covered
    print(f"\n{path.name}: 키 {len(seen)}개 · 문장 {lines_total}개 · 실패 {failures} · 미검수 {unreviewed}")
    if missing_q:
        print(f"주의: 대사 없는 질문 ID {sorted(missing_q)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
