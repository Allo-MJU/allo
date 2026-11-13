"""이미지→3D 서비스(Tripo 등)에서 받은 캐릭터 FBX 를 Unity 에 넣기 좋게 정리한다. 손 작업 없이 스크립트로만.

실행:
  blender -b -P tools/blender/character.py -- --in ~/Downloads/road_sprout/road_sprout.fbx \
      --out ~/Downloads/allo_3d/road_sprout/road_sprout.fbx --preview docs/work-results/explore/char_road_sprout.png
  # 검사만 (부품·삼각형·크기·텍스처·틈)
  blender -b -P tools/blender/character.py -- --in road_sprout.fbx --check

하는 일:
  - 부품(메시)은 합치지 않고 그대로 둔다 (나중에 부품별로 움직일 수 있게)
  - 발바닥이 원점: 바닥 z=0, 가로·앞뒤 가운데 0. 앞은 -Y (kit.py·props.py 와 같음 → Unity 에서 +Z)
  - 부품 경계 틈 메우기: 열린 가장자리 버텍스를 가장 가까운 다른 부품 표면으로 당겨 붙인다 (면을 새로 만들지 않음)
  - 재질: 색 텍스처만 남기고 노멀맵은 뺀다 (Allo/Toon 셰이더는 노멀맵을 쓰지 않는다). 텍스처는 --tex 크기로 줄인다
  - 색 텍스처가 하나도 없으면 --fallback-color 단색으로 두고 크게 경고한다

선택:
  --yaw 도        Z 축으로 돌린다 (모델 앞이 -Y 가 아닐 때)
  --max-tris N    전체 삼각형이 N 보다 많으면 부품마다 같은 비율로 데시메이트
  --size X,Y,Z    실제 크기(m)로 맞춘다: 가로, 앞뒤, 키. 0 은 나머지 축과 같은 비율 (예: 0,0,0.125 = 키 0.125m, 비율 유지)
  --tex N         텍스처 한 변 최대 픽셀 (기본 1024)
  --gap M         이 거리(m, 원본 크기 기준)보다 먼 틈은 메우지 않는다 (기본 0.015)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import kit  # noqa: E402


def arg(argv, name, default=None, cast=str):
    return cast(argv[argv.index(name) + 1]) if name in argv else default


def meshes():
    return sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: o.name)


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def load(path):
    kit.clear_scene()
    bpy.ops.import_scene.fbx(filepath=path)
    # 빈 물체·뼈대는 버리고 메시만, 변환은 메시에 굽는다
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            for c in o.children:
                mw = c.matrix_world.copy()
                c.parent = None
                c.matrix_world = mw
            bpy.data.objects.remove(o)
    for o in meshes():
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)


def resize(spec):
    """--size X,Y,Z (m). 0 인 축은 0 이 아닌 축들의 평균 배율을 쓴다. 발바닥 원점은 그대로"""
    if not spec:
        return
    want = [float(v) for v in spec.split(",")]
    lo, hi = bounds(meshes())
    have = hi - lo
    ks = [w / h for w, h in zip(want, have) if w > 0]
    if not ks:
        return
    k = sum(ks) / len(ks)
    sc = [w / h if w > 0 else k for w, h in zip(want, have)]
    m = Matrix.Diagonal((*sc, 1))
    for o in meshes():
        o.data.transform(m)
        o.data.update()


def place(yaw):
    objs = meshes()
    rot = Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in objs:
        o.data.transform(rot)
    lo, hi = bounds(objs)
    shift = Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    for o in objs:
        o.data.transform(shift)
        o.data.update()


def close_gaps(limit):
    """열린 가장자리 버텍스를 가장 가까운 다른 부품 표면으로 옮긴다. 옮긴 수와 남은 최대 틈(m)을 돌려준다"""
    objs = meshes()
    trees = {}
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        trees[o.name] = BVHTree.FromBMesh(bm)
        bm.free()
    moved, left = 0, 0.0
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for v in bm.verts:
            if not v.is_boundary:
                continue
            best = None
            for name, t in trees.items():
                if name == o.name:
                    continue
                hit = t.find_nearest(v.co)
                if hit[0] is not None and (best is None or hit[3] < best[3]):
                    best = hit
            if best is None:
                continue
            d = best[3]
            if 0.0005 < d <= limit:
                # 표면에서 0.5mm 안쪽까지 들여 넣어 가장자리가 이웃 부품 속에 묻히게 한다
                v.co = best[0] - best[1].normalized() * 0.0005
                moved += 1
            elif d > limit:
                left = max(left, d)
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()
    return moved, left


def is_normal_map(img):
    """노멀맵은 평균이 (0.5, 0.5, 1) 근처인 보라·파랑 그림이다"""
    if img.size[0] == 0:
        return False
    px = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, img.channels)[::97, :3]
    r, g, b = px.mean(axis=0)
    return b > 0.75 and abs(r - 0.5) < 0.12 and abs(g - 0.5) < 0.12


def fix_materials(out_dir, tex_size, fallback):
    """색 텍스처만 Base Color 에 꽂고 노멀맵 노드는 지운다. 색 텍스처 수를 돌려준다"""
    colored = 0
    saved = {}
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if bsdf is None:
            continue
        # Base Color 에 꽂힌 그림을 우선, 없으면 노멀맵이 아닌 첫 그림. 나머지(노멀·metallic·roughness)는 버린다
        color_img = next((l.from_node for l in nt.links if l.to_socket == bsdf.inputs["Base Color"]
                          and l.from_node.bl_idname == "ShaderNodeTexImage" and l.from_node.image is not None), None)
        for n in list(nt.nodes):
            if n.bl_idname != "ShaderNodeTexImage" or n.image is None or n == color_img:
                continue
            if color_img is None and not is_normal_map(n.image):
                color_img = n
            else:
                nt.nodes.remove(n)
        for n in list(nt.nodes):
            if n.bl_idname == "ShaderNodeNormalMap":
                nt.nodes.remove(n)
        if color_img is None:
            bsdf.inputs["Base Color"].default_value = kit.srgb(fallback)
            continue
        img = color_img.image
        if img.name not in saved:
            if max(img.size) > tex_size:
                img.scale(tex_size, tex_size)
            path = os.path.join(out_dir, bpy.path.clean_name(img.name) + ".png")
            img.filepath_raw = path
            img.file_format = "PNG"
            img.save()
            saved[img.name] = path
        nt.links.new(color_img.outputs["Color"], bsdf.inputs["Base Color"])
        colored += 1
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    return colored


def decimate(max_tris):
    total = sum(tris(o) for o in meshes())
    if max_tris <= 0 or total <= max_tris:
        return total
    ratio = max_tris / total
    for o in meshes():
        mod = o.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
        # 크게 줄이면 면이 각져 보인다: 부드러운 음영 (30도 넘는 모서리는 각을 살린다)
        for p in o.data.polygons:
            p.use_smooth = True
        if hasattr(o.data, "set_sharp_from_angle"):
            o.data.set_sharp_from_angle(angle=math.radians(30))
    return sum(tris(o) for o in meshes())


def report(label):
    objs = meshes()
    lo, hi = bounds(objs)
    size = hi - lo
    print(f"[character] {label}: 부품 {len(objs)}, 삼각형 {sum(tris(o) for o in objs)}, "
          f"크기 {size.x:.3f}×{size.y:.3f}×{size.z:.3f} (가로×앞뒤×키), 바닥 z={lo.z:.3f}, "
          f"가운데 ({(lo.x + hi.x) / 2:+.3f}, {(lo.y + hi.y) / 2:+.3f})")


def preview(path):
    kit.setup_render()
    scene = bpy.context.scene
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 600
    lo, hi = bounds(meshes())
    h = hi.z - lo.z
    r = max(hi - lo) * 3.2  # 가장 긴 변이 화면에 다 들어오는 거리 (lens 50)
    target = (0, 0, h * 0.45)
    base = os.path.splitext(path)[0]
    for name, eye in [("front", (0, -r, h * 0.9)), ("side", (r, 0, h * 0.9)),
                      ("three", (r * 0.7, -r * 0.7, h * 1.4))]:
        kit.render_preview(f"{base}_{name}.png", eye, target, lens=50)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = os.path.abspath(os.path.expanduser(arg(argv, "--in")))
    load(src)
    report("원본")
    if "--check" in argv:
        return
    place(arg(argv, "--yaw", 0.0, float))
    moved, left = close_gaps(arg(argv, "--gap", 0.015, float))
    print(f"[character] 틈 메우기: 버텍스 {moved}개 이동, 메우지 않은 가장 큰 틈 {left * 1000:.1f}mm")
    after = decimate(arg(argv, "--max-tris", 0, int))
    resize(arg(argv, "--size"))
    out = arg(argv, "--out")
    if out:
        out = os.path.abspath(os.path.expanduser(out))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        colored = fix_materials(os.path.dirname(out), arg(argv, "--tex", 1024, int),
                                arg(argv, "--fallback-color", "#8FA850"))
        if colored == 0:
            print("[character] 경고: 색 텍스처가 없어요 (노멀맵만 있음). 단색으로 내보냅니다. "
                  "서비스에서 Base Color 텍스처를 포함해 다시 내보내세요")
        else:
            print(f"[character] 색 텍스처 {colored}개 (최대 {arg(argv, '--tex', 1024, int)}px)")
        bpy.ops.export_scene.fbx(filepath=out, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z",
                                 axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE",
                                 use_selection=False, object_types={"MESH"}, path_mode="RELATIVE")
        report(f"내보냄 {out} (삼각형 {after})")
    if "--preview" in argv:
        preview(os.path.abspath(arg(argv, "--preview")))


if __name__ == "__main__":
    main()
