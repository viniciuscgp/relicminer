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
MODEL_DIR = ROOT / "models" / "fence"
SOURCE_DIR = MODEL_DIR / "source"
BLEND_PATH = SOURCE_DIR / "Fence.blend"
GLB_PATH = MODEL_DIR / "Fence.glb"
WOOD_TEX_PATH = MODEL_DIR / "Fence_wood_albedo.png"
METAL_TEX_PATH = MODEL_DIR / "Fence_metal_albedo.png"
SEED = 9321


def ensure_dirs() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)


def delete_previous() -> None:
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith("Fence_") or obj.name == "RelicMiner_Fence":
            bpy.data.objects.remove(obj, do_unlink=True)

    collection = bpy.data.collections.get("RelicMiner_Fence")
    if collection:
        for obj in list(collection.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(collection)

    for data_group in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for block in list(data_group):
            if block.users == 0 and block.name.startswith("Fence"):
                data_group.remove(block)


def make_collection() -> bpy.types.Collection:
    collection = bpy.data.collections.new("RelicMiner_Fence")
    bpy.context.scene.collection.children.link(collection)
    return collection


def link_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    collection.objects.link(obj)
    for other in list(obj.users_collection):
        if other != collection:
            other.objects.unlink(obj)


def create_wood_texture() -> bpy.types.Image:
    size = 512
    rng = random.Random(SEED)
    image = bpy.data.images.new("Fence_wood_albedo", width=size, height=size, alpha=True)
    bands = [(rng.random(), rng.uniform(-0.22, 0.22), rng.uniform(0.18, 0.58)) for _ in range(26)]
    pixels: list[float] = []

    for y in range(size):
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            grain = 0.0
            for center, drift, strength in bands:
                wave = center + math.sin((u * 8.0 + drift) * math.pi * 2.0) * 0.015
                grain += max(0.0, 1.0 - abs(v - wave) * 42.0) * strength
            ring = math.sin((u * 17.0 + v * 2.7) * math.pi * 2.0) * 0.035
            noise = rng.uniform(-0.025, 0.025)
            shade = grain * 0.17 + ring + noise
            r = max(0.25, min(0.78, 0.55 + shade))
            g = max(0.14, min(0.48, 0.33 + shade * 0.62))
            b = max(0.06, min(0.24, 0.13 + shade * 0.32))
            pixels.extend((r, g, b, 1.0))

    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(WOOD_TEX_PATH)
    image.file_format = "PNG"
    image.save()
    return image


def create_flat_texture(name: str, path: Path, color: tuple[float, float, float, float]) -> bpy.types.Image:
    image = bpy.data.images.new(name, width=8, height=8, alpha=True)
    image.pixels.foreach_set(list(color) * 64)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    return image


def texture_material(name: str, image: bpy.types.Image, roughness: float, specular: float) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        if node.name != "Material Output":
            nodes.remove(node)

    output = nodes["Material Output"]
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = specular
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def color_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.75) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.22
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)


