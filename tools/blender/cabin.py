"""뒷좌석 아이 시점의 차 내부를 만든다. 물체를 잘게 나눠 각각 이름을 붙인다.

실행:
  blender -b -P tools/blender/cabin.py -- --out unity/allo_explore/Assets/Models/Cabin.glb \
      --preview docs/work-results/explore/
  blender -b -P tools/blender/cabin.py -- --fbx unity/allo_explore/Assets/Models/Cabin.fbx
  blender -b -P tools/blender/cabin.py -- --check     (이름 검사만)

좌표는 kit.py 머리말 참고 (원점: 뒷좌석 가운데 바닥, -Y 가 앞).
캐릭터가 올라설 수 있는 면은 Walk_* 판으로 따로 둔다 (Unity 에서 렌더는 끄고 위치만 쓴다).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kit  # noqa: E402
import palette as P  # noqa: E402

# 실내 치수 (소형 SUV 정도)
W = 1.46          # 실내 폭
HALF = W / 2
ROOF = 1.24       # 바닥에서 천장까지
BELT = 0.66       # 창 아래 선
FRONT = -1.95     # 대시보드 앞 끝
BACK = 0.78       # 뒷유리 아래
B_PILLAR = -0.66  # 앞·뒤 문 사이 기둥

REQUIRED = [
    "Shell", "Seat_FL", "Seat_FR", "Headrest_FL", "Headrest_FR", "RearSeat",
    "Armrest", "Dashboard", "Wheel", "Mirror", "MirrorCharm", "DoorPanel_L",
    "DoorPanel_R", "DoorPanel_RL", "DoorPanel_RR", "Glass_Front", "Glass_L",
    "Glass_R", "Glass_Back", "Cushion", "Plush", "Bottle", "DomeLight",
    "RearShelf",
]
WALKS = [
    "Walk_RearSeat_L", "Walk_RearSeat_R", "Walk_Armrest", "Walk_RearShelf", "Walk_Dashboard",
    "Walk_DoorSill_L", "Walk_DoorSill_R",
]


def shell():
    """바닥·천장·기둥·문 아래판을 합친 몸체. 창 자리는 비운다."""
    parts = []
    b = kit.rounded_box
    parts.append(b("Floor", (W, BACK - FRONT, 0.04), (0, (BACK + FRONT) / 2, -0.02),
                   P.FLOOR, bevel=0.01))
    parts.append(b("Headliner", (W + 0.06, BACK - FRONT + 0.1, 0.05),
                   (0, (BACK + FRONT) / 2 + 0.05, ROOF + 0.025), P.HEADLINER, bevel=0.03))
    for sx in (-1, 1):
        x = sx * (HALF + 0.03)
        xp = sx * (HALF + 0.005)  # 기둥은 창 안쪽 면에 붙인다
        # 문 아래 벽 (창 아래)
        parts.append(b(f"LowerWall_{sx}", (0.06, BACK - FRONT, BELT),
                       (x, (BACK + FRONT) / 2, BELT / 2), P.DOOR, bevel=0.02))
        # 기둥: A(앞유리 옆), B(앞·뒤 문 사이), C(뒷문 뒤)
        parts.append(b(f"PillarA_{sx}", (0.07, 0.09, ROOF - BELT),
                       (xp, FRONT + 0.08, (ROOF + BELT) / 2), P.PILLAR, bevel=0.025,
                       rotation=(-28, 0, 0)))
        parts.append(b(f"PillarB_{sx}", (0.07, 0.12, ROOF - BELT),
                       (xp, B_PILLAR, (ROOF + BELT) / 2), P.PILLAR, bevel=0.03))
        parts.append(b(f"PillarC_{sx}", (0.07, 0.3, ROOF - BELT),
                       (xp, BACK - 0.08, (ROOF + BELT) / 2), P.PILLAR, bevel=0.04))
        # 창 위 지붕 레일
        parts.append(b(f"RoofRail_{sx}", (0.08, BACK - FRONT, 0.07),
                       (x - sx * 0.01, (BACK + FRONT) / 2, ROOF - 0.03), P.TRIM, bevel=0.03))
        # 손잡이 (창 위)
        kit.torus(f"GrabHandle_{sx}", 0.06, 0.012, (sx * (HALF - 0.04), 0.0, ROOF - 0.1),
                  P.TRIM, rotation=(0, 90, 0))
    # 뒤쪽 벽 (뒷유리 아래)
    parts.append(b("BackWall", (W, 0.06, BELT + 0.05), (0, BACK + 0.03, (BELT + 0.05) / 2),
                   P.DOOR, bevel=0.02))
    # 앞쪽 벽 (대시보드 아래)
    parts.append(b("Firewall", (W, 0.06, 0.75), (0, FRONT - 0.03, 0.375), P.DASH,
                   bevel=0.02))
    for o in parts[1:]:
        kit.parent(o, parts[0])
    parts[0].name = "Shell"
    return parts[0]


def glass():
    a = 0.22
    kit.plane("Glass_Front", (W - 0.1, 0.72), (0, FRONT + 0.32, 1.08), P.GLASS,
              rotation=(62, 0, 0), alpha=a)
    kit.plane("Glass_Back", (W - 0.2, 0.5), (0, BACK + 0.08, 0.95), P.GLASS,
              rotation=(-55, 0, 0), alpha=a)
    for name, sx in (("Glass_L", 1), ("Glass_R", -1)):
        kit.plane(name, (BACK - FRONT - 0.3, ROOF - BELT - 0.06),
                  (sx * (HALF + 0.035), (BACK + FRONT) / 2 + 0.05, (ROOF + BELT) / 2),
                  P.GLASS, rotation=(90, 0, 90), alpha=a)


def front_seat(side, sx):
    x = sx * 0.36
    b = kit.rounded_box
    base = b(f"Seat_{side}", (0.5, 0.5, 0.14), (x, -1.02, 0.36), P.SEAT, bevel=0.05)
    back = b(f"SeatBack_{side}", (0.48, 0.13, 0.6), (x, -0.76, 0.72), P.SEAT,
             bevel=0.06, rotation=(14, 0, 0))
    kit.parent(back, base)
    # 등받이 뒤 주머니와 박음질 띠 (아이 쪽에서 보이는 면)
    pocket = b(f"SeatPocket_{side}", (0.36, 0.02, 0.24), (x, -0.68, 0.6), P.SEAT_DARK,
               bevel=0.015, rotation=(14, 0, 0))
    kit.parent(pocket, base)
    for k, dx in enumerate((-0.12, 0.12)):
        seam = b(f"SeatSeam_{side}{k}", (0.012, 0.01, 0.56), (x + dx, -0.685, 0.78),
                 P.SEAM, bevel=0.004, rotation=(14, 0, 0))
        kit.parent(seam, base)
    # 등받이·방석 양옆의 볼록한 지지대 (스포츠 시트처럼 몸을 감싸는 부분)
    for k, dx in enumerate((-0.21, 0.21)):
        bol = b(f"SeatBolster_{side}{k}", (0.08, 0.15, 0.5), (x + dx, -0.74, 0.72), P.SEAT_DARK,
                bevel=0.035, rotation=(14, 0, 0))
        kit.parent(bol, base)
        cb = b(f"CushionBolster_{side}{k}", (0.08, 0.46, 0.08), (x + dx, -1.02, 0.45),
               P.SEAT_DARK, bevel=0.03)
        kit.parent(cb, base)
    head = b(f"Headrest_{side}", (0.25, 0.1, 0.15), (x, -0.67, 1.13), P.SEAT,
             bevel=0.045, rotation=(10, 0, 0))
    for k, dx in enumerate((-0.06, 0.06)):
        post = kit.cylinder(f"HeadrestPost_{side}{k}", 0.008, 0.1, (x + dx, -0.7, 1.03),
                            P.STEEL)
        kit.parent(post, head)
    return base


def rear_seat():
    b = kit.rounded_box
    seat = b("RearSeat", (W - 0.08, 0.52, 0.16), (0, 0.22, 0.36), P.SEAT, bevel=0.06)
    back = b("RearSeatBack", (W - 0.08, 0.14, 0.62), (0, 0.55, 0.72), P.SEAT, bevel=0.06,
             rotation=(-12, 0, 0))
    kit.parent(back, seat)
    for k, x in enumerate((-0.42, 0.0, 0.42)):
        head = b(f"RearHeadrest{k}", (0.24, 0.1, 0.14), (x, 0.6, 1.1), P.SEAT_DARK,
                 bevel=0.04)
        kit.parent(head, seat)
    # 뒷좌석 안전벨트: 기둥 위쪽에서 비스듬히 내려와 버클로
    for k, sx in enumerate((1, -1)):
        belt = b(f"SeatBelt{k}", (0.05, 0.008, 0.62), (sx * 0.52, 0.42, 0.78), "#3A3F44",
                 bevel=0.003, rotation=(-14, sx * 32, 0))
        kit.parent(belt, seat)
        buckle = b(f"Buckle{k}", (0.04, 0.03, 0.06), (sx * 0.2, 0.4, 0.47), P.STEEL, bevel=0.01)
        kit.parent(buckle, seat)
    for k, x in enumerate((-0.4, 0.4)):
        mat = b(f"FloorMat{k}", (0.42, 0.36, 0.01), (x, -0.25, 0.005), "#3B332D", bevel=0.004)
        kit.parent(mat, seat)
    arm = b("Armrest", (0.22, 0.42, 0.1), (0, 0.24, 0.5), P.SEAT_DARK, bevel=0.04)
    for k, dx in enumerate((-0.05, 0.05)):
        cup = kit.cylinder(f"CupHolder{k}", 0.035, 0.03, (dx, 0.1, 0.545), P.RUBBER)
        kit.parent(cup, arm)
    return seat


def dashboard():
    b = kit.rounded_box
    dash = b("Dashboard", (W, 0.42, 0.26), (0, -1.72, 0.82), P.DASH, bevel=0.07)
    top = b("DashTop", (W - 0.06, 0.36, 0.04), (0, -1.74, 0.96), P.DASH_TOP, bevel=0.02)
    kit.parent(top, dash)
    screen = b("DashScreen", (0.3, 0.02, 0.17), (0, -1.5, 0.86), P.SCREEN, bevel=0.012,
               rotation=(-12, 0, 0))
    kit.parent(screen, dash)
    logo = kit.sphere("DashLogo", 0.018, (0, -1.488, 0.86), P.LOGO_YELLOW,
                      scale=(1, 0.3, 1.3))
    kit.parent(logo, screen)
    cluster = b("Cluster", (0.32, 0.06, 0.12), (0.36, -1.56, 0.93), P.DASH_TOP, bevel=0.03)
    kit.parent(cluster, dash)
    for k, x in enumerate((-0.6, -0.12, 0.12, 0.6)):
        vent = b(f"Vent{k}", (0.12, 0.02, 0.05), (x, -1.505, 0.92), P.RUBBER, bevel=0.012)
        kit.parent(vent, dash)
    for k, dx in enumerate((-0.07, 0.07)):
        gauge = kit.cylinder(f"Gauge{k}", 0.05, 0.01, (0.36 + dx, -1.525, 0.93), "#1E2A26",
                             rotation=(90, 0, 0))
        needle = b(f"Needle{k}", (0.004, 0.004, 0.04), (0.36 + dx, -1.518, 0.94), "#FF6B4A",
                   bevel=0.001, rotation=(0, 35 - 70 * k, 0))
        kit.parent(gauge, cluster)
        kit.parent(needle, gauge)
    for k, x in enumerate((-0.6, -0.12, 0.12, 0.6)):
        for j in range(3):
            slat = b(f"VentSlat{k}{j}", (0.11, 0.004, 0.006), (x, -1.493, 0.905 + j * 0.015),
                     "#5A5048", bevel=0.001)
            kit.parent(slat, dash)
    glove = b("Glovebox", (0.4, 0.02, 0.14), (-0.4, -1.505, 0.74), P.DASH_TOP, bevel=0.02)
    kit.parent(glove, dash)
    for k, sx in enumerate((1, -1)):
        visor = b(f"SunVisor{k}", (0.4, 0.16, 0.025), (sx * 0.36, -1.45, ROOF - 0.04),
                  P.TRIM, bevel=0.012, rotation=(8, 0, 0))
        kit.parent(visor, dash)
    console = b("CenterConsole", (0.26, 0.6, 0.38), (0, -1.25, 0.19), P.DASH, bevel=0.05)
    kit.parent(console, dash)
    shifter = kit.sphere("Shifter", 0.035, (0, -1.15, 0.43), P.RUBBER)
    kit.parent(shifter, console)
    wheel = kit.torus("Wheel", 0.17, 0.022, (0.36, -1.4, 0.86), P.RUBBER, rotation=(70, 0, 0))
    hub = kit.cylinder("WheelHub", 0.05, 0.04, (0.36, -1.41, 0.86), P.DASH_TOP,
                       rotation=(70, 0, 0))
    kit.parent(hub, wheel)
    return dash


def doors():
    b = kit.rounded_box
    spans = {"L": (B_PILLAR, FRONT + 0.25), "RL": (BACK - 0.2, B_PILLAR)}
    for sx, front_name, rear_name in ((1, "DoorPanel_L", "DoorPanel_RL"),
                                      (-1, "DoorPanel_R", "DoorPanel_RR")):
        x = sx * (HALF - 0.01)
        for name, (y0, y1) in ((front_name, spans["L"]), (rear_name, spans["RL"])):
            y = (y0 + y1) / 2
            ln = abs(y0 - y1) - 0.04
            panel = b(name, (0.04, ln, BELT - 0.06), (x, y, BELT / 2), P.DOOR, bevel=0.02)
            trim = b(f"{name}_Trim", (0.06, ln, 0.05), (x - sx * 0.01, y, BELT - 0.02),
                     P.TRIM, bevel=0.02)
            arm = b(f"{name}_Arm", (0.09, ln * 0.6, 0.05), (x - sx * 0.04, y, 0.46),
                    P.DOOR_DARK, bevel=0.02)
            handle = b(f"{name}_Handle", (0.03, 0.1, 0.03), (x - sx * 0.03, y - 0.1, 0.56),
                       P.STEEL, bevel=0.01)
            pocket = b(f"{name}_Pocket", (0.07, ln * 0.7, 0.1), (x - sx * 0.04, y, 0.16),
                       P.DOOR_DARK, bevel=0.02)
            speaker = kit.cylinder(f"{name}_Speaker", 0.06, 0.02,
                                   (x - sx * 0.025, y + ln * 0.25, 0.22), P.RUBBER,
                                   rotation=(0, 90, 0))
            switch = b(f"{name}_Switch", (0.03, 0.06, 0.012), (x - sx * 0.05, y + 0.08, 0.49),
                       P.RUBBER, bevel=0.004)
            for o in (trim, arm, handle, pocket, speaker, switch):
                kit.parent(o, panel)


def mirror_and_lights():
    b = kit.rounded_box
    mirror = b("Mirror", (0.26, 0.04, 0.07), (0, -1.38, 1.13), P.RUBBER, bevel=0.025)
    face = b("MirrorFace", (0.23, 0.01, 0.05), (0, -1.355, 1.13), "#9FB3C2", bevel=0.01)
    stem = kit.cylinder("MirrorStem", 0.01, 0.08, (0, -1.4, 1.2), P.RUBBER)
    for o in (face, stem):
        kit.parent(o, mirror)
    string = kit.cylinder("MirrorCharmString", 0.0025, 0.09, (0, -1.37, 1.05), "#8A5A3C")
    charm = kit.sphere("MirrorCharm", 0.03, (0, -1.37, 0.98), P.EGG, scale=(1, 1, 1.3))
    kit.parent(string, charm)
    dome = b("DomeLight", (0.22, 0.12, 0.025), (0, -0.4, ROOF - 0.005), "#F3EDE2",
             bevel=0.01, emit=0.3)
    shelf = b("RearShelf", (W - 0.1, 0.24, 0.025), (0, BACK - 0.06, BELT + 0.07), P.DOOR,
              bevel=0.01)
    return mirror, dome, shelf


def props():
    """뒷좌석 위 장난감들. 캐릭터가 밀거나 올라갈 수 있다."""
    kit.rounded_box("Cushion", (0.3, 0.22, 0.09), (0.42, 0.24, 0.49), P.CUSHION,
                    bevel=0.04, rotation=(0, 0, 12))
    body = kit.sphere("Plush", 0.09, (-0.45, 0.28, 0.53), P.PLUSH, scale=(1, 0.9, 1.05))
    head = kit.sphere("PlushHead", 0.065, (-0.45, 0.29, 0.66), P.PLUSH)
    kit.parent(head, body)
    for k, dx in enumerate((-0.045, 0.045)):
        ear = kit.sphere(f"PlushEar{k}", 0.025, (-0.45 + dx, 0.29, 0.72), P.PLUSH_DARK)
        kit.parent(ear, head)
    bottle = kit.cylinder("Bottle", 0.03, 0.2, (HALF - 0.06, 0.1, 0.24), P.BOTTLE)
    cap = kit.cylinder("BottleCap", 0.022, 0.03, (HALF - 0.06, 0.1, 0.355), "#F1E6CF")
    kit.parent(cap, bottle)


def walk_surfaces():
    """캐릭터가 서고 걸을 수 있는 면. 각 면의 가운데·크기만 의미가 있다."""
    w = kit.plane
    c = P.WALK
    # 뒷좌석은 팔걸이 양옆 두 칸 (팔걸이 아래로 파고들지 않게)
    w("Walk_RearSeat_L", (0.48, 0.4), (0.39, 0.22, 0.445), c)
    w("Walk_RearSeat_R", (0.48, 0.4), (-0.39, 0.22, 0.445), c)
    w("Walk_Armrest", (0.2, 0.38), (0, 0.24, 0.556), c)
    w("Walk_RearShelf", (W - 0.2, 0.2), (0, BACK - 0.06, BELT + 0.083), c)
    w("Walk_Dashboard", (W - 0.3, 0.3), (0, -1.74, 0.982), c)
    # 머리받침·등받이 위는 좁고 캐릭터가 의자에 묻혀 보여서 걷는 면에서 뺐다 (대시보드는 창턱으로 간다)
    w("Walk_DoorSill_L", (0.06, BACK - FRONT - 0.5), (HALF - 0.04, -0.6, BELT + 0.005), c)
    w("Walk_DoorSill_R", (0.06, BACK - FRONT - 0.5), (-HALF + 0.04, -0.6, BELT + 0.005), c)


def build():
    kit.clear_scene()
    shell()
    glass()
    front_seat("FL", 1)
    front_seat("FR", -1)
    rear_seat()
    dashboard()
    doors()
    mirror_and_lights()
    props()
    walk_surfaces()


def check():
    import bpy
    names = {o.name for o in bpy.data.objects}
    missing = [n for n in REQUIRED + WALKS if n not in names]
    if missing:
        print(f"names MISSING {missing}")
        sys.exit(1)
    print(f"names OK ({len(REQUIRED)} + {len(WALKS)} walk)")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    fbx = argv[argv.index("--fbx") + 1] if "--fbx" in argv else None
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    build()
    check()
    if "--check" in argv:
        return
    if out:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        kit.export_glb(os.path.abspath(out))
        print(f"exported {out}")
    if fbx:
        import bpy
        os.makedirs(os.path.dirname(os.path.abspath(fbx)), exist_ok=True)
        # Unity 는 FBX 를 패키지 없이 읽는다. 단위·축은 Unity 기준(Y 위)으로 굽는다
        bpy.ops.export_scene.fbx(filepath=os.path.abspath(fbx), apply_scale_options="FBX_SCALE_ALL",
                                 axis_forward="-Z", axis_up="Y", bake_space_transform=True,
                                 use_mesh_modifiers=True, mesh_smooth_type="FACE")
        print(f"exported {fbx}")
    if preview:
        import bpy
        for o in bpy.data.objects:
            if o.name.startswith("Walk_"):
                o.hide_render = True
        kit.setup_render()
        os.makedirs(preview, exist_ok=True)
        eye = (0, 0.3, 1.04)  # 카시트에 앉은 아이 눈높이
        views = {
            "cabin_front": (0, -2, 0.85),
            "cabin_left": (2, -0.3, 0.8),
            "cabin_back": (0, 2, 0.75),
            "cabin_overview": None,
        }
        for name, target in views.items():
            path = os.path.abspath(os.path.join(preview, f"{name}.png"))
            if target is None:
                # 위에서 비스듬히 본 전체 배치 (지붕 위 시점, 천장은 렌더에서 숨긴다)
                import bpy as _b
                _b.data.objects["Shell"].hide_render = True
                for o in _b.data.objects:
                    if o.name in ("Headliner", "RoofRail_1", "RoofRail_-1", "DomeLight"):
                        o.hide_render = True
                kit.render_preview(path, (1.9, 1.6, 2.6), (0, -0.6, 0.5), lens=20)
            else:
                kit.render_preview(path, eye, target, lens=14)
            print(f"preview {path}")


if __name__ == "__main__":
    main()
