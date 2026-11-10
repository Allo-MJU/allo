"""차 내부 모델을 만드는 공용 도형 함수. Blender 5.x 배경 모드(-b)에서 쓴다.

좌표: 미터, 원점은 뒷좌석 가운데 바닥, +Z 위, -Y 앞(차 진행 방향), +X 는 아이 기준 왼쪽.
모든 물체는 둥근 모서리(베벨) + 부드러운 음영으로 말랑한 장난감 느낌을 낸다.
"""
import math

import bpy

_materials = {}


def srgb(hex_color, alpha=1.0):
    h = hex_color.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*lin, alpha)


def material(hex_color, *, alpha=1.0, rough=0.55, emit=0.0):
    key = (hex_color, alpha, rough, emit)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(f"M_{hex_color.lstrip('#')}_{int(alpha * 100)}")
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = rough
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        if hasattr(m, "blend_method"):
            m.blend_method = "BLEND"
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = srgb(hex_color)
        bsdf.inputs["Emission Strength"].default_value = emit
    _materials[key] = m
    return m


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()


def _finish(obj, name, color, bevel, segments, alpha=1.0, emit=0.0, smooth=True):
    obj.name = name
    obj.data.name = name
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    if smooth:
        bpy.ops.object.shade_smooth()
    obj.data.materials.append(material(color, alpha=alpha, emit=emit))
    obj.select_set(False)
    return obj


def rounded_box(name, size, location, color, *, bevel=0.02, rotation=(0, 0, 0),
                segments=4, alpha=1.0, emit=0.0):
    """size=(x,y,z) 미터, location 은 상자 가운데, rotation 은 도(degree)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location,
                                    rotation=[math.radians(a) for a in rotation])
    obj = bpy.context.active_object
    obj.scale = size
    return _finish(obj, name, color, min(bevel, min(size) * 0.45), segments,
                   alpha=alpha, emit=emit)


def cylinder(name, radius, depth, location, color, *, rotation=(0, 0, 0),
             bevel=0.005, vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location,
                                        vertices=vertices,
                                        rotation=[math.radians(a) for a in rotation])
    return _finish(bpy.context.active_object, name, color, bevel, 3)


def sphere(name, radius, location, color, *, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location,
                                         segments=32, ring_count=16)
    obj = bpy.context.active_object
    obj.scale = scale
    return _finish(obj, name, color, 0, 0)


def torus(name, major, minor, location, color, *, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     location=location,
                                     rotation=[math.radians(a) for a in rotation])
    return _finish(bpy.context.active_object, name, color, 0, 0)


def plane(name, size, location, color, *, rotation=(0, 0, 0), alpha=1.0):
    """두께 없는 판. 유리·걷는 면에 쓴다."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=location,
                                     rotation=[math.radians(a) for a in rotation])
    obj = bpy.context.active_object
    obj.scale = (size[0], size[1], 1)
    return _finish(obj, name, color, 0, 0, alpha=alpha, smooth=False)


def parent(child, parent_obj):
    child.parent = parent_obj
    child.matrix_parent_inverse = parent_obj.matrix_world.inverted()


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_yup=True)


def setup_render(engine_pref=("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH")):
    scene = bpy.context.scene
    for engine in engine_pref:
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb("#93C6EA")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(-20),
                                                   math.radians(30)))
    sun = bpy.context.active_object
    sun.name = "PreviewSun"
    sun.data.energy = 2.2
    bpy.ops.object.light_add(type="AREA", location=(0, -0.5, 1.15))
    fill = bpy.context.active_object
    fill.name = "PreviewFill"
    fill.data.energy = 25
    fill.data.size = 1.2
    return scene


def render_preview(path, location, look_at, lens=18):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = location
    direction = (look_at[0] - location[0], look_at[1] - location[1],
                 look_at[2] - location[2])
    from mathutils import Vector
    cam.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
