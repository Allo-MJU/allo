"""창밖 물체(나무·집·차·가로등·구름 등)를 만든다. 각 물체는 원점이 바닥 가운데이고 -Y 가 앞이다.

실행:
  blender -b -P tools/blender/props.py -- --fbx unity/allo_explore/Assets/Models/Props.fbx \
      --preview docs/work-results/explore/props.png

이름 규칙: 최상위 물체 이름이 Unity 에서 쓰는 이름이다 (PROPS). 재질 이름이 Glow_ 로 시작하면
Unity 에서 스스로 빛나는 재질로 바꾼다 (밤에 켜지는 전조등·가로등·창문).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
import kit  # noqa: E402

PROPS = ["Tree_Round", "Tree_Pine", "Bush", "House_A", "House_B", "Car_Sedan", "Car_SUV", "Bus",
         "StreetLamp", "Cloud", "Rock", "Sailboat", "Lighthouse", "Bench"]


def mat(name, hex_color, rough=0.6, emit=0.0):
    m = kit.material(hex_color, rough=rough, emit=emit)
    m.name = name
    return m


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def ico(name, radius, loc, m, subdiv=2, squash=(1, 1, 1), jitter=0.0, seed=0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = squash
    if jitter:
        rnd = random.Random(seed)
        for v in o.data.vertices:
            v.co *= 1 + rnd.uniform(-jitter, jitter)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    assign(o, m)
    return o


def cone(name, r1, r2, depth, loc, m, verts=10):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc)
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_smooth()
    assign(o, m)
    return o


def box(name, size, loc, m, bevel=0.03, rot=(0, 0, 0)):
    o = kit.rounded_box(name, size, loc, "#ffffff", bevel=bevel, rotation=rot)
    assign(o, m)
    return o


def cyl(name, r, depth, loc, m, rot=(0, 0, 0), verts=16):
    o = kit.cylinder(name, r, depth, loc, "#ffffff", rotation=rot, vertices=verts)
    assign(o, m)
    return o


def prism(name, w, d, h, loc, m):
    """박공지붕: 단면이 삼각형인 기둥 (x 폭 w, y 길이 d, 높이 h)"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    pts = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (0, -d / 2, h),
           (-w / 2, d / 2, 0), (w / 2, d / 2, 0), (0, d / 2, h)]
    v = [bm.verts.new(p) for p in pts]
    for f in [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]:
        bm.faces.new([v[i] for i in f])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.location = loc
    me.materials.append(m)
    return o


def join(name, parts, at=(0, 0, 0)):
    """여러 조각을 한 물체로 합친다. 원점은 at (바닥 가운데)"""
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        for mod in list(p.modifiers):
            bpy.context.view_layer.objects.active = p
            bpy.ops.object.modifier_apply(modifier=mod.name)
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    bpy.context.scene.cursor.location = at
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    o.location = (0, 0, 0)
    return o