def smart_uv(obj: bpy.types.Object, angle_limit: float = 66.0) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle_limit), island_margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def apply_bevel(obj: bpy.types.Object, width: float, segments: int = 1) -> None:
    modifier = obj.modifiers.new("Fence_low_poly_bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def cube_obj(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    rotation_z: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=(0.0, 0.0, rotation_z))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    apply_bevel(obj, 0.035, 1)
    smart_uv(obj)
    link_to_collection(obj, collection)
    return obj


def make_post(
    name: str,
    x: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    lean_deg: float,
) -> bpy.types.Object:
    obj = cube_obj(name, (0.42, 0.42, 1.62), (x, 0.0, 0.81), material, collection, math.radians(lean_deg))
    obj.rotation_euler.rotate_axis("Y", math.radians(-lean_deg * 0.45))
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.select_set(False)

    cube_obj(f"{name}_Cap", (0.39, 0.39, 0.13), (x, 0.0, 1.665), material, collection, math.radians(lean_deg))
    return obj


def make_rail_mesh(
    name: str,
    z_center: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    slope: float,
) -> bpy.types.Object:
    rng = random.Random(SEED + int(z_center * 1000))
    length = 3.48
    half_y = 0.145
    half_z = 0.13
    xs = [-length * 0.5, -1.1, -0.35, 0.42, 1.17, length * 0.5]
    verts: list[tuple[float, float, float]] = []
    for i, x in enumerate(xs):
        wave = math.sin((i / (len(xs) - 1)) * math.pi) * 0.035
        twist = rng.uniform(-0.015, 0.015)
        center_z = z_center + x * slope + wave
        verts.extend(
            [
                (x, -half_y + rng.uniform(-0.01, 0.008), center_z - half_z + twist),
                (x, half_y + rng.uniform(-0.008, 0.01), center_z - half_z - twist),
                (x, half_y + rng.uniform(-0.008, 0.01), center_z + half_z + twist),
                (x, -half_y + rng.uniform(-0.01, 0.008), center_z + half_z - twist),
            ]
        )

    faces: list[tuple[int, ...]] = []
    for i in range(len(xs) - 1):
        a = i * 4
        b = (i + 1) * 4
        faces.extend(
            [
                (a + 0, b + 0, b + 1, a + 1),
                (a + 1, b + 1, b + 2, a + 2),
                (a + 2, b + 2, b + 3, a + 3),
                (a + 3, b + 3, b + 0, a + 0),
            ]
        )
    faces.append((0, 1, 2, 3))
    last = (len(xs) - 1) * 4
    faces.append((last, last + 3, last + 2, last + 1))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    apply_bevel(obj, 0.026, 1)
    smart_uv(obj)
    return obj


def make_front_strip(
    name: str,
    x: float,
    z: float,
    length: float,
    height: float,
    y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    angle: float = 0.0,
) -> bpy.types.Object:
    obj = cube_obj(name, (length, 0.012, height), (x, y, z), material, collection, angle)
    apply_bevel(obj, 0.004, 1)
    return obj


def add_wood_marks(collection: bpy.types.Collection, dark: bpy.types.Material, light: bpy.types.Material) -> None:
    rng = random.Random(SEED + 44)
    for rail_index, z in enumerate((1.12, 0.63), start=1):
        for i in range(8):
            x = rng.uniform(-1.45, 1.45)
            length = rng.uniform(0.16, 0.44)
            height = rng.uniform(0.008, 0.018)
            material = light if i == 2 else dark
            mark_z = z + rng.uniform(-0.07, 0.07)
            make_front_strip(
                f"Fence_Rail_{rail_index}_WoodMark_{i + 1:02d}",
                x,
                mark_z,
                length,
                height,
                -0.154,
                material,
                collection,
                rng.uniform(-0.06, 0.06),
            )

    for side, x in (("L", -1.93), ("R", 1.93)):
        for i in range(5):
            make_front_strip(
                f"Fence_Post_{side}_WoodMark_{i + 1:02d}",
                x + rng.uniform(-0.12, 0.12),
                rng.uniform(0.28, 1.47),
                rng.uniform(0.025, 0.045),
                rng.uniform(0.12, 0.34),
                -0.214,
                dark,
                collection,
                rng.uniform(-0.05, 0.05),
            )


def make_bolt(
    name: str,
    x: float,
    z: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=10,
        radius=0.07,
        depth=0.04,
        location=(x, -0.235, z),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.active_object
    obj.name = name
    assign_material(obj, material)
    apply_bevel(obj, 0.008, 1)
    link_to_collection(obj, collection)
    return obj


def configure_scene() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 64

    world = scene.world or bpy.data.worlds.new("Fence_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.94, 0.93, 0.91, 1.0)
        bg.inputs[1].default_value = 0.8

    if "Camera" not in bpy.data.objects:
        bpy.ops.object.camera_add()
    camera = bpy.data.objects["Camera"]
    camera.location = (3.4, -5.0, 2.15)
    target = Vector((0.0, 0.0, 0.86))
    direction = target - Vector(camera.location)
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 34
    scene.camera = camera

    if "Light" in bpy.data.objects:
        light = bpy.data.objects["Light"]
        light.location = (-2.5, -3.5, 4.0)
        light.data.energy = 450
    else:
        bpy.ops.object.light_add(type="AREA", location=(-2.5, -3.5, 4.0))
        light = bpy.context.active_object
        light.name = "Light"
        light.data.energy = 450
        light.data.size = 5.0


def export_asset(collection: bpy.types.Collection) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_yup=True,
    )


def build() -> dict[str, object]:
    ensure_dirs()
    delete_previous()
    collection = make_collection()

    wood_image = create_wood_texture()
    metal_image = create_flat_texture("Fence_metal_albedo", METAL_TEX_PATH, (0.29, 0.27, 0.23, 1.0))
    wood = texture_material("Fence_warm_lowpoly_wood", wood_image, roughness=0.82, specular=0.18)
    metal = texture_material("Fence_dark_iron_bolts", metal_image, roughness=0.68, specular=0.35)
    make_post("Fence_Left_Post", -1.93, wood, collection, -2.0)
    make_post("Fence_Right_Post", 1.93, wood, collection, 1.4)
    make_rail_mesh("Fence_Top_Rail", 1.12, wood, collection, 0.018)
    make_rail_mesh("Fence_Bottom_Rail", 0.63, wood, collection, 0.010)
    for side, x in (("Left", -1.935), ("Right", 1.935)):
        make_bolt(f"Fence_{side}_Top_Bolt", x, 1.12, metal, collection)
        make_bolt(f"Fence_{side}_Bottom_Bolt", x, 0.63, metal, collection)

    empty = bpy.data.objects.new("RelicMiner_Fence", None)
    collection.objects.link(empty)
    for obj in collection.objects:
        if obj != empty:
            obj.parent = empty

    configure_scene()
    export_asset(collection)

    return {
        "objects": len(collection.objects),
        "blend": str(BLEND_PATH),
        "glb": str(GLB_PATH),
        "wood_texture": str(WOOD_TEX_PATH),
        "metal_texture": str(METAL_TEX_PATH),
    }


result = build()
