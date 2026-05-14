from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Euler, Vector


try:
    ROOT = Path(__file__).resolve().parents[1]
except NameError:
    ROOT = Path("/home/viniciuscgp/Desktop/v-games/RelicMiner/relicminer")

MODEL_DIR = ROOT / "models" / "player"
SOURCE_DIR = MODEL_DIR / "source"
BLEND_PATH = SOURCE_DIR / "Player_Adventurer.blend"
PREVIEW_PATH = SOURCE_DIR / "Player_Adventurer_preview.png"
TORSO_DECAL_PATH = SOURCE_DIR / "Player_Adventurer_torso_decal.png"
SEED = 7429


COLLECTION_NAME = "RelicMiner_Player_Adventurer"
PREFIXES = ("Player_", "Rig_")


def ensure_dirs() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)


def delete_previous() -> None:
    collection = bpy.data.collections.get(COLLECTION_NAME)
    if collection:
        for obj in list(collection.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(collection)

    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith(PREFIXES):
            bpy.data.objects.remove(obj, do_unlink=True)

    for data_group in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.armatures):
        for block in list(data_group):
            if block.users == 0 and block.name.startswith(PREFIXES):
                data_group.remove(block)

    for action in list(bpy.data.actions):
        if action.name.startswith("Player_Basic"):
            bpy.data.actions.remove(action)


def make_collection() -> bpy.types.Collection:
    collection = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)
    return collection


def link_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    collection.objects.link(obj)
    for other in list(obj.users_collection):
        if other != collection:
            other.objects.unlink(obj)


def make_mat(name: str, color: tuple[float, float, float, float], roughness: float = 0.78) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.22
    return mat


def make_image_mat(name: str, image: bpy.types.Image, roughness: float = 0.82) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = "BLEND"
    mat.use_screen_refraction = False
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.18
    return mat