def build():
    kit.clear_scene()
    M = {
        "trunk": mat("Trunk", "#5B4434"), "leaf": mat("Leaf", "#3E6B3A"), "leaf_lit": mat("LeafLit", "#6E9E4C"),
        "pine": mat("Pine", "#2F5233"), "pine_lit": mat("PineLit", "#477A44"),
        "wall": mat("Wall", "#F1E6CF"), "wall2": mat("Wall2", "#E7B98F"), "roof": mat("Roof", "#B8634A"),
        "roof2": mat("Roof2", "#4A7FB0"), "door": mat("Door", "#6B4A35"), "glass": mat("Glass", "#5E7E9C", rough=0.15),
        "car_red": mat("CarRed", "#D4583F", rough=0.3), "car_blue": mat("CarBlue", "#5E8FC0", rough=0.3),
        "bus": mat("BusGreen", "#3FA36B", rough=0.35), "tire": mat("Tire", "#1E1E1E", rough=0.9),
        "chrome": mat("Chrome", "#C9CED0", rough=0.25), "steel": mat("Steel", "#7B8287", rough=0.4),
        "head": mat("Glow_Head", "#FFF4D6", emit=1), "tail": mat("Glow_Tail", "#E2463A", emit=1),
        "lamp": mat("Glow_Lamp", "#FFD98A", emit=1), "cloud": mat("Cloud", "#FFFFFF", rough=1),
        "rock": mat("Rock", "#8C8A80", rough=0.9), "white": mat("White", "#F3F1EA"), "red": mat("Red", "#D9473A"),
        "hull": mat("Hull", "#5A4636"), "wood": mat("Wood", "#8A6A4C"),
    }
    x = 0.0

    def place(o, width):
        nonlocal x
        o.location = (x + width / 2, 0, 0)
        x += width + 1.5

    # 둥근 활엽수: 줄기 + 그늘색 잎 덩어리 + 해 쪽 밝은 덩어리
    parts = [cone("t", 0.18, 0.1, 2.6, (0, 0, 1.3), M["trunk"], verts=8)]
    rnd = random.Random(1)
    for k in range(5):
        a = k / 5 * math.tau
        parts.append(ico("l", 1.1, (math.cos(a) * 0.8, math.sin(a) * 0.8, 3.2 + rnd.uniform(-0.3, 0.4)), M["leaf"],
                         jitter=0.12, seed=k))
    parts.append(ico("l", 1.2, (0, 0, 4.0), M["leaf"], jitter=0.1, seed=9))
    for k in range(3):
        parts.append(ico("l", 0.7, (-0.5 + k * 0.4, -0.6, 4.3 - k * 0.2), M["leaf_lit"], jitter=0.1, seed=20 + k))
    place(join("Tree_Round", parts), 4)

    # 바늘잎나무: 원뿔 세 겹
    parts = [cone("t", 0.15, 0.12, 1.4, (0, 0, 0.7), M["trunk"], verts=8)]
    for k, (r, z) in enumerate([(1.5, 2.0), (1.15, 3.3), (0.75, 4.5)]):
        parts.append(cone("p", r, 0.05, 2.0, (0, 0, z), M["pine" if k < 2 else "pine_lit"], verts=10))
    place(join("Tree_Pine", parts), 3.2)

    parts = [ico("b", 0.7, (dx, dy, 0.5), M["leaf"] if k else M["leaf_lit"], jitter=0.15, seed=30 + k)
             for k, (dx, dy) in enumerate([(0, 0), (0.6, 0.2), (-0.5, 0.3), (0.2, -0.5)])]
    place(join("Bush", parts), 2.2)

    # 단층집: 벽 + 박공지붕 + 문 + 창문 + 굴뚝
    parts = [box("w", (6, 5, 2.8), (0, 0, 1.4), M["wall"], bevel=0.05),
             prism("r", 6.8, 5.6, 1.8, (0, 0, 2.8), M["roof"]),
             box("d", (0.9, 0.08, 1.8), (0.8, -2.52, 0.9), M["door"], bevel=0.02),
             box("c", (0.5, 0.5, 1.2), (-1.8, 1.0, 3.6), M["wall2"], bevel=0.02)]
    for wx in (-1.6, 2.2):
        parts.append(box("g", (1.0, 0.08, 0.9), (wx, -2.52, 1.6), M["glass"], bevel=0.02))
    place(join("House_A", parts), 6.8)

    # 2층집: 평지붕 + 베란다
    parts = [box("w", (6, 6, 5.6), (0, 0, 2.8), M["wall2"], bevel=0.06),
             box("r", (6.4, 6.4, 0.3), (0, 0, 5.75), M["roof2"], bevel=0.05),
             box("v", (4, 1.0, 0.15), (0, -3.4, 2.9), M["white"], bevel=0.02),
             box("d", (1.0, 0.08, 2.0), (-1.6, -3.02, 1.0), M["door"], bevel=0.02)]
    for wz in (1.5, 4.3):
        for wx in (-1.8, 0.4, 2.0):
            if wz < 2 and wx < -1:
                continue
            parts.append(box("g", (1.0, 0.08, 1.1), (wx, -3.02, wz), M["glass"], bevel=0.02))
    place(join("House_B", parts), 6.4)

    def car(name, body_m, length, height, cab_len):
        p = [box("b", (1.8, length, 0.7), (0, 0, 0.6), body_m, bevel=0.18),
             box("c", (1.6, cab_len, height), (0, 0.15, 0.95 + height / 2), M["glass"], bevel=0.2),
             box("ct", (1.62, cab_len * 0.85, 0.08), (0, 0.15, 0.95 + height), body_m, bevel=0.04)]
        for sx in (-0.82, 0.82):
            for sy in (-length * 0.32, length * 0.32):
                p.append(cyl("w", 0.34, 0.25, (sx, sy, 0.34), M["tire"], rot=(0, 90, 0)))
                p.append(cyl("h", 0.18, 0.27, (sx, sy, 0.34), M["chrome"], rot=(0, 90, 0)))
            p.append(box("hl", (0.35, 0.06, 0.15), (sx * 0.7, -length / 2, 0.7), M["head"], bevel=0.02))
            p.append(box("tl", (0.35, 0.06, 0.15), (sx * 0.7, length / 2, 0.75), M["tail"], bevel=0.02))
        return join(name, p)

    place(car("Car_Sedan", M["car_red"], 4.3, 0.55, 2.1), 2)
    place(car("Car_SUV", M["car_blue"], 4.6, 0.75, 2.8), 2)

    parts = [box("b", (2.5, 11, 2.8), (0, 0, 1.8), M["bus"], bevel=0.2),
             box("g", (2.52, 9.6, 0.9), (0, 0.3, 2.4), M["glass"], bevel=0.05),
             box("f", (2.2, 0.05, 1.4), (0, -5.52, 2.2), M["glass"], bevel=0.03),
             box("s", (2.52, 11, 0.2), (0, 0, 1.2), M["white"], bevel=0.02)]
    for sy in (-3.6, 3.6):
        for sx in (-1.2, 1.2):
            parts.append(cyl("w", 0.5, 0.3, (sx, sy, 0.5), M["tire"], rot=(0, 90, 0)))
    for sx in (-0.9, 0.9):
        parts.append(box("hl", (0.4, 0.06, 0.2), (sx, -5.52, 0.9), M["head"], bevel=0.02))
    place(join("Bus", parts), 2.5)

    parts = [cyl("p", 0.09, 7, (0, 0, 3.5), M["steel"], verts=10),
             box("a", (0.08, 1.6, 0.08), (0, -0.75, 7.0), M["steel"], bevel=0.02, rot=(8, 0, 0)),
             box("h", (0.35, 0.6, 0.15), (0, -1.5, 6.85), M["steel"], bevel=0.05),
             box("l", (0.3, 0.5, 0.05), (0, -1.5, 6.76), M["lamp"], bevel=0.02)]
    place(join("StreetLamp", parts), 1)

    rnd = random.Random(7)
    parts = []
    for k in range(9):
        t = k / 8
        r = 2.2 + 2.6 * math.sin(t * math.pi) * rnd.uniform(0.7, 1.1)
        parts.append(ico("c", r, (-8 + t * 16, rnd.uniform(-1.5, 1.5), r * 0.55), M["cloud"], subdiv=2,
                         squash=(1, 1, 0.75), jitter=0.06, seed=50 + k))
    place(join("Cloud", parts), 20)

    place(join("Rock", [ico("r", 1.0, (0, 0, 0.45), M["rock"], subdiv=1, squash=(1.3, 1, 0.7), jitter=0.2, seed=3)]), 2.6)

    parts = [box("h", (1.4, 4.2, 0.7), (0, 0, 0.35), M["hull"], bevel=0.25),
             cyl("m", 0.05, 5, (0, 0.2, 3.1), M["wood"], verts=8),
             prism("s", 0.12, 2.6, 4.2, (0, 0.35, 0.9), M["cloud"])]
    parts[-1].rotation_euler = (0, 0, 0)
    place(join("Sailboat", parts), 2)

    parts = [cone("t", 1.6, 1.1, 12, (0, 0, 6), M["white"], verts=16),
             cone("b", 1.45, 1.35, 1.6, (0, 0, 7.5), M["red"], verts=16),
             cyl("g", 1.0, 1.4, (0, 0, 12.7), M["lamp"], verts=16),
             cone("r", 1.3, 0.1, 1.4, (0, 0, 14.1), M["red"], verts=16)]
    place(join("Lighthouse", parts), 3.2)

    parts = [box("s", (1.6, 0.5, 0.08), (0, 0, 0.45), M["wood"], bevel=0.02),
             box("b", (1.6, 0.06, 0.4), (0, 0.22, 0.75), M["wood"], bevel=0.02)]
    for sx in (-0.7, 0.7):
        parts.append(box("l", (0.06, 0.45, 0.45), (sx, 0, 0.22), M["steel"], bevel=0.01))
    place(join("Bench", parts), 1.6)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    names = {o.name for o in bpy.data.objects}
    missing = [n for n in PROPS if n not in names]
    print("props MISSING", missing) if missing else print(f"props OK ({len(PROPS)})")
    if "--fbx" in argv:
        path = os.path.abspath(argv[argv.index("--fbx") + 1])
        # 내보낼 때는 모두 원점에 둔다 (Unity 에서 물체마다 따로 꺼내 쓴다)
        for o in bpy.data.objects:
            if o.type == "MESH":
                o["preview_x"] = o.location.x
                o.location = (0, 0, 0)
        bpy.ops.export_scene.fbx(filepath=path, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z",
                                 axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE")
        for o in bpy.data.objects:
            if "preview_x" in o:
                o.location.x = o["preview_x"]
        print(f"exported {path}")
    if "--preview" in argv:
        path = os.path.abspath(argv[argv.index("--preview") + 1])
        kit.setup_render()
        width = max(o.location.x for o in bpy.data.objects if o.type == "MESH")
        # 물체가 길게 늘어서 있어 앞·뒤 절반을 따로 찍는다
        half = width / 2
        for k, cx in enumerate((half / 2, half * 1.5)):
            kit.render_preview(path.replace(".png", f"_{k}.png"), (cx, -24, 8), (cx, 0, 3), lens=24)
        print(f"preview {path}")


if __name__ == "__main__":
    main()
