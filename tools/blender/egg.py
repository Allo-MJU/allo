"""정리된 알 FBX(character.py 결과)를 지그재그 금을 따라 윗껍데기·아래 껍데기로 자른다. 부화 연출(Unity Toys.EggTop/EggBottom)용.

실행:
  blender -b -P tools/blender/egg.py -- --in ~/Downloads/allo_3d_props/egg/egg.fbx \
      --out ~/Downloads/allo_3d_props --preview /tmp/egg_split.png

결과: <out>/egg_top/egg_top.fbx (원점 = 금 높이 가운데), <out>/egg_bottom/egg_bottom.fbx (원점 = 바닥 가운데).
잘린 면은 크림색 속껍질 재질(EggInside)로 채운다. 크기·좌표는 입력 알 그대로(m).

선택:
  --cut 0.70     금 높이 (알 키에 대한 비율). Unity 는 윗껍데기를 알 키의 0.75 에서 날린다
  --amp 0.04     지그재그 높이 (알 키에 대한 비율, 위아래로)
  --teeth 9      지그재그 수
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import kit  # noqa: E402
from character import arg, bounds, load, meshes, tris  # noqa: E402

INSIDE = "#FFF4D6"  # 속껍질 (크림)


def cutter(height, radius, cut, amp, teeth):
    """금 아래쪽을 채우는 닫힌 입체: 윗면이 지그재그 왕관, 아랫면은 알 밑보다 아래"""
    bm = bmesh.new()
    n = teeth * 2
    top = [bm.verts.new((math.cos(i * 2 * math.pi / n) * radius, math.sin(i * 2 * math.pi / n) * radius,
                         height * (cut + (amp if i % 2 == 0 else -amp)))) for i in range(n)]
    bot = [bm.verts.new((v.co.x, v.co.y, -height)) for v in top]
    ct = bm.verts.new((0, 0, height * cut))
    cb = bm.verts.new((0, 0, -height))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ct, top[i], top[j]))
        bm.faces.new((cb, bot[j], bot[i]))
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Cutter")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Cutter", me)
    bpy.context.scene.collection.objects.link(obj)
    inside = bpy.data.materials.new("EggInside")
    inside.use_nodes = True
    inside.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = kit.srgb(INSIDE)
    me.materials.append(inside)
    return obj


def piece(src, cut_obj, op, name):
    obj = src.copy()
    obj.data = src.data.copy()
    obj.name = obj.data.name = name
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.operation = op
    mod.object = cut_obj
    mod.solver = "EXACT"
    if hasattr(mod, "material_mode"):
        mod.material_mode = "TRANSFER"  # 잘린 면은 자르개 재질(속껍질)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def export(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o == obj)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE",
                             object_types={"MESH"}, path_mode="COPY", embed_textures=False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    load(os.path.abspath(os.path.expanduser(arg(argv, "--in"))))
    objs = meshes()
    if len(objs) > 1:
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
    egg = meshes()[0]
    lo, hi = bounds([egg])
    h = hi.z - lo.z
    cut, amp, teeth = arg(argv, "--cut", 0.70, float), arg(argv, "--amp", 0.04, float), arg(argv, "--teeth", 9, int)
    c = cutter(h, max(hi.x - lo.x, hi.y - lo.y) * 1.5, cut, amp, teeth)
    bottom = piece(egg, c, "INTERSECT", "EggBottom")
    top = piece(egg, c, "DIFFERENCE", "EggTop")
    bpy.data.objects.remove(c)
    egg.hide_set(True)
    egg.hide_render = True
    top.data.transform(Matrix.Translation((0, 0, -h * cut)))  # 원점 = 금 높이 가운데
    for o in (top, bottom):
        b0, b1 = bounds([o])
        print(f"[egg] {o.name}: 삼각형 {tris(o)}, 높이 {b1.z - b0.z:.4f}m, 바닥 z={b0.z:+.4f}, 재질 {[m.name for m in o.data.materials]}")
    out = os.path.abspath(os.path.expanduser(arg(argv, "--out")))
    export(top, os.path.join(out, "egg_top", "egg_top.fbx"))
    export(bottom, os.path.join(out, "egg_bottom", "egg_bottom.fbx"))
    print(f"[egg] 내보냄 {out}/egg_top, {out}/egg_bottom (알 키 {h:.4f}m, 금 {cut:.2f}±{amp:.2f})")
    if "--preview" in argv:
        top.location = (0, 0, h * cut + h * 0.25)  # 윗껍데기를 띄워서 찍는다
        kit.setup_render()
        bpy.context.scene.render.resolution_x = 900
        bpy.context.scene.render.resolution_y = 700
        r = h * 4
        kit.render_preview(os.path.abspath(arg(argv, "--preview")), (r * 0.6, -r * 0.8, h * 1.6), (0, 0, h * 0.6), lens=50)


if __name__ == "__main__":
    main()