def create_torso_decal_image() -> bpy.types.Image:
    size = 512
    image = bpy.data.images.new("Player_Adventurer_torso_decal", width=size, height=size, alpha=True)
    rng = random.Random(SEED + 109)
    pixels: list[float] = []

    def line_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
        abx, aby = bx - ax, by - ay
        apx, apy = px - ax, py - ay
        denom = abx * abx + aby * aby
        t = 0.0 if denom == 0.0 else max(0.0, min(1.0, (apx * abx + apy * aby) / denom))
        cx, cy = ax + abx * t, ay + aby * t
        return math.hypot(px - cx, py - cy)

    def in_tri(px: float, py: float, a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> bool:
        def sign(p1: tuple[float, float], p2: tuple[float, float], p3: tuple[float, float]) -> float:
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

        p = (px, py)
        d1 = sign(p, a, b)
        d2 = sign(p, b, c)
        d3 = sign(p, c, a)
        has_neg = d1 < 0 or d2 < 0 or d3 < 0
        has_pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (has_neg and has_pos)

    for y in range(size):
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            half_width = 0.34 + 0.09 * v
            inside = abs(u - 0.5) <= half_width and 0.03 <= v <= 0.97
            if not inside:
                pixels.extend((0.0, 0.0, 0.0, 0.0))
                continue

            color = [0.0, 0.0, 0.0, 0.0]

            # Blue shirt opening under the vest.
            v_shape = 0.38 < v < 0.83 and abs(u - 0.5) < (0.035 + (v - 0.38) * 0.30)
            top_shirt = v > 0.80 and abs(u - 0.5) < 0.27
            if v_shape or top_shirt:
                n = rng.uniform(-0.012, 0.012)
                shirt_shade = 0.035 * math.sin((u * 9.0 + v) * math.pi)
                color = [0.24 + shirt_shade + n, 0.42 + shirt_shade + n, 0.48 + shirt_shade + n, 1.0]

            # Pale folded collar, drawn into the texture instead of modeled as blocky wedges.
            left_collar = in_tri(u, v, (0.36, 0.77), (0.50, 0.77), (0.43, 0.62))
            right_collar = in_tri(u, v, (0.50, 0.77), (0.64, 0.77), (0.57, 0.62))
            if left_collar or right_collar:
                color = [0.55, 0.68, 0.68, 1.0]

            # Dark vest opening and seams.
            seam = line_dist(u, v, 0.40, 0.18, 0.50, 0.58) < 0.012 or line_dist(u, v, 0.60, 0.18, 0.50, 0.58) < 0.012
            if seam and 0.22 < v < 0.66:
                color = [0.20, 0.12, 0.06, 1.0]

            # Laces as texture strokes.
            lace = False
            lace_segments = [
                (0.43, 0.53, 0.57, 0.44),
                (0.57, 0.53, 0.43, 0.44),
                (0.44, 0.42, 0.56, 0.34),
                (0.56, 0.42, 0.44, 0.34),
            ]
            for ax, ay, bx, by in lace_segments:
                if line_dist(u, v, ax, ay, bx, by) < 0.006:
                    lace = True
                    break
            if lace:
                color = [0.10, 0.065, 0.035, 1.0]

            pixels.extend(tuple(max(0.0, min(1.0, c)) for c in color))

    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(TORSO_DECAL_PATH)
    image.file_format = "PNG"
    image.save()
    return image


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def shade_low_poly(obj: bpy.types.Object) -> None:
    if hasattr(obj.data, "polygons"):
        for poly in obj.data.polygons:
            poly.use_smooth = False


def bevel(obj: bpy.types.Object, width: float, segments: int = 1) -> None:
    mod = obj.modifiers.new("Player_soft_lowpoly_bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    shade_low_poly(obj)


def set_origin(obj: bpy.types.Object, location: Vector) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.scene.cursor.location = location
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.select_set(False)


def parent_keep_transform(obj: bpy.types.Object, parent: bpy.types.Object) -> None:
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def empty(name: str, location: tuple[float, float, float], collection: bpy.types.Collection, parent: bpy.types.Object | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.12
    obj.location = location
    collection.objects.link(obj)
    if parent:
        parent_keep_transform(obj, parent)
    return obj


def cube(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel_width: float = 0.025,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if bevel_width:
        bevel(obj, bevel_width, 1)
    else:
        shade_low_poly(obj)
    link_to_collection(obj, collection)
    return obj


def sphere(
    name: str,
    radius: float,
    scale: tuple[float, float, float],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    segments: int = 16,
    rings: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    shade_low_poly(obj)
    link_to_collection(obj, collection)
    return obj


def cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    vertices: int = 10,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel_width: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    assign(obj, mat)
    if bevel_width:
        bevel(obj, bevel_width, 1)
    else:
        shade_low_poly(obj)
    link_to_collection(obj, collection)
    return obj


def front_decal_plane(
    name: str,
    width: float,
    height: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=location, rotation=(math.radians(90.0), 0.0, 0.0))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (width * 0.5, height * 0.5, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    link_to_collection(obj, collection)
    return obj


def tapered_box_mesh(
    name: str,
    bottom: tuple[float, float],
    top: tuple[float, float],
    height: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    bx, by = bottom[0] * 0.5, bottom[1] * 0.5
    tx, ty = top[0] * 0.5, top[1] * 0.5
    z0, z1 = -height * 0.5, height * 0.5
    verts = [
        (-bx, -by, z0), (bx, -by, z0), (bx, by, z0), (-bx, by, z0),
        (-tx, -ty, z1), (tx, -ty, z1), (tx, ty, z1), (-tx, ty, z1),
    ]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    collection.objects.link(obj)
    assign(obj, mat)
    bevel(obj, 0.025, 1)
    return obj


def limb_segment(
    name: str,
    start: Vector,
    end: Vector,
    radius_a: float,
    radius_b: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    vertices: int = 10,
) -> bpy.types.Object:
    direction = end - start
    length = direction.length
    center = start + direction * 0.5
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius_b, radius2=radius_a, depth=length, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    assign(obj, mat)
    shade_low_poly(obj)
    link_to_collection(obj, collection)
    set_origin(obj, start)
    return obj


def wedge_mesh(
    name: str,
    points: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    origin: tuple[float, float, float] | None = None,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    faces = [(0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0)]
    mesh.from_pydata(points, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign(obj, mat)
    shade_low_poly(obj)
    if origin:
        set_origin(obj, Vector(origin))
    return obj


def add_curve_line(
    name: str,
    points: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    bevel_depth: float = 0.01,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 0
    poly = curve.splines.new("POLY")
    poly.points.add(len(points) - 1)
    for point, co in zip(poly.points, points):
        point.co = (co[0], co[1], co[2], 1.0)
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def add_armature(collection: bpy.types.Collection) -> bpy.types.Object:
    bpy.ops.object.armature_add(location=(0.0, 0.0, 0.0))
    arm = bpy.context.active_object
    arm.name = "Rig_Adventurer_Armature_Reference"
    arm.data.name = "Rig_Adventurer_Bones"
    link_to_collection(arm, collection)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = arm.data.edit_bones
    root = bones[0]
    root.name = "root"
    root.head = (0.0, 0.0, 0.15)
    root.tail = (0.0, 0.0, 0.85)

    def bone(name: str, head: tuple[float, float, float], tail: tuple[float, float, float], parent: bpy.types.EditBone | None) -> bpy.types.EditBone:
        b = bones.new(name)
        b.head = head
        b.tail = tail
        if parent:
            b.parent = parent
        return b

    pelvis = bone("pelvis", (0, 0, 0.85), (0, 0, 1.35), root)
    spine = bone("spine", (0, 0, 1.35), (0, 0, 2.2), pelvis)
    neck = bone("neck", (0, 0, 2.2), (0, 0, 2.46), spine)
    head = bone("head", (0, 0, 2.46), (0, 0, 3.2), neck)
    # Character faces -Y, so its right side is world -X and left side is world +X.
    for side, sx in (("R", -1.0), ("L", 1.0)):
        upper = bone(f"upper_arm.{side}", (0.28 * sx, 0, 2.08), (0.72 * sx, -0.02, 1.54), spine)
        fore = bone(f"forearm.{side}", (0.72 * sx, -0.02, 1.54), (0.78 * sx, -0.08, 1.05), upper)
        bone(f"hand.{side}", (0.78 * sx, -0.08, 1.05), (0.78 * sx, -0.10, 0.86), fore)
        thigh = bone(f"thigh.{side}", (0.22 * sx, 0, 1.18), (0.27 * sx, 0.02, 0.55), pelvis)
        shin = bone(f"shin.{side}", (0.27 * sx, 0.02, 0.55), (0.29 * sx, -0.02, 0.16), thigh)
        bone(f"foot.{side}", (0.29 * sx, -0.02, 0.16), (0.29 * sx, -0.26, 0.05), shin)
    bone("backpack", (0, 0.22, 1.65), (0, 0.42, 2.35), spine)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    arm.data.display_type = "STICK"
    return arm


def build_character() -> dict[str, object]:
    ensure_dirs()
    delete_previous()
    collection = make_collection()
    rng = random.Random(SEED)
    torso_decal = create_torso_decal_image()

    mats = {
        "skin": make_mat("Player_skin_warm", (0.86, 0.51, 0.30, 1.0), 0.82),
        "skin_shadow": make_mat("Player_skin_shadow", (0.66, 0.35, 0.20, 1.0), 0.85),
        "hair": make_mat("Player_chocolate_hair", (0.19, 0.10, 0.055, 1.0), 0.86),
        "cap": make_mat("Player_canvas_cap", (0.54, 0.31, 0.13, 1.0), 0.88),
        "cap_dark": make_mat("Player_dark_cap_seams", (0.25, 0.14, 0.065, 1.0), 0.88),
        "shirt": make_mat("Player_blue_shirt", (0.23, 0.40, 0.47, 1.0), 0.8),
        "shirt_fold": make_mat("Player_pale_sleeve_fold", (0.52, 0.64, 0.64, 1.0), 0.82),
        "vest": make_mat("Player_leather_vest", (0.42, 0.25, 0.12, 1.0), 0.84),
        "leather": make_mat("Player_straps_brown", (0.34, 0.19, 0.085, 1.0), 0.82),
        "dark_leather": make_mat("Player_dark_leather", (0.20, 0.12, 0.065, 1.0), 0.84),
        "pants": make_mat("Player_olive_pants", (0.22, 0.22, 0.15, 1.0), 0.86),
        "boot": make_mat("Player_worn_boots", (0.33, 0.18, 0.08, 1.0), 0.82),
        "metal": make_mat("Player_warm_buckle_metal", (0.78, 0.50, 0.18, 1.0), 0.45),
        "eye_white": make_mat("Player_eye_white", (0.96, 0.90, 0.78, 1.0), 0.48),
        "iris": make_mat("Player_amber_iris", (0.39, 0.20, 0.06, 1.0), 0.42),
        "black": make_mat("Player_black_detail", (0.035, 0.027, 0.022, 1.0), 0.6),
        "torso_decal": make_image_mat("Player_torso_decal_material", torso_decal, 0.86),
    }

    rig_root = empty("Rig_Player_Root_FK", (0.0, 0.0, 0.0), collection)
    pelvis = empty("Rig_Pelvis_FK", (0.0, 0.0, 1.1), collection, rig_root)
    spine = empty("Rig_Spine_FK", (0.0, 0.0, 1.85), collection, pelvis)
    head_ctrl = empty("Rig_Head_FK", (0.0, -0.01, 2.55), collection, spine)
    backpack_ctrl = empty("Rig_Backpack_FK", (0.0, 0.35, 1.95), collection, spine)

    controls = {"root": rig_root, "pelvis": pelvis, "spine": spine, "head": head_ctrl, "backpack": backpack_ctrl}
    for side, sx in (("R", -1.0), ("L", 1.0)):
        shoulder = empty(f"Rig_Shoulder_{side}_FK", (0.38 * sx, -0.02, 2.03), collection, spine)
        elbow = empty(f"Rig_Elbow_{side}_FK", (0.72 * sx, -0.06, 1.48), collection, shoulder)
        wrist = empty(f"Rig_Wrist_{side}_FK", (0.75 * sx, -0.10, 1.03), collection, elbow)
        hip = empty(f"Rig_Hip_{side}_FK", (0.23 * sx, 0.0, 1.10), collection, pelvis)
        knee = empty(f"Rig_Knee_{side}_FK", (0.27 * sx, -0.01, 0.55), collection, hip)
        ankle = empty(f"Rig_Ankle_{side}_FK", (0.28 * sx, -0.02, 0.16), collection, knee)
        controls[f"shoulder_{side}"] = shoulder
        controls[f"elbow_{side}"] = elbow
        controls[f"wrist_{side}"] = wrist
        controls[f"hip_{side}"] = hip
        controls[f"knee_{side}"] = knee
        controls[f"ankle_{side}"] = ankle

    armature = add_armature(collection)
    parent_keep_transform(armature, rig_root)

    neck = cylinder("Player_Neck", 0.13, 0.23, (0, -0.01, 2.34), mats["skin"], collection, vertices=10)
    head = sphere("Player_Head", 1.0, (0.43, 0.37, 0.51), (0.0, -0.04, 2.73), mats["skin"], collection, segments=18, rings=9)
    nose = sphere("Player_Nose", 1.0, (0.055, 0.040, 0.045), (0.0, -0.405, 2.67), mats["skin_shadow"], collection, segments=8, rings=4)
    ear_r = sphere("Player_Ear_R", 1.0, (0.08, 0.035, 0.12), (-0.43, -0.03, 2.66), mats["skin"], collection, segments=8, rings=4)
    ear_l = sphere("Player_Ear_L", 1.0, (0.08, 0.035, 0.12), (0.43, -0.03, 2.66), mats["skin"], collection, segments=8, rings=4)
    for obj in (neck, head, nose, ear_l, ear_r):
        parent_keep_transform(obj, head_ctrl)

    for side, sx in (("R", -1.0), ("L", 1.0)):
        eye = sphere(f"Player_Eye_{side}_White", 1.0, (0.062, 0.017, 0.082), (0.135 * sx, -0.397, 2.79), mats["eye_white"], collection, 12, 6)
        iris = sphere(f"Player_Eye_{side}_Iris", 1.0, (0.031, 0.006, 0.043), (0.135 * sx, -0.414, 2.788), mats["iris"], collection, 10, 4)
        pupil = sphere(f"Player_Eye_{side}_Pupil", 1.0, (0.014, 0.004, 0.020), (0.135 * sx, -0.420, 2.788), mats["black"], collection, 8, 4)
        brow = cube(
            f"Player_Eyebrow_{side}",
            (0.18, 0.025, 0.045),
            (0.135 * sx, -0.405, 2.93),
            mats["hair"],
            collection,
            rotation=(0.0, 0.0, math.radians(-9.0 * sx)),
            bevel_width=0.008,
        )
        for obj in (eye, iris, pupil, brow):
            parent_keep_transform(obj, head_ctrl)

    smile = add_curve_line("Player_Smile", [(-0.070, -0.424, 2.552), (0.0, -0.430, 2.542), (0.075, -0.424, 2.552)], mats["hair"], collection, 0.0025)
    parent_keep_transform(smile, head_ctrl)

    cap = sphere("Player_Cap_Crown", 1.0, (0.47, 0.38, 0.20), (0.0, -0.01, 3.10), mats["cap"], collection, 14, 5)
    brim = cube("Player_Cap_Brim", (0.55, 0.18, 0.06), (0.0, -0.34, 2.99), mats["cap"], collection, rotation=(math.radians(7), 0, 0), bevel_width=0.02)
    band = cube("Player_Cap_Front_Band", (0.80, 0.06, 0.08), (0.0, -0.31, 2.99), mats["cap_dark"], collection, bevel_width=0.01)
    for obj in (cap, brim, band):
        parent_keep_transform(obj, head_ctrl)

    hair_points = [
        ((-0.06, -0.37, 3.04), (-0.34, -0.56, 2.86), (-0.18, -0.32, 2.84), (-0.16, -0.28, 3.08)),
        ((0.05, -0.38, 3.03), (0.32, -0.55, 2.88), (0.16, -0.32, 2.82), (0.14, -0.28, 3.07)),
        ((-0.18, -0.30, 3.00), (-0.46, -0.42, 2.77), (-0.27, -0.22, 2.78), (-0.30, -0.18, 3.02)),
        ((0.20, -0.27, 2.99), (0.46, -0.38, 2.78), (0.28, -0.18, 2.79), (0.30, -0.14, 3.03)),
        ((0.0, -0.36, 3.02), (-0.04, -0.60, 2.80), (0.14, -0.38, 2.80), (0.08, -0.28, 3.04)),
    ]
    for i, pts in enumerate(hair_points, start=1):
        lock = wedge_mesh(f"Player_Hair_Front_Lock_{i:02d}", list(pts), mats["hair"], collection, (0.0, 0.0, 2.75))
        parent_keep_transform(lock, head_ctrl)
    for side, sx in (("R", -1.0), ("L", 1.0)):
        side_lock = wedge_mesh(
            f"Player_Hair_Side_{side}",
            [(0.33 * sx, -0.15, 2.94), (0.53 * sx, -0.18, 2.69), (0.37 * sx, -0.02, 2.59), (0.28 * sx, -0.03, 2.88)],
            mats["hair"],
            collection,
            (0.0, 0.0, 2.75),
        )
        parent_keep_transform(side_lock, head_ctrl)

    shirt = tapered_box_mesh("Player_Blue_Shirt_Torso", (0.62, 0.35), (0.76, 0.40), 0.78, (0.0, -0.01, 1.78), mats["shirt"], collection)
    vest = tapered_box_mesh("Player_Leather_Vest", (0.68, 0.39), (0.82, 0.44), 0.68, (0.0, -0.035, 1.75), mats["vest"], collection)
    belt = cube("Player_Belt", (0.78, 0.48, 0.12), (0.0, -0.04, 1.34), mats["dark_leather"], collection, bevel_width=0.015)
    buckle = cube("Player_Belt_Buckle", (0.20, 0.055, 0.16), (0.0, -0.295, 1.35), mats["metal"], collection, bevel_width=0.01)
    torso_decal_obj = front_decal_plane("Player_Torso_Shirt_Vest_Decal", 0.70, 0.78, (0.0, -0.326, 1.76), mats["torso_decal"], collection)
    strap = cube("Player_Crossbody_Strap", (0.13, 0.065, 0.92), (-0.07, -0.365, 1.77), mats["leather"], collection, rotation=(0, math.radians(-30), 0), bevel_width=0.012)
    for obj in (shirt, vest, belt, buckle, torso_decal_obj, strap):
        parent_keep_transform(obj, spine if obj.location.z > 1.45 else pelvis)

    pouch = cube("Player_Belt_Pouch_L", (0.22, 0.10, 0.36), (0.48, -0.22, 1.14), mats["leather"], collection, bevel_width=0.018)
    tool_loop = cylinder("Player_Belt_Tool_Loop_L", 0.055, 0.08, (0.34, -0.25, 1.19), mats["dark_leather"], collection, vertices=8, rotation=(math.radians(90), 0, 0))
    for obj in (pouch, tool_loop):
        parent_keep_transform(obj, pelvis)

    roll = cylinder("Player_Backpack_Rolled_Bedroll", 0.22, 0.72, (0.0, 0.36, 2.00), mats["dark_leather"], collection, vertices=12, rotation=(0.0, math.radians(90), 0.0), bevel_width=0.008)
    pack = cube("Player_Backpack_Base", (0.48, 0.20, 0.56), (0.0, 0.38, 1.72), mats["leather"], collection, bevel_width=0.035)
    for side, sx in (("R", -1.0), ("L", 1.0)):
        bedroll_cap = cylinder(f"Player_Bedroll_Cap_{side}", 0.185, 0.035, (0.37 * sx, 0.36, 2.00), mats["cap"], collection, vertices=10, rotation=(0.0, math.radians(90), 0.0))
        parent_keep_transform(bedroll_cap, backpack_ctrl)
    for obj in (roll, pack):
        parent_keep_transform(obj, backpack_ctrl)

    for side, sx in (("R", -1.0), ("L", 1.0)):
        upper_arm = limb_segment(f"Player_UpperArm_{side}", Vector((0.43 * sx, -0.02, 2.00)), Vector((0.66 * sx, -0.04, 1.52)), 0.135, 0.12, mats["shirt"], collection)
        cuff = cylinder(f"Player_Sleeve_Cuff_{side}", 0.13, 0.09, (0.66 * sx, -0.04, 1.52), mats["shirt_fold"], collection, vertices=10, rotation=(math.radians(12), 0, math.radians(12 * sx)), bevel_width=0.005)
        forearm = limb_segment(f"Player_Forearm_{side}", Vector((0.67 * sx, -0.05, 1.46)), Vector((0.75 * sx, -0.09, 1.04)), 0.10, 0.085, mats["skin"], collection)
        wrist_band = cylinder(f"Player_Wrist_Wrap_{side}", 0.09, 0.09, (0.74 * sx, -0.09, 1.08), mats["leather"], collection, vertices=8, rotation=(math.radians(8), 0, math.radians(12 * sx)), bevel_width=0.006)
        hand = sphere(f"Player_Gloved_Hand_{side}", 1.0, (0.105, 0.075, 0.13), (0.75 * sx, -0.12, 0.92), mats["leather"], collection, segments=8, rings=4)
        thumb = cube(f"Player_Glove_Thumb_{side}", (0.045, 0.055, 0.075), (0.68 * sx, -0.15, 0.94), mats["leather"], collection, rotation=(0, 0, math.radians(18 * sx)), bevel_width=0.01)
        knuckle = cube(f"Player_Glove_Knuckles_{side}", (0.13, 0.025, 0.035), (0.75 * sx, -0.185, 0.95), mats["dark_leather"], collection, bevel_width=0.008)
        shoulder_pad = sphere(f"Player_Shoulder_LeatherPad_{side}", 1.0, (0.18, 0.12, 0.10), (0.40 * sx, -0.05, 2.03), mats["leather"], collection, segments=8, rings=4)
        parent_keep_transform(upper_arm, controls[f"shoulder_{side}"])
        parent_keep_transform(shoulder_pad, controls[f"shoulder_{side}"])
        parent_keep_transform(cuff, controls[f"elbow_{side}"])
        parent_keep_transform(forearm, controls[f"elbow_{side}"])
        parent_keep_transform(wrist_band, controls[f"wrist_{side}"])
        parent_keep_transform(hand, controls[f"wrist_{side}"])
        parent_keep_transform(thumb, controls[f"wrist_{side}"])
        parent_keep_transform(knuckle, controls[f"wrist_{side}"])

        thigh = limb_segment(f"Player_Thigh_{side}", Vector((0.22 * sx, 0.0, 1.13)), Vector((0.27 * sx, -0.01, 0.58)), 0.15, 0.135, mats["pants"], collection)
        knee_patch = cube(f"Player_KneePatch_{side}", (0.20, 0.05, 0.15), (0.28 * sx, -0.15, 0.66), mats["dark_leather"], collection, rotation=(math.radians(6), 0, 0), bevel_width=0.012)
        shin = limb_segment(f"Player_Shin_{side}", Vector((0.27 * sx, -0.01, 0.55)), Vector((0.30 * sx, -0.03, 0.20)), 0.125, 0.11, mats["pants"], collection)
        boot = cube(f"Player_Boot_{side}", (0.28, 0.42, 0.18), (0.30 * sx, -0.12, 0.10), mats["boot"], collection, rotation=(0, 0, math.radians(2 * sx)), bevel_width=0.025)
        boot_cuff = cube(f"Player_Boot_Cuff_{side}", (0.28, 0.22, 0.16), (0.29 * sx, -0.03, 0.28), mats["leather"], collection, bevel_width=0.018)
        boot_strap = cube(f"Player_Boot_Strap_{side}", (0.32, 0.24, 0.05), (0.29 * sx, -0.04, 0.36), mats["dark_leather"], collection, bevel_width=0.008)
        boot_buckle = cube(f"Player_Boot_Buckle_{side}", (0.10, 0.045, 0.07), (0.39 * sx, -0.16, 0.36), mats["metal"], collection, bevel_width=0.005)
        parent_keep_transform(thigh, controls[f"hip_{side}"])
        parent_keep_transform(knee_patch, controls[f"knee_{side}"])
        parent_keep_transform(shin, controls[f"knee_{side}"])
        parent_keep_transform(boot, controls[f"ankle_{side}"])
        parent_keep_transform(boot_cuff, controls[f"ankle_{side}"])
        parent_keep_transform(boot_strap, controls[f"ankle_{side}"])
        parent_keep_transform(boot_buckle, controls[f"ankle_{side}"])

        strap_obj = cube(f"Player_Backpack_Strap_{side}", (0.11, 0.06, 0.72), (0.31 * sx, -0.18, 1.76), mats["leather"], collection, rotation=(0, math.radians(10 * sx), 0), bevel_width=0.01)
        strap_buckle = cube(f"Player_Strap_Buckle_{side}", (0.13, 0.045, 0.11), (0.34 * sx, -0.255, 1.71), mats["metal"], collection, bevel_width=0.006)
        parent_keep_transform(strap_obj, spine)
        parent_keep_transform(strap_buckle, spine)

    # Small low-poly cloth facets on cap and pants, modeled as broad panels rather than thin decorative strips.
    for i in range(9):
        x = rng.uniform(-0.30, 0.30)
        y = rng.uniform(-0.13, 0.16)
        z = rng.uniform(3.06, 3.21)
        facet = cube(f"Player_Cap_Facet_{i + 1:02d}", (rng.uniform(0.07, 0.14), 0.012, rng.uniform(0.025, 0.05)), (x, y, z), mats["cap_dark"], collection, rotation=(0, 0, rng.uniform(-0.5, 0.5)), bevel_width=0.0)
        parent_keep_transform(facet, head_ctrl)

    bpy.context.scene["Player_Adventurer_Rig_Notes"] = (
        "Modular FK-friendly model: rotate Rig_*_FK empties for blocking animation. "
        "Meshes are separated at head, spine, shoulders, elbows, wrists, hips, knees, ankles, backpack, cap and accessories."
    )

    return {
        "objects": len(collection.objects),
        "blend": str(BLEND_PATH),
        "preview": str(PREVIEW_PATH),
        "rig_note": bpy.context.scene["Player_Adventurer_Rig_Notes"],
    }


def configure_scene() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 96
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1500

    world = scene.world or bpy.data.worlds.new("Player_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.027, 0.03, 1.0)
        bg.inputs[1].default_value = 0.75

    if "Camera" not in bpy.data.objects:
        bpy.ops.object.camera_add()
    camera = bpy.data.objects["Camera"]
    camera.location = (2.2, -5.0, 2.15)
    direction = Vector((0.0, -0.02, 1.65)) - Vector(camera.location)
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 56
    bpy.context.scene.camera = camera

    if "Light" in bpy.data.objects:
        light = bpy.data.objects["Light"]
        light.location = (-2.5, -4.0, 5.2)
        light.data.energy = 650
    else:
        bpy.ops.object.light_add(type="AREA", location=(-2.5, -4.0, 5.2))
        light = bpy.context.active_object
        light.name = "Light"
        light.data.energy = 650
        light.data.size = 4.0

    bpy.ops.object.light_add(type="POINT", location=(2.3, -3.0, 2.9))
    fill = bpy.context.active_object
    fill.name = "Player_Face_Fill_Light"
    fill.data.energy = 85


def create_basic_animations() -> None:
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 250
    scene.render.fps = 24

    for marker in list(scene.timeline_markers):
        scene.timeline_markers.remove(marker)
    for name, frame in (("Idle", 1), ("Walk", 80), ("Jump", 140), ("Wave", 200)):
        scene.timeline_markers.new(name, frame=frame)

    names = [
        "Rig_Player_Root_FK",
        "Rig_Pelvis_FK",
        "Rig_Spine_FK",
        "Rig_Head_FK",
        "Rig_Backpack_FK",
        "Rig_Shoulder_L_FK",
        "Rig_Shoulder_R_FK",
        "Rig_Elbow_L_FK",
        "Rig_Elbow_R_FK",
        "Rig_Wrist_L_FK",
        "Rig_Wrist_R_FK",
        "Rig_Hip_L_FK",
        "Rig_Hip_R_FK",
        "Rig_Knee_L_FK",
        "Rig_Knee_R_FK",
        "Rig_Ankle_L_FK",
        "Rig_Ankle_R_FK",
    ]
    controls = {name: bpy.data.objects[name] for name in names if name in bpy.data.objects}
    base_loc = {name: controls[name].location.copy() for name in controls}

    for obj in controls.values():
        obj.rotation_mode = "XYZ"
        obj.animation_data_clear()

    def key(name: str, frame: int, loc: tuple[float, float, float] | None = None, rot: tuple[float, float, float] | None = None) -> None:
        obj = controls[name]
        if loc is not None:
            obj.location = Vector(base_loc[name]) + Vector(loc)
            obj.keyframe_insert(data_path="location", frame=frame)
        if rot is not None:
            obj.rotation_euler = Euler(tuple(math.radians(value) for value in rot), "XYZ")
            obj.keyframe_insert(data_path="rotation_euler", frame=frame)

    def neutral(frame: int) -> None:
        for name in controls:
            key(name, frame, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))

    # Idle: subtle breathing/balance loop.
    for frame, lift, sway in ((1, 0.0, 0.0), (30, 0.025, 1.2), (60, 0.0, 0.0)):
        neutral(frame)
        key("Rig_Pelvis_FK", frame, (0.0, 0.0, lift), (0.0, 0.0, sway * 0.35))
        key("Rig_Spine_FK", frame, (0.0, 0.0, 0.0), (sway * 0.25, 0.0, -sway * 0.20))
        key("Rig_Head_FK", frame, (0.0, 0.0, 0.0), (-sway * 0.18, 0.0, sway * 0.28))
        key("Rig_Backpack_FK", frame, (0.0, 0.0, lift * 0.35), (-sway * 0.20, 0.0, 0.0))

    # Walk: in-place loop with opposing arms/legs.
    walk_frames = [
        (80, 0.0, 0.0, 0.0),
        (90, 11.0, -11.0, 0.022),
        (100, 0.0, 0.0, 0.0),
        (110, -11.0, 11.0, 0.022),
        (120, 0.0, 0.0, 0.0),
    ]
    for frame, left, right, bob in walk_frames:
        neutral(frame)
        key("Rig_Pelvis_FK", frame, (0.0, 0.0, bob), (0.0, 0.0, left * 0.10))
        key("Rig_Spine_FK", frame, (0.0, 0.0, 0.0), (0.0, 0.0, -left * 0.08))
        key("Rig_Hip_L_FK", frame, rot=(left, 0.0, 0.0))
        key("Rig_Hip_R_FK", frame, rot=(right, 0.0, 0.0))
        key("Rig_Knee_L_FK", frame, rot=(-max(left, 0.0) * 0.55, 0.0, 0.0))
        key("Rig_Knee_R_FK", frame, rot=(-max(right, 0.0) * 0.55, 0.0, 0.0))
        key("Rig_Ankle_L_FK", frame, rot=(-left * 0.35, 0.0, 0.0))
        key("Rig_Ankle_R_FK", frame, rot=(-right * 0.35, 0.0, 0.0))
        key("Rig_Shoulder_L_FK", frame, rot=(right * 0.85, 0.0, 0.0))
        key("Rig_Shoulder_R_FK", frame, rot=(left * 0.85, 0.0, 0.0))
        key("Rig_Elbow_L_FK", frame, rot=(abs(right) * 0.35, 0.0, -4.0))
        key("Rig_Elbow_R_FK", frame, rot=(abs(left) * 0.35, 0.0, 4.0))
        key("Rig_Head_FK", frame, rot=(-bob * 30.0, 0.0, left * 0.05))
        key("Rig_Backpack_FK", frame, rot=(right * 0.12, 0.0, left * 0.08))

    # Jump: crouch, lift, land.
    jump_keys = [
        (140, 0.0, 0.0, 0.0, 0.0),
        (148, -0.12, 16.0, 22.0, -10.0),
        (162, 0.36, -8.0, -10.0, 14.0),
        (174, -0.05, 10.0, 16.0, -6.0),
        (188, 0.0, 0.0, 0.0, 0.0),
    ]
    for frame, root_z, hip, knee, arm in jump_keys:
        neutral(frame)
        key("Rig_Player_Root_FK", frame, (0.0, 0.0, root_z), (0.0, 0.0, 0.0))
        key("Rig_Pelvis_FK", frame, (0.0, 0.0, -0.03 if root_z < 0.0 else 0.02), (hip * 0.12, 0.0, 0.0))
        key("Rig_Hip_L_FK", frame, rot=(hip, 0.0, 0.0))
        key("Rig_Hip_R_FK", frame, rot=(hip, 0.0, 0.0))
        key("Rig_Knee_L_FK", frame, rot=(-knee, 0.0, 0.0))
        key("Rig_Knee_R_FK", frame, rot=(-knee, 0.0, 0.0))
        key("Rig_Shoulder_L_FK", frame, rot=(arm, 0.0, -4.0))
        key("Rig_Shoulder_R_FK", frame, rot=(arm, 0.0, 4.0))
        key("Rig_Elbow_L_FK", frame, rot=(6.0 if arm else 0.0, 0.0, -2.0))
        key("Rig_Elbow_R_FK", frame, rot=(6.0 if arm else 0.0, 0.0, 2.0))
        key("Rig_Backpack_FK", frame, rot=(-arm * 0.08, 0.0, 0.0))

    # Wave: right arm raises and waves, body/head reacts slightly.
    wave_frames = [
        (200, 0.0, 0.0, 0.0),
        (210, 22.0, 6.0, -10.0),
        (220, 30.0, 8.0, 12.0),
        (230, 26.0, 6.0, -12.0),
        (240, 14.0, 4.0, 0.0),
        (250, 0.0, 0.0, 0.0),
    ]
    for frame, shoulder, elbow, wrist_z in wave_frames:
        neutral(frame)
        key("Rig_Shoulder_R_FK", frame, rot=(0.0, shoulder, 12.0 if shoulder else 0.0))
        key("Rig_Elbow_R_FK", frame, rot=(elbow, 0.0, 8.0))
        key("Rig_Wrist_R_FK", frame, rot=(0.0, 0.0, wrist_z))
        key("Rig_Shoulder_L_FK", frame, rot=(4.0, 0.0, -4.0))
        key("Rig_Head_FK", frame, rot=(0.0, 0.0, 4.0))
        key("Rig_Spine_FK", frame, rot=(0.0, 0.0, 2.0))

    for obj in controls.values():
        if not obj.animation_data or not obj.animation_data.action:
            continue
        obj.animation_data.action.name = f"Player_BasicTimeline_{obj.name}"

    scene["Player_Adventurer_Animation_Notes"] = (
        "Timeline markers: Idle 1-60, Walk 80-120, Jump 140-188, Wave 200-250. "
        "Animations are keyed on Rig_*_FK controls so the modular meshes remain editable."
    )


def bind_modular_meshes_to_armature() -> dict[str, int]:
    arm = bpy.data.objects["Rig_Adventurer_Armature_Reference"]
    world = arm.matrix_world.copy()
    arm.parent = None
    arm.matrix_world = world
    arm.show_in_front = True

    def bind(obj: bpy.types.Object, bone_name: str) -> None:
        world_matrix = obj.matrix_world.copy()
        obj.parent = arm
        obj.parent_type = "BONE"
        obj.parent_bone = bone_name
        obj.matrix_world = world_matrix

    def bind_many(prefixes: tuple[str, ...], bone_name: str) -> int:
        count = 0
        for obj in bpy.data.objects:
            if obj.name.startswith(prefixes):
                bind(obj, bone_name)
                count += 1
        return count

    bound = 0
    bound += bind_many(
        (
            "Player_Head",
            "Player_Nose",
            "Player_Ear",
            "Player_Eye",
            "Player_Eyebrow",
            "Player_Smile",
            "Player_Cap",
            "Player_Hair",
        ),
        "head",
    )
    bound += bind_many(("Player_Neck",), "neck")
    bound += bind_many(
        (
            "Player_Blue_Shirt_Torso",
            "Player_Leather_Vest",
            "Player_Torso_Shirt_Vest_Decal",
            "Player_Crossbody_Strap",
            "Player_Backpack_Strap",
            "Player_Strap_Buckle",
        ),
        "spine",
    )
    bound += bind_many(("Player_Belt", "Player_Belt_Buckle", "Player_Belt_Pouch", "Player_Belt_Tool_Loop"), "pelvis")
    bound += bind_many(("Player_Backpack", "Player_Bedroll"), "backpack")

    for side in ("L", "R"):
        bound += bind_many((f"Player_UpperArm_{side}", f"Player_Shoulder_LeatherPad_{side}"), f"upper_arm.{side}")
        bound += bind_many((f"Player_Sleeve_Cuff_{side}", f"Player_Forearm_{side}", f"Player_Wrist_Wrap_{side}"), f"forearm.{side}")
        bound += bind_many((f"Player_Gloved_Hand_{side}", f"Player_Glove_Thumb_{side}", f"Player_Glove_Knuckles_{side}"), f"hand.{side}")
        bound += bind_many((f"Player_Thigh_{side}",), f"thigh.{side}")
        bound += bind_many((f"Player_KneePatch_{side}", f"Player_Shin_{side}"), f"shin.{side}")
        bound += bind_many((f"Player_Boot_{side}", f"Player_Boot_Cuff_{side}", f"Player_Boot_Strap_{side}", f"Player_Boot_Buckle_{side}"), f"foot.{side}")

    hidden_controls = 0
    for obj in bpy.data.objects:
        if obj.name.startswith("Rig_") and obj != arm:
            obj.hide_viewport = True
            obj.hide_render = True
            obj.animation_data_clear()
            hidden_controls += 1

    bpy.context.scene["Player_Adventurer_Rig_Notes"] = (
        "Rigid modular character bound to real armature bones. Bone heads are placed at the main joints "
        "(shoulder, elbow, wrist, hip, knee, ankle, neck). Player_* meshes are parented to their matching bones; "
        "animations are keyed on pose bones, not FK empties."
    )
    return {"bound_objects": bound, "hidden_legacy_controls": hidden_controls}


def create_right_hand_socket(collection: bpy.types.Collection) -> bpy.types.Object:
    arm = bpy.data.objects["Rig_Adventurer_Armature_Reference"]
    socket = bpy.data.objects.new("RightHandSocket", None)
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 0.11
    collection.objects.link(socket)
    socket.matrix_world = arm.matrix_world @ arm.data.bones["hand.R"].matrix_local
    socket.location += Vector((0.0, -0.06, 0.0))
    world = socket.matrix_world.copy()
    socket.parent = arm
    socket.parent_type = "BONE"
    socket.parent_bone = "hand.R"
    socket.matrix_world = world
    socket["GodotUsage"] = "Attach external weapon/item scene to this socket after import."
    return socket


def create_bone_animations() -> None:
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 500
    scene.render.fps = 24

    for marker in list(scene.timeline_markers):
        scene.timeline_markers.remove(marker)
    for name, frame in (
        ("Idle", 1),
        ("Walk", 80),
        ("Jump", 140),
        ("Wave", 200),
        ("hold_pickaxe", 260),
        ("mine_pickaxe", 280),
        ("attack_sword", 360),
        ("use_item", 430),
    ):
        scene.timeline_markers.new(name, frame=frame)

    arm = bpy.data.objects["Rig_Adventurer_Armature_Reference"]
    arm.animation_data_clear()
    arm_base_location = arm.location.copy()
    for pbone in arm.pose.bones:
        pbone.rotation_mode = "XYZ"
        pbone.rotation_euler = (0.0, 0.0, 0.0)
        pbone.location = (0.0, 0.0, 0.0)

    def pose(frame: int, rotations: dict[str, tuple[float, float, float]], root_z: float = 0.0) -> None:
        scene.frame_set(frame)
        arm.location = arm_base_location + Vector((0.0, 0.0, root_z))
        arm.keyframe_insert(data_path="location", frame=frame)
        for pbone in arm.pose.bones:
            pbone.rotation_euler = (0.0, 0.0, 0.0)
            pbone.location = (0.0, 0.0, 0.0)
            pbone.keyframe_insert(data_path="rotation_euler", frame=frame)
        for bone_name, rot in rotations.items():
            pbone = arm.pose.bones[bone_name]
            pbone.rotation_euler = Euler(tuple(math.radians(value) for value in rot), "XYZ")
            pbone.keyframe_insert(data_path="rotation_euler", frame=frame)

    def side_pairs(left: float, right: float, arm_scale: float = 0.75) -> dict[str, tuple[float, float, float]]:
        return {
            "thigh.L": (left, 0.0, 0.0),
            "thigh.R": (right, 0.0, 0.0),
            "shin.L": (-max(left, 0.0) * 0.45, 0.0, 0.0),
            "shin.R": (-max(right, 0.0) * 0.45, 0.0, 0.0),
            "foot.L": (-left * 0.25, 0.0, 0.0),
            "foot.R": (-right * 0.25, 0.0, 0.0),
            "upper_arm.L": (right * arm_scale, 0.0, -2.0),
            "upper_arm.R": (left * arm_scale, 0.0, 2.0),
            "forearm.L": (abs(right) * 0.20, 0.0, -1.5),
            "forearm.R": (abs(left) * 0.20, 0.0, 1.5),
        }

    # Idle: readable breathing cycle with chest lift, shoulder release and a slight backpack lag.
    pose(1, {})
    pose(
        18,
        {
            "pelvis": (-0.55, 0.0, 0.0),
            "spine": (2.0, 0.0, 0.0),
            "neck": (-0.35, 0.0, 0.0),
            "head": (-0.5, 0.0, 0.0),
            "upper_arm.L": (-0.85, 0.0, 0.0),
            "upper_arm.R": (-0.85, 0.0, 0.0),
            "backpack": (-0.75, 0.0, 0.0),
        },
        root_z=0.022,
    )
    pose(
        36,
        {
            "pelvis": (0.35, 0.0, 0.0),
            "spine": (-1.15, 0.0, 0.0),
            "neck": (0.22, 0.0, 0.0),
            "head": (0.28, 0.0, 0.0),
            "upper_arm.L": (0.38, 0.0, 0.0),
            "upper_arm.R": (0.38, 0.0, 0.0),
            "backpack": (0.5, 0.0, 0.0),
        },
        root_z=-0.012,
    )
    pose(60, {})

    # Walk: conservative in-place cycle, all rotations through leg/arm bones.
    for frame, left, right in ((80, 0.0, 0.0), (90, 16.0, -16.0), (100, 0.0, 0.0), (110, -16.0, 16.0), (120, 0.0, 0.0)):
        rotations = side_pairs(left, right)
        rotations.update({"pelvis": (0.0, 0.0, left * 0.08), "spine": (0.0, 0.0, -left * 0.06), "head": (0.0, 0.0, left * 0.04), "backpack": (right * 0.08, 0.0, left * 0.05)})
        pose(frame, rotations)

    # Jump: compact crouch, vertical lift, compact landing.
    for frame, root_z, hip, knee, arm_x, arm_z in (
        (140, 0.0, 0.0, 0.0, 0.0, 0.0),
        (148, -0.06, 10.0, 14.0, -6.0, 6.0),
        (158, 0.40, -3.0, 2.0, 8.0, 34.0),
        (168, 0.28, 2.0, 4.0, 4.0, 24.0),
        (178, -0.035, 8.0, 12.0, -3.0, 8.0),
        (188, 0.0, 0.0, 0.0, 0.0, 0.0),
    ):
        pose(
            frame,
            {
                "pelvis": (hip * 0.10, 0.0, 0.0),
                "thigh.L": (hip, 0.0, 0.0),
                "thigh.R": (hip, 0.0, 0.0),
                "shin.L": (-knee * 0.55, 0.0, 0.0),
                "shin.R": (-knee * 0.55, 0.0, 0.0),
                "foot.L": (-hip * 0.15, 0.0, 0.0),
                "foot.R": (-hip * 0.15, 0.0, 0.0),
                "upper_arm.L": (arm_x, 0.0, arm_z),
                "upper_arm.R": (arm_x, 0.0, -arm_z),
                "forearm.L": (4.0 if arm_z else 0.0, 0.0, arm_z * 0.10),
                "forearm.R": (4.0 if arm_z else 0.0, 0.0, -arm_z * 0.10),
                "hand.L": (0.0, 0.0, arm_z * 0.08),
                "hand.R": (0.0, 0.0, -arm_z * 0.08),
                "backpack": (-arm_x * 0.08, 0.0, 0.0),
            },
            root_z=root_z,
        )

    # Wave: small right-hand wave, keyed on shoulder/forearm/hand bones.
    for frame, shoulder_x, elbow_x, wrist_z in ((200, 0.0, 0.0, 0.0), (210, 30.0, 10.0, -10.0), (220, 42.0, 14.0, 12.0), (230, 34.0, 10.0, -12.0), (240, 16.0, 4.0, 0.0), (250, 0.0, 0.0, 0.0)):
        pose(
            frame,
            {
                "upper_arm.R": (shoulder_x, 0.0, 4.0 if shoulder_x else 0.0),
                "forearm.R": (elbow_x, 0.0, 4.0 if elbow_x else 0.0),
                "hand.R": (0.0, 0.0, wrist_z),
                "upper_arm.L": (2.0, 0.0, -2.0),
                "head": (0.0, 0.0, -2.0),
                "spine": (0.0, 0.0, -1.0),
            },
        )

    # hold_pickaxe: the external pickaxe can rest over the right shoulder while the hand grips its shaft.
    for frame, rotations in (
        (260, {"upper_arm.R": (-58.0, 32.0, -58.0), "forearm.R": (-98.0, -44.0, -64.0), "hand.R": (0.0, 0.0, 6.0), "spine": (-1.0, 0.0, -2.0), "head": (1.0, 0.0, 1.0)}),
        (270, {"upper_arm.R": (-57.0, 32.0, -57.0), "forearm.R": (-97.0, -44.0, -63.0), "hand.R": (0.0, 0.0, 6.0), "spine": (-1.5, 0.0, -2.0), "head": (1.2, 0.0, 1.0)}),
        (278, {"upper_arm.R": (-58.0, 32.0, -58.0), "forearm.R": (-98.0, -44.0, -64.0), "hand.R": (0.0, 0.0, 6.0), "spine": (-1.0, 0.0, -2.0), "head": (1.0, 0.0, 1.0)}),
    ):
        pose(frame, rotations)

    # mine_pickaxe: start from shoulder carry, raise both hands, then strike down and forward toward -Y.
    for frame, rotations in (
        (280, {"upper_arm.R": (-58.0, 32.0, -58.0), "forearm.R": (-98.0, -44.0, -64.0), "hand.R": (0.0, 0.0, 6.0), "spine": (-1.0, 0.0, -2.0), "head": (1.0, 0.0, 1.0)}),
        (294, {"upper_arm.R": (-6.0, 0.0, 52.0), "forearm.R": (60.0, 0.0, 10.0), "hand.R": (0.0, 0.0, 8.0), "upper_arm.L": (-6.0, 0.0, -52.0), "forearm.L": (60.0, 0.0, -10.0), "hand.L": (0.0, 0.0, -8.0), "spine": (-4.0, 0.0, 0.0), "head": (3.0, 0.0, 0.0)}),
        (308, {"upper_arm.R": (-2.0, 0.0, 56.0), "forearm.R": (62.0, 0.0, 10.0), "hand.R": (0.0, 0.0, 8.0), "upper_arm.L": (-2.0, 0.0, -56.0), "forearm.L": (62.0, 0.0, -10.0), "hand.L": (0.0, 0.0, -8.0), "spine": (-5.0, 0.0, 0.0), "head": (3.5, 0.0, 0.0)}),
        (322, {"upper_arm.R": (-55.0, 0.0, 10.0), "forearm.R": (-18.0, 0.0, 4.0), "hand.R": (0.0, 0.0, -10.0), "upper_arm.L": (-48.0, 0.0, -10.0), "forearm.L": (-12.0, 0.0, -4.0), "hand.L": (0.0, 0.0, 10.0), "spine": (7.0, 0.0, 0.0), "head": (-4.0, 0.0, 0.0)}),
        (336, {"upper_arm.R": (-42.0, 0.0, 14.0), "forearm.R": (-8.0, 0.0, 4.0), "hand.R": (0.0, 0.0, -6.0), "upper_arm.L": (-36.0, 0.0, -14.0), "forearm.L": (-6.0, 0.0, -4.0), "hand.L": (0.0, 0.0, 6.0), "spine": (3.5, 0.0, 0.0), "head": (-2.0, 0.0, 0.0)}),
        (350, {"upper_arm.R": (-58.0, 32.0, -58.0), "forearm.R": (-98.0, -44.0, -64.0), "hand.R": (0.0, 0.0, 6.0), "spine": (-1.0, 0.0, -2.0), "head": (1.0, 0.0, 1.0)}),
    ):
        pose(frame, rotations)

    # attack_sword: one-handed diagonal slash, lifting on the right and cutting forward across -Y.
    for frame, rotations in (
        (360, {"upper_arm.R": (4.0, 0.0, 8.0), "forearm.R": (8.0, 0.0, 4.0), "hand.R": (0.0, 0.0, 0.0)}),
        (372, {"upper_arm.R": (8.0, 0.0, 46.0), "forearm.R": (32.0, 0.0, 10.0), "hand.R": (0.0, 0.0, 14.0), "spine": (-2.0, 0.0, -2.0), "head": (1.0, 0.0, 1.0)}),
        (386, {"upper_arm.R": (-52.0, 0.0, 6.0), "forearm.R": (-10.0, 0.0, -6.0), "hand.R": (0.0, 0.0, -22.0), "spine": (4.0, 0.0, 2.0), "head": (-2.0, 0.0, -1.0), "upper_arm.L": (4.0, 0.0, -4.0)}),
        (400, {"upper_arm.R": (-28.0, 0.0, 8.0), "forearm.R": (-4.0, 0.0, -2.0), "hand.R": (0.0, 0.0, -10.0), "spine": (2.0, 0.0, 1.0), "head": (-1.0, 0.0, 0.0)}),
        (414, {"upper_arm.R": (4.0, 0.0, 8.0), "forearm.R": (8.0, 0.0, 4.0), "hand.R": (0.0, 0.0, 0.0)}),
    ):
        pose(frame, rotations)

    # use_item: bring the right hand socket up toward the chest/face and lower it again.
    for frame, rotations in (
        (430, {"upper_arm.R": (4.0, 0.0, 4.0), "forearm.R": (6.0, 0.0, 2.0), "hand.R": (0.0, 0.0, 0.0)}),
        (444, {"upper_arm.R": (28.0, 0.0, 8.0), "forearm.R": (38.0, 0.0, 6.0), "hand.R": (0.0, 0.0, 6.0), "head": (5.0, 0.0, 2.0), "spine": (-1.0, 0.0, 1.0)}),
        (460, {"upper_arm.R": (30.0, 0.0, 8.0), "forearm.R": (42.0, 0.0, 8.0), "hand.R": (0.0, 0.0, -6.0), "head": (7.0, 0.0, 2.0), "spine": (-1.0, 0.0, 1.0)}),
        (472, {"upper_arm.R": (12.0, 0.0, 5.0), "forearm.R": (18.0, 0.0, 3.0), "hand.R": (0.0, 0.0, 0.0)}),
        (480, {}),
    ):
        pose(frame, rotations)

    if arm.animation_data and arm.animation_data.action:
        arm.animation_data.action.name = "Player_Basic_Bone_Animations"

    scene["Player_Adventurer_Animation_Notes"] = (
        "Timeline markers: Idle 1-60, Walk 80-120, Jump 140-188, Wave 200-250, "
        "hold_pickaxe 260-278, mine_pickaxe 280-350, attack_sword 360-414, use_item 430-480. "
        "Animations are keyed on Rig_Adventurer_Armature_Reference pose bones. No limb mesh uses FK-empty displacement."
    )
    scene.frame_set(1)


def save_and_preview() -> None:
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


result = build_character()
binding_result = bind_modular_meshes_to_armature()
create_right_hand_socket(bpy.data.collections[COLLECTION_NAME])
configure_scene()
create_bone_animations()
save_and_preview()
result["binding"] = binding_result
