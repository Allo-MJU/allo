// ALLO 캐릭터·알 시안 렌더러. 12종이 같은 몸(2.5등신)을 공유하고 파라미터만 다르다.
// 시안용이다. 최종 에셋은 art/export 의 PNG 로 교체한다.
(function () {
  const C = {
    cream: '#FFF0D8', sage: '#B9D0B9', sky: '#A9D4F1', lav: '#C9B9E8',
    peach: '#F5B99F', butter: '#F4D98B', brown: '#66584D',
  };

  function mix(hex, to, t) {
    const a = parseInt(hex.slice(1), 16), b = parseInt(to.slice(1), 16);
    const r = Math.round(((a >> 16) & 255) * (1 - t) + ((b >> 16) & 255) * t);
    const g = Math.round(((a >> 8) & 255) * (1 - t) + ((b >> 8) & 255) * t);
    const bl = Math.round((a & 255) * (1 - t) + (b & 255) * t);
    return '#' + ((1 << 24) | (r << 16) | (g << 8) | bl).toString(16).slice(1);
  }
  const lighten = (h, t) => mix(h, '#ffffff', t);
  const darken = (h, t) => mix(h, '#3a2f28', t);

  const SPECIES = {
    road_sprout: {
      ko: '길싹이', en: 'Road Sprout', attr: 'normal', tier: 1, rank: 'common',
      body: '#D7E8C4', accent: '#9CC58F', horn: 'bump', tail: 'leaf', wing: 'round',
      eyes: 'big', mouth: 'open', top: 'sprout', idle: 1.8, move: 'bounce',
      persona: '처음 만나는 친구. 뭐든 신기해함', say: '"신기해!"',
      cond: '어디서든', sig: '머리 새싹이 쑥 자라 꽃이 핌', base: '잎사귀 용',
    },
    bridge_hopper: {
      ko: '다리뛰기', en: 'Bridge Hopper', attr: 'normal', tier: 2, rank: 'rare',
      body: '#CFE0C6', accent: '#9FBF9A', horn: 'bump', tail: 'dash', wing: 'round',
      eyes: 'wink', mouth: 'grin', deco: ['arches', 'scarf'], idle: 1.4, move: 'hop',
      persona: '깡총깡총 활발. 다리·건너기를 좋아함', say: '"건너자!"',
      cond: '급조작 6 이하', sig: '꼬리로 아치를 그리고 건너뜀', base: '길잡이 용',
    },
    mountain_sprite: {
      ko: '산정령', en: 'Mountain Sprite', attr: 'normal', tier: 3, rank: 'epic',
      body: '#C9CCC7', accent: '#8FA08E', horn: 'rock', tail: 'crystal', wing: 'round',
      eyes: 'half', mouth: 'flat', blush: 0.12, deco: ['pebbles', 'plates'], pearl: true,
      idle: 4.0, move: 'breathe',
      persona: '차분하고 의젓한 형·누나', say: '"천천히 가자."',
      cond: '급조작 2 이하', sig: '작은 돌을 쌓고 고개를 끄덕임', base: '바위 용',
    },
    puddle_pip: {
      ko: '웅덩이삐약', en: 'Puddle Pip', attr: 'water', tier: 1, rank: 'common',
      body: '#D3EAF8', accent: '#8EC3E6', horn: 'bump', tail: 'drop', wing: 'round',
      eyes: 'big', mouth: 'o', top: 'drop', deco: ['puddle'], idle: 1.8, move: 'bounce',
      persona: '아기 새. 물웅덩이에서 첨벙', say: '"첨벙!"',
      cond: 'rain', sig: '웅덩이에서 첨벙, 물방울이 튀어 오름', base: '비의 용',
    },
    river_glider: {
      ko: '강미끄럼', en: 'River Glider', attr: 'water', tier: 2, rank: 'rare',
      body: '#BFE0F4', accent: '#7FB6DE', horn: 'drop', tail: 'fin', wing: 'round',
      eyes: 'droopy', mouth: 'smile', deco: ['waves'], idle: 3.6, move: 'sway',
      persona: '느긋하게 흘러가는 성격', say: '"스르르~"',
      cond: 'rain · 6 이하', sig: '꼬리 끝 물방울을 공중에 띄움', base: '여울 용',
    },
    tide_keeper: {
      ko: '물결지기', en: 'Tide Keeper', attr: 'water', tier: 3, rank: 'epic',
      body: '#A9D4F1', accent: '#6FAFD9', horn: 'bump', tail: 'pearl', wing: 'wave',
      eyes: 'round', mouth: 'smile', top: 'shell', deco: ['foam'], pearl: true, glassWing: true,
      idle: 2.8, move: 'rock',
      persona: '잔잔하고 든든한 바다 지킴이', say: '"지켜 줄게."',
      cond: 'rain · 2 이하', sig: '조개를 열어 진주를 보여 줌', base: '파도 용',
    },
    lamp_moth: {
      ko: '등불나방', en: 'Lamp Moth', attr: 'dark', tier: 1, rank: 'common',
      body: '#E1D8F4', accent: '#AE9AD9', horn: 'antenna', tail: 'bump', wing: 'moth',
      eyes: 'sparkle', mouth: 'open', idle: 3.2, move: 'float',
      persona: '불빛만 보면 신남', say: '"반짝!"',
      cond: 'night', sig: '더듬이 전구가 차례로 켜짐', base: '불빛 용',
    },
    tunnel_moth: {
      ko: '터널나방', en: 'Tunnel Moth', attr: 'dark', tier: 2, rank: 'rare',
      body: '#C9BEE8', accent: '#8F7CC7', horn: 'antenna', tail: 'lantern', wing: 'moth',
      eyes: 'focus', mouth: 'smile', deco: ['windows'], idle: 2.8, move: 'rock',
      persona: '어둠 속 길잡이. 든든함', say: '"따라와."',
      cond: 'tunnel · 6 이하', sig: '몸의 창이 앞에서 뒤로 켜짐', base: '불빛 용 + 길잡이 용',
    },
    star_owl: {
      ko: '별부엉이', en: 'Star Owl', attr: 'dark', tier: 3, rank: 'epic',
      body: '#8384BF', accent: '#5E5F9E', belly: '#F3E9DA', horn: 'ear', tail: 'star', wing: 'round',
      eyes: 'big', mouth: 'o', top: 'moon', deco: ['stars'], pearl: true, glassWing: true,
      idle: 2.8, move: 'turn',
      persona: '똑똑한 밤하늘 박사', say: '"후후, 그거 알아?"',
      cond: 'night · 2 이하', sig: '별자리 안에서 고개를 내밈', base: '별빛 용',
    },
    storm_lantern: {
      ko: '폭풍등', en: 'Storm Lantern', attr: 'water', tier: 3, rank: 'special',
      body: '#A9D4F1', accent: '#7C8FD6', horn: 'crown', tail: 'lantern', wing: 'round',
      eyes: 'brave', mouth: 'grin', deco: ['rain'], glassWing: true, aura: '#F4D98B',
      idle: 1.4, move: 'hop',
      persona: '씩씩한 등불. 비 오는 터널에서 태어남', say: '"번쩍!"',
      cond: 'rain + tunnel · 4 이하', sig: '랜턴이 번쩍, 빗방울이 빛으로', base: '비의 용 × 불빛 용',
    },
    highway_comet: {
      ko: '고속혜성', en: 'Highway Comet', attr: 'dark', tier: 3, rank: 'special',
      body: '#8A8CC8', accent: '#5F62A8', belly: '#F6EBDC', horn: 'bump', tail: 'comet', wing: 'round',
      eyes: 'happy', mouth: 'grin', top: 'star', deco: ['dashes'], glassWing: true, aura: '#C9B9E8',
      idle: 1.4, move: 'hop',
      persona: '빠른 게 좋은 신나는 혜성', say: '"슝!"',
      cond: 'highway + night · 2 이하', sig: '빛의 띠를 남기며 한 바퀴', base: '길잡이 용 × 별빛 용',
    },
    sea_mist: {
      ko: '바다안개', en: 'Sea Mist', attr: 'water', tier: 3, rank: 'special',
      body: '#F2F7FB', accent: '#A9D4F1', horn: 'bump', tail: 'mist', wing: 'cloud',
      eyes: 'half', mouth: 'smile', top: 'shellSmall', deco: ['mist'], aura: '#A9D4F1',
      idle: 3.2, move: 'float',
      persona: '몽글몽글 조용한 안개', say: '"살며시…"',
      cond: 'coast + rain · 4 이하', sig: '안개 뭉치 위에 올라 둥실', base: '구름 용 × 파도 용',
    },
  };

  const ORDER = ['road_sprout', 'bridge_hopper', 'mountain_sprite', 'puddle_pip', 'river_glider',
    'tide_keeper', 'lamp_moth', 'tunnel_moth', 'star_owl', 'storm_lantern', 'highway_comet', 'sea_mist'];
  const RANK = {
    common: { ko: '일반', color: '#A8D5A2' }, rare: { ko: '희귀', color: '#9CCBF0' },
    epic: { ko: '초희귀', color: '#F4D98B' }, special: { ko: '특별', color: '#F2A7C3' },
  };
  const ATTR = { normal: { ko: '땅·길', color: C.sage }, water: { ko: '물', color: C.sky }, dark: { ko: '밤', color: C.lav } };

  let uidSeq = 0;

  function grad(id, color, cx = '35%', cy = '30%') {
    return `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="75%">
      <stop offset="0" stop-color="${lighten(color, 0.45)}"/>
      <stop offset="0.55" stop-color="${color}"/>
      <stop offset="1" stop-color="${darken(color, 0.14)}"/></radialGradient>`;
  }

  // ---------- 부위 ----------
  function hornAt(type, x, y, rot, s, u) {
    const t = `translate(${x},${y}) rotate(${rot})`;
    const f = `url(#${u}a)`;
    switch (type) {
      case 'rock':
        return `<g transform="${t}"><rect x="-9" y="-12" width="18" height="18" rx="6" fill="url(#${u}r)"/>
          <rect x="-5" y="-10" width="6" height="4" rx="2" fill="#fff" opacity=".35"/></g>`;
      case 'drop':
        return `<g transform="${t}"><path d="M0,-14 C6,-5 8,0 8,3 A8,8 0 0 1 -8,3 C-8,0 -6,-5 0,-14Z" fill="${f}"/>
          <ellipse cx="-2.5" cy="-1" rx="2" ry="3" fill="#fff" opacity=".6"/></g>`;
      case 'crown':
        return `<g transform="${t}"><path d="M0,-15 C6,-6 8,-1 8,2 A8,8 0 0 1 -8,2 C-8,-1 -6,-6 0,-15Z" fill="${lighten(s.body, 0.25)}" opacity=".85" stroke="${s.accent}" stroke-width="1.5"/>
          <ellipse cx="-2.5" cy="-2" rx="2" ry="3" fill="#fff" opacity=".8"/></g>`;
      case 'antenna':
        return '';
      case 'ear':
        return `<g transform="${t}"><path d="M-9,4 Q-6,-16 4,-18 Q2,-8 9,4Z" fill="${f}"/></g>`;
      default:
        return `<g transform="${t}"><ellipse cx="0" cy="-3" rx="8" ry="10" fill="${f}"/>
          <ellipse cx="-2.5" cy="-7" rx="2.2" ry="3" fill="#fff" opacity=".45"/></g>`;
    }
  }

  function horns(s, u) {
    if (s.horn === 'antenna') {
      return [[-1, 82], [1, 118]].map(([d, x]) =>
        `<path d="M${x},46 Q${x + d * 6},26 ${x + d * 12},20" stroke="${s.accent}" stroke-width="4" fill="none" stroke-linecap="round"/>
         <circle cx="${x + d * 12}" cy="18" r="9" fill="${C.butter}" opacity=".35" class="glow"/>
         <circle cx="${x + d * 12}" cy="18" r="6" fill="url(#${u}y)"/>`).join('');
    }
    if (s.horn === 'ear') return hornAt('ear', 66, 52, -18, s, u) + hornAt('ear', 134, 52, 18, s, u);
    const mid = s.top ? '' : hornAt(s.horn, 100, 42, 0, s, u);
    return hornAt(s.horn, 76, 48, -22, s, u) + mid + hornAt(s.horn, 124, 48, 22, s, u);
  }

  function top(s, u) {
    switch (s.top) {
      case 'sprout':
        return `<path d="M100,42 Q99,30 101,22" stroke="#7FAF6E" stroke-width="3" fill="none" stroke-linecap="round"/>
          <path d="M101,24 Q88,14 84,22 Q92,30 101,24Z" fill="#9CC58F"/>
          <path d="M101,22 Q114,10 120,18 Q112,28 101,22Z" fill="#B5D6A3"/>`;
      case 'drop':
        return `<g transform="translate(100,30)"><path d="M0,-14 C7,-4 10,1 10,5 A10,10 0 0 1 -10,5 C-10,1 -7,-4 0,-14Z" fill="${C.sky}" opacity=".9"/>
          <ellipse cx="-3" cy="2" rx="2.5" ry="4" fill="#fff" opacity=".7"/></g>`;
      case 'shell':
        return `<g transform="translate(100,36)"><path d="M-14,4 Q0,-22 14,4 Q0,10 -14,4Z" fill="#FBE3D6" stroke="#EBB9A3" stroke-width="1.2"/>
          <path d="M0,6 L0,-12 M-6,5 L-5,-9 M6,5 L5,-9" stroke="#EBB9A3" stroke-width="1.2"/></g>`;
      case 'shellSmall':
        return `<g transform="translate(120,44) rotate(18)"><path d="M-8,3 Q0,-12 8,3 Q0,6 -8,3Z" fill="#FBE3D6" stroke="#EBB9A3"/></g>`;
      case 'moon':
        return `<g transform="translate(100,52)"><path d="M4,-9 A10,10 0 1 0 4,9 A7.5,7.5 0 1 1 4,-9Z" fill="url(#${u}y)"/></g>`;
      case 'star':
        return `<g transform="translate(100,30)">${starPath(0, 0, 11, `url(#${u}y)`)}<circle r="16" fill="${C.butter}" opacity=".2" class="glow"/></g>`;
      default: return '';
    }
  }

  function starPath(x, y, r, fill) {
    let d = '';
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI / 2 + (i * Math.PI) / 5, rr = i % 2 ? r * 0.5 : r;
      d += (i ? 'L' : 'M') + (x + rr * Math.cos(a)).toFixed(1) + ',' + (y + rr * Math.sin(a)).toFixed(1);
    }
    return `<path d="${d}Z" fill="${fill}" stroke="${fill}" stroke-width="${r * 0.25}" stroke-linejoin="round"/>`;
  }

  function wing(s, u, side) {
    const op = s.glassWing ? 0.62 : 1;
    const fill = `url(#${u}a)`;
    const m = side < 0 ? 'translate(200,0) scale(-1,1)' : '';
    let p;
    if (s.wing === 'wave') {
      p = `<path d="M136,112 Q156,78 182,86 Q176,94 180,100 Q170,100 174,110 Q164,108 166,118 Q152,114 146,126Z" fill="${fill}" opacity="${op}"/>`;
    } else if (s.wing === 'moth') {
      p = `<ellipse cx="160" cy="98" rx="20" ry="15" transform="rotate(-25 160 98)" fill="${fill}" opacity="${op}"/>
           <ellipse cx="156" cy="120" rx="13" ry="10" transform="rotate(20 156 120)" fill="${fill}" opacity="${op}"/>
           <circle cx="162" cy="96" r="5" fill="${C.butter}" opacity=".8"/>`;
    } else if (s.wing === 'cloud') {
      p = `<g fill="#fff" opacity=".95"><circle cx="152" cy="106" r="13"/><circle cx="166" cy="96" r="11"/><circle cx="170" cy="112" r="10"/></g>`;
    } else {
      p = `<path d="M138,114 Q154,84 176,90 Q170,100 174,108 Q160,108 150,124Z" fill="${fill}" opacity="${op}"/>
           <path d="M146,110 Q158,98 170,96" stroke="${darken(s.accent, 0.1)}" stroke-width="1.5" fill="none" opacity=".4"/>`;
    }
    return `<g transform="${m}">${p}</g>`;
  }

  function tail(s, u) {
    const base = `<path d="M124,162 Q174,182 180,136 Q176,124 164,130 Q162,154 128,144Z" fill="url(#${u}b)"/><path d="M134,158 Q166,166 172,140" stroke="#fff" stroke-width="2.5" fill="none" opacity=".35" stroke-linecap="round"/>`;
    const tip = {
      leaf: `<path d="M172,132 Q170,112 186,106 Q190,124 172,132Z" fill="#9CC58F"/><path d="M174,128 Q180,118 184,110" stroke="#7FAF6E" fill="none" stroke-width="1.2"/>`,
      dash: `<g stroke="#fff" stroke-width="3" stroke-linecap="round" opacity=".9"><path d="M140,154 L146,155"/><path d="M154,154 L160,152"/><path d="M166,146 L169,141"/></g>
             <ellipse cx="172" cy="130" rx="7" ry="8" fill="url(#${u}a)"/>`,
      crystal: `<g class="glow"><circle cx="174" cy="124" r="12" fill="#D9F0B5" opacity=".35"/></g>
             <path d="M174,110 L182,122 L174,134 L166,122Z" fill="#CBEAA8" stroke="#9CC58F" stroke-width="1.5"/><path d="M170,120 L174,112 L176,122Z" fill="#fff" opacity=".7"/>`,
      drop: `<g transform="translate(174,124)"><path d="M0,-14 C7,-4 9,1 9,4 A9,9 0 0 1 -9,4 C-9,1 -7,-4 0,-14Z" fill="${C.sky}"/><ellipse cx="-3" cy="2" rx="2" ry="3" fill="#fff" opacity=".7"/></g>`,
      fin: `<path d="M170,134 Q178,108 196,104 Q188,122 196,140 Q180,136 170,134Z" fill="url(#${u}a)" opacity=".9"/>`,
      pearl: `<path d="M166,134 Q176,114 192,116 Q184,128 190,142 Q176,138 166,134Z" fill="url(#${u}a)" opacity=".75"/>
              <circle cx="182" cy="124" r="11" fill="${C.butter}" opacity=".3" class="glow"/><circle cx="182" cy="124" r="6" fill="url(#${u}p)"/>`,
      bump: `<ellipse cx="172" cy="130" rx="7" ry="8" fill="url(#${u}a)"/>`,
      lantern: `<path d="M174,128 L176,118" stroke="${darken(s.accent, 0.2)}" stroke-width="2"/>
              <circle cx="178" cy="104" r="16" fill="${C.butter}" opacity=".35" class="glow"/>
              <rect x="169" y="96" width="18" height="20" rx="7" fill="url(#${u}y)" stroke="${darken(s.accent, 0.1)}" stroke-width="2"/>
              <rect x="172" y="92" width="12" height="5" rx="2" fill="${s.accent}"/>`,
      star: `<g class="glow"><circle cx="176" cy="126" r="11" fill="${C.butter}" opacity=".3"/></g>${starPath(176, 126, 8, `url(#${u}y)`)}`,
      comet: `<path d="M172,130 Q190,120 199,96 Q196,118 186,134 Q178,140 172,130Z" fill="url(#${u}c)" opacity=".9" class="glow"/>
              ${starPath(176, 128, 7, `url(#${u}y)`)}`,
      mist: `<g fill="#fff" opacity=".9"><circle cx="172" cy="132" r="9"/><circle cx="182" cy="124" r="7"/><circle cx="188" cy="114" r="5"/></g>`,
    }[s.tail] || '';
    return base + tip;
  }

  function deco(s, u, layer) {
    const d = s.deco || [];
    let out = '';
    if (layer === 'under') {
      if (d.includes('puddle')) out += `<ellipse cx="100" cy="184" rx="56" ry="9" fill="${C.sky}" opacity=".45"/><ellipse cx="80" cy="182" rx="12" ry="2" fill="#fff" opacity=".7"/>`;
      if (d.includes('mist')) out += `<g fill="#fff" opacity=".8" class="drift"><circle cx="34" cy="150" r="12"/><circle cx="48" cy="156" r="9"/><circle cx="160" cy="176" r="11"/><circle cx="176" cy="170" r="8"/></g>`;
      return out;
    }
    if (layer === 'body') {
      if (d.includes('arches')) out += `<g stroke="${s.accent}" stroke-width="3" fill="none" stroke-linecap="round" opacity=".9">
          <path d="M60,134 Q66,124 72,134"/><path d="M58,148 Q64,138 70,148"/><path d="M130,134 Q136,124 142,134"/></g>`;
      if (d.includes('plates')) out += `<g fill="url(#${u}r)"><rect x="56" y="122" width="14" height="10" rx="4"/><rect x="132" y="120" width="14" height="11" rx="4"/><rect x="134" y="138" width="10" height="8" rx="3"/></g>`;
      if (d.includes('waves')) out += `<g stroke="#fff" stroke-width="3.5" fill="none" stroke-linecap="round" opacity=".85">
          <path d="M58,130 q6,-5 12,0 t12,0"/><path d="M120,130 q6,-5 12,0 t12,0"/><path d="M56,146 q6,-5 12,0"/></g>`;
      if (d.includes('foam')) out += `<g fill="#fff" opacity=".85"><circle cx="62" cy="128" r="3"/><circle cx="68" cy="136" r="2"/><circle cx="138" cy="130" r="3"/><circle cx="134" cy="140" r="2"/></g>`;
      if (d.includes('windows')) out += [0, 1, 2].map(i => `<rect x="${128 + i * 2}" y="${120 + i * 11}" width="9" height="7" rx="2" fill="url(#${u}y)" class="win" style="animation-delay:${i * 0.4}s"/>
          <rect x="${62 - i * 2}" y="${120 + i * 11}" width="9" height="7" rx="2" fill="url(#${u}y)" class="win" style="animation-delay:${i * 0.4 + 0.2}s"/>`).join('');
      if (d.includes('stars')) out += [[62, 128, 4], [138, 126, 5], [134, 146, 3], [66, 146, 3]].map(([x, y, r]) => starPath(x, y, r, `url(#${u}y)`)).join('');
      if (d.includes('dashes')) out += `<g stroke="#fff" stroke-width="3" stroke-linecap="round" opacity=".85"><path d="M58,128 l7,0"/><path d="M58,140 l7,0"/><path d="M136,128 l7,0"/><path d="M136,140 l7,0"/></g>`;
      if (d.includes('rain')) out += `<g fill="#fff" opacity=".85"><path d="M62,126 c2,3 3,5 3,6 a3,3 0 0 1 -6,0 c0,-1 1,-3 3,-6z"/><path d="M138,130 c2,3 3,5 3,6 a3,3 0 0 1 -6,0 c0,-1 1,-3 3,-6z"/></g>`;
      return out;
    }
    if (layer === 'head') {
      if (d.includes('pebbles')) out += `<g fill="${darken(s.body, 0.12)}" opacity=".5"><ellipse cx="66" cy="70" rx="4" ry="3"/><ellipse cx="136" cy="74" rx="3" ry="2.5"/><ellipse cx="72" cy="60" rx="2.5" ry="2"/></g>`;
      if (d.includes('scarf')) out += `<path d="M66,116 Q100,128 134,116 L134,124 Q100,136 66,124Z" fill="${C.peach}"/>
          <path d="M120,122 Q128,138 122,146 Q132,140 132,124Z" fill="${darken(C.peach, 0.08)}"/>
          <g stroke="#fff" stroke-width="1.5" opacity=".6"><path d="M80,122 l4,3"/><path d="M96,125 l4,1"/><path d="M112,124 l4,-1"/></g>`;
      return out;
    }
    if (layer === 'fx') {
      if (s.rank === 'epic' || s.rank === 'special') {
        out += `<g class="twinkle">${starPath(40, 62, 4, C.butter)}${starPath(166, 52, 3, '#fff')}${starPath(30, 120, 2.5, C.butter)}</g>`;
      }
      if (d.includes('mist')) out += `<g fill="#fff" opacity=".75" class="drift"><circle cx="40" cy="80" r="7"/><circle cx="50" cy="84" r="5"/></g>`;
    }
    return out;
  }

  // ---------- 얼굴 ----------
  function eye(x, type, dir) {
    const B = C.brown;
    const dx = dir || 0;
    const dot = (ox, oy, r = 1.8) => `<circle cx="${x + dx + ox}" cy="${88 + oy}" r="${r}" fill="#fff"/>`;
    switch (type) {
      case 'big': return `<ellipse cx="${x + dx}" cy="88" rx="7.5" ry="9" fill="${B}"/>${dot(-2.5, -3.5, 2.8)}${dot(2.5, 3, 1.3)}`;
      case 'sparkle': return `<ellipse cx="${x + dx}" cy="88" rx="6" ry="7.5" fill="${B}"/>${dot(-2, -3, 2.2)}${dot(2.2, 2, 1.3)}`;
      case 'half': return `<ellipse cx="${x + dx}" cy="90" rx="5.5" ry="4" fill="${B}"/><path d="M${x - 7},87 L${x + 7},87" stroke="${B}" stroke-width="2.5" stroke-linecap="round"/>${dot(-1.5, 1, 1.2)}`;
      case 'droopy': return `<ellipse cx="${x + dx}" cy="89" rx="5" ry="6" fill="${B}"/>${dot(-1.5, -2)}
          <path d="M${x - 7},${x < 100 ? 82 : 80} L${x + 7},${x < 100 ? 80 : 82}" stroke="${B}" stroke-width="2" stroke-linecap="round" opacity=".7"/>`;
      case 'focus': return `<ellipse cx="${x + dx}" cy="89" rx="5" ry="6.5" fill="${B}"/>${dot(-1.5, -2.5)}
          <path d="M${x - 6},79 L${x + 6},79" stroke="${B}" stroke-width="2.2" stroke-linecap="round"/>`;
      case 'brave': return `<ellipse cx="${x + dx}" cy="89" rx="5.5" ry="7" fill="${B}"/>${dot(-1.5, -2.5, 2)}
          <path d="M${x - 7},${x < 100 ? 80 : 77} L${x + 7},${x < 100 ? 77 : 80}" stroke="${B}" stroke-width="2.6" stroke-linecap="round"/>`;
      case 'happy': return `<path d="M${x - 6},91 Q${x},82 ${x + 6},91" stroke="${B}" stroke-width="3" fill="none" stroke-linecap="round"/>`;
      case 'closed': return `<path d="M${x - 6},88 Q${x},94 ${x + 6},88" stroke="${B}" stroke-width="3" fill="none" stroke-linecap="round"/>`;
      case 'surprise': return `<ellipse cx="${x}" cy="88" rx="7" ry="8.5" fill="#fff" stroke="${B}" stroke-width="2"/><circle cx="${x}" cy="88" r="4" fill="${B}"/>`;
      default: return `<ellipse cx="${x + dx}" cy="88" rx="7" ry="8.5" fill="${B}"/>${dot(-2.3, -3.2, 2.6)}${dot(2.3, 2.8, 1.2)}`;
    }
  }

  function mouth(type) {
    const B = C.brown;
    switch (type) {
      case 'open': return `<path d="M93,103 Q100,113 107,103Z" fill="${B}"/><path d="M96,108 Q100,111 104,108" fill="${C.peach}"/>`;
      case 'grin': return `<path d="M90,102 Q100,116 110,102Z" fill="${B}"/><path d="M94,108 Q100,113 106,108" fill="${C.peach}"/>`;
      case 'flat': return `<path d="M95,105 L105,105" stroke="${B}" stroke-width="2.5" stroke-linecap="round"/>`;
      case 'o': return `<ellipse cx="100" cy="105" rx="3.5" ry="4" fill="${B}"/>`;
      case 'big-o': return `<ellipse cx="100" cy="106" rx="5" ry="6" fill="${B}"/>`;
      case 'yawn': return `<ellipse cx="100" cy="106" rx="4" ry="5" fill="${B}" opacity=".85"/>`;
      default: return `<path d="M92,102 Q96,107 100,102 Q104,107 108,102" stroke="${B}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
    }
  }

  const EXPR = {
    happy: { eyes: 'happy', mouth: 'grin', blush: 0.85, fx: 'hearts' },
    sleepy: { eyes: 'closed', mouth: 'yawn', fx: 'zzz' },
    look: { dir: 3.5, fx: 'sparkle' },
    surprise: { eyes: 'surprise', mouth: 'big-o', fx: 'alert' },
    signature: { eyes: 'sparkle', mouth: 'grin', blush: 0.75, fx: 'sparkle' },
  };

  function exprFx(kind) {
    if (kind === 'hearts') return `<g fill="${C.peach}"><path d="M40,60 c-4,-6 -12,-2 -8,4 l8,8 l8,-8 c4,-6 -4,-10 -8,-4z"/><path d="M162,48 c-3,-4 -8,-1 -6,3 l6,6 l6,-6 c2,-4 -3,-7 -6,-3z" opacity=".8"/></g>`;
    if (kind === 'zzz') return `<g fill="${C.brown}" font-family="sans-serif" font-weight="700" opacity=".55"><text x="150" y="50" font-size="16">z</text><text x="164" y="36" font-size="12">z</text></g>`;
    if (kind === 'alert') return `<g stroke="${C.butter}" stroke-width="4" stroke-linecap="round"><path d="M44,44 l6,10"/><path d="M36,62 l10,4"/><path d="M58,36 l2,11"/></g>`;
    if (kind === 'sparkle') return `<g>${starPath(170, 70, 6, C.butter)}</g>`;
    return '';
  }

  // ---------- 조립 ----------
  function renderSpecies(id, opt = {}) {
    const s0 = SPECIES[id];
    const e = opt.expr ? EXPR[opt.expr] || {} : {};
    const s = Object.assign({}, s0);
    const u = 'g' + (++uidSeq) + '_';
    const belly = s.belly || C.cream;
    const defs = `<defs>${grad(u + 'b', s.body)}${grad(u + 'a', s.accent)}${grad(u + 'h', s.body, '38%', '28%')}
      ${grad(u + 'w', belly, '40%', '30%')}${grad(u + 'r', '#B7BDB2')}${grad(u + 'y', C.butter, '40%', '35%')}
      <radialGradient id="${u}p" cx="35%" cy="30%"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#F3E3C8"/></radialGradient>
      <linearGradient id="${u}c" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="${C.butter}"/><stop offset="1" stop-color="${C.lav}" stop-opacity="0"/></linearGradient>
      <linearGradient id="${u}sheen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".28"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
      </defs>`;
    const blush = e.blush != null ? e.blush : (s.blush != null ? s.blush : 0.55);
    const eyesT = e.eyes || s.eyes, mouthT = e.mouth || s.mouth, dir = e.dir || 0;
    const aura = s.aura ? `<circle cx="100" cy="112" r="88" fill="none" stroke="${s.aura}" stroke-width="3" opacity=".5" stroke-dasharray="2 9" stroke-linecap="round" class="spin"/>
       <circle cx="100" cy="112" r="80" fill="${s.aura}" opacity=".12"/>` : '';
    const sheen = s.pearl ? `<ellipse cx="100" cy="84" rx="50" ry="44" fill="url(#${u}sheen)"/><ellipse cx="100" cy="138" rx="46" ry="40" fill="url(#${u}sheen)"/>` : '';
    const svg = `<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg" class="allo-char" data-id="${id}">${defs}
      ${aura}
      <ellipse cx="100" cy="186" rx="44" ry="7" fill="${C.brown}" opacity=".13"/>
      ${deco(s, u, 'under')}
      <g class="char-body">
        ${tail(s, u)}
        ${wing(s, u, 1)}${wing(s, u, -1)}
        <ellipse cx="100" cy="138" rx="46" ry="40" fill="url(#${u}b)"/>
        <ellipse cx="100" cy="148" rx="29" ry="25" fill="url(#${u}w)"/>
        ${deco(s, u, 'body')}
        <ellipse cx="80" cy="177" rx="14" ry="8.5" fill="url(#${u}b)"/><ellipse cx="120" cy="177" rx="14" ry="8.5" fill="url(#${u}b)"/>
        <ellipse cx="80" cy="179" rx="7" ry="3.5" fill="${belly}" opacity=".8"/><ellipse cx="120" cy="179" rx="7" ry="3.5" fill="${belly}" opacity=".8"/>
        <ellipse cx="70" cy="142" rx="9" ry="12" transform="rotate(-22 70 142)" fill="url(#${u}b)"/>
        <ellipse cx="130" cy="142" rx="9" ry="12" transform="rotate(22 130 142)" fill="url(#${u}b)"/>
        <g class="char-head">
          ${horns(s, u)}
          <ellipse cx="100" cy="84" rx="50" ry="44" fill="url(#${u}h)"/>
          <ellipse cx="100" cy="98" rx="30" ry="20" fill="${belly}" opacity=".55"/>
          <ellipse cx="80" cy="62" rx="13" ry="7" fill="#fff" opacity=".35" transform="rotate(-20 80 62)"/>
          ${top(s, u)}
          ${deco(s, u, 'head')}
          <ellipse cx="70" cy="101" rx="9" ry="5.5" fill="${C.peach}" opacity="${blush}"/>
          <ellipse cx="130" cy="101" rx="9" ry="5.5" fill="${C.peach}" opacity="${blush}"/>
          <g class="eyes">${eye(82, eyesT, dir)}${eye(118, eyesT === 'wink' ? 'happy' : eyesT, dir)}</g>
          ${mouth(mouthT)}
        </g>
        ${sheen}
      </g>
      ${deco(s, u, 'fx')}
      ${exprFx(e.fx)}
    </svg>`;
    return svg;
  }

  // ---------- 알 ----------
  const EGG_PATH = 'M100,26 C141,26 164,90 164,130 C164,168 136,188 100,188 C64,188 36,168 36,130 C36,90 59,26 100,26Z';
  const TAGS = {
    rain: { ko: '비', word: 'rain' }, night: { ko: '밤', word: 'night' }, tunnel: { ko: '터널', word: 'tunnel' },
    highway: { ko: '고속도로', word: 'highway' }, coast: { ko: '바다', word: 'coast' },
    mountain: { ko: '산', word: 'mountain' }, city: { ko: '도심', word: 'city' },
  };

  function pattern(tag) {
    const drop = (x, y, s = 1) => `<path transform="translate(${x},${y}) scale(${s})" d="M0,-9 C5,-2 6,1 6,3 A6,6 0 0 1 -6,3 C-6,1 -5,-2 0,-9Z"/>`;
    switch (tag) {
      case 'rain': return `<g fill="#7FB6DE" opacity=".8">${drop(76, 70)}${drop(122, 96, 1.2)}${drop(88, 138, .9)}${drop(136, 150)}${drop(62, 112, .8)}</g>`;
      case 'night': return `<g fill="${C.butter}">${starPath(70, 80, 6, C.butter)}${starPath(130, 126, 5, C.butter)}${starPath(84, 156, 4, C.butter)}
          <path d="M128,62 A14,14 0 1 0 128,90 A10,10 0 1 1 128,62Z"/></g>`;
      case 'tunnel': return `<path d="M44,150 Q100,96 156,150" stroke="#8F7CC7" stroke-width="5" fill="none" opacity=".5"/>
          <g fill="${C.butter}">${[0, 1, 2, 3, 4].map(i => `<circle cx="${60 + i * 20}" cy="${150 - [0, 26, 36, 26, 0][i] - 6}" r="4"/>`).join('')}</g>`;
      case 'highway': return `<path d="M30,132 Q100,104 170,124 L170,146 Q100,126 30,154Z" fill="#9C9FB0" opacity=".55"/>
          <path d="M34,143 Q100,116 168,135" stroke="#fff" stroke-width="3.5" stroke-dasharray="10 9" fill="none"/>`;
      case 'coast': return `<path d="M30,150 q14,-10 28,0 t28,0 t28,0 t28,0 t28,0 L170,190 L30,190Z" fill="#6FAFD9" opacity=".55"/>
          <g transform="translate(128,92)"><path d="M-10,3 Q0,-14 10,3 Q0,7 -10,3Z" fill="#FBE3D6" stroke="#EBB9A3"/></g>`;
      case 'mountain': return `<path d="M30,160 L74,100 L96,128 L124,86 L170,160Z" fill="#9CC58F" opacity=".7"/>
          <path d="M124,86 L134,100 L126,98 L118,104Z" fill="#fff" opacity=".9"/>`;
      case 'city': return `<g fill="#AE9AD9" opacity=".65"><rect x="56" y="118" width="22" height="60" rx="3"/><rect x="84" y="98" width="26" height="80" rx="3"/><rect x="116" y="126" width="22" height="52" rx="3"/></g>
          <g fill="${C.butter}">${[[61, 126], [69, 140], [90, 108], [100, 122], [90, 136], [121, 134], [129, 148]].map(([x, y]) => `<rect x="${x}" y="${y}" width="5" height="6" rx="1"/>`).join('')}</g>`;
    }
    return '';
  }

  function renderEgg(opt = {}) {
    const size = opt.size || 'mid', stage = opt.stage || 1, tags = opt.tags || [];
    const k = { small: 0.78, mid: 0.9, large: 1 }[size];
    const u = 'e' + (++uidSeq) + '_';
    const crack = stage >= 3 ? `<path d="M70,96 L82,108 L76,118 L92,128 L86,138" stroke="${C.brown}" stroke-width="2.5" fill="none" stroke-linejoin="round" opacity=".55"/>
        <path d="M132,84 L124,98 L134,104" stroke="${C.brown}" stroke-width="2" fill="none" opacity=".45"/>` : '';
    const glow = stage >= 2 ? `<ellipse cx="100" cy="112" rx="${stage === 3 ? 92 : 80}" ry="${stage === 3 ? 96 : 84}" fill="url(#${u}gl)"/>` : '';
    const pats = tags.map(t => `<g opacity="${stage === 1 ? 0.45 : stage === 2 ? 0.75 : 1}">${pattern(t)}</g>`).join('');
    return `<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg" class="allo-egg">
      <defs>
        <radialGradient id="${u}f" cx="36%" cy="28%" r="80%"><stop offset="0" stop-color="#FFFDF8"/><stop offset=".6" stop-color="${C.cream}"/><stop offset="1" stop-color="#EBD7B8"/></radialGradient>
        <radialGradient id="${u}gl"><stop offset=".55" stop-color="${C.butter}" stop-opacity=".45"/><stop offset="1" stop-color="${C.butter}" stop-opacity="0"/></radialGradient>
        <clipPath id="${u}c"><path d="${EGG_PATH}"/></clipPath>
      </defs>
      <g transform="translate(100,188) scale(${k}) translate(-100,-188)">
        ${glow}
        <ellipse cx="100" cy="190" rx="52" ry="7" fill="${C.brown}" opacity=".13"/>
        <path d="${EGG_PATH}" fill="url(#${u}f)"/>
        <g clip-path="url(#${u}c)">${pats}</g>
        ${crack}
        <ellipse cx="76" cy="66" rx="12" ry="20" transform="rotate(20 76 66)" fill="#fff" opacity="${stage === 1 ? 0.35 : 0.6}"/>
      </g></svg>`;
  }

  // 희소도 배지: 색 + 모양(별 개수·왕관) + 글자. 색만으로 등급을 구분하지 않는다 (WCAG 1.4.1).
  const RANK_MARK = { common: 1, rare: 2, epic: 3, special: 'crown' };
  function rankMark(rank, size = 12) {
    const m = RANK_MARK[rank];
    if (m === 'crown') return `<svg width="${size * 1.4}" height="${size}" viewBox="0 0 14 10"><path d="M1,9 L1.5,3 L4.5,5.5 L7,1 L9.5,5.5 L12.5,3 L13,9Z" fill="${C.brown}" stroke="${C.brown}" stroke-width="1" stroke-linejoin="round"/></svg>`;
    return `<svg width="${size * m}" height="${size}" viewBox="0 0 ${10 * m} 10">${Array.from({ length: m }, (_, i) => starPath(5 + i * 10, 5.3, 4.3, C.brown)).join('')}</svg>`;
  }
  function badge(rank, opt = {}) {
    const r = RANK[rank];
    return `<span class="badge" style="background:${r.color}">${rankMark(rank, opt.size || 11)}<b>${r.ko}</b></span>`;
  }

  window.ALLO = { C, SPECIES, ORDER, RANK, ATTR, TAGS, renderSpecies, renderEgg, starPath, rankMark, badge };
})();
