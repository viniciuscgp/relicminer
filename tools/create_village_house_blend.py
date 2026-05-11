from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Euler


ROOT = Path(__file__).resolve().parents[1]
TEXTURE_DIR = ROOT / "textures" / "generated"
MODEL_DIR = ROOT / "models"
SOURCE_DIR = MODEL_DIR / "source"
BLEND_PATH = SOURCE_DIR / "Village_House_A.blend"
GLB_PATH = MODEL_DIR / "Village_House_A.glb"
SEED = 4172
ROOF_ANGLE = math.radians(33.0)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data_group in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for block in list(data_group):
            if block.users == 0:
                data_group.remove(block)


def load_image(name: str) -> bpy.types.Image:
    return bpy.data.images.load(str(TEXTURE_DIR / name), check_existing=True)


def configure_world() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    world = bpy.data.worlds.new("VillageWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.96, 0.96, 0.98, 1.0)
    bg.inputs[1].default_value = 0.9


def apply_bevel(obj: bpy.types.Object, width: float = 0.028, segments: int = 2) -> None:
    modifier = obj.modifiers.new(name="Bevel", type="BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def smart_uv(obj: bpy.types.Object, angle_limit: float = 66.0) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle_limit), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def set_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)


def create_textured_material(
    name: str,
    image_name: str,
    *,
    roughness: float,
    specular: float = 0.3,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        if node.name not in {"Material Output"}:
            nodes.remove(node)

    output = nodes["Material Output"]
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    tex = nodes.new("ShaderNodeTexImage")
    tex.location = (-320, 80)
    tex.image = load_image(image_name)
    tex.interpolation = "Closest"
    tex.projection = "FLAT"

    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-560, 80)
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 1.0)
    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-780, 80)

    links.new(texcoord.outputs["UV"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = specular

    if emission_strength > 0.0:
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    output.location = (260, 0)
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def cube(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def plane(
    name: str,
    size: tuple[float, float],
    location: tuple[float, float, float],
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_plane_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def gable_mesh(
    name: str,
    width: float,
    thickness: float,
    base_z: float,
    peak_z: float,
    y: float,
) -> bpy.types.Object:
    half_w = width * 0.5
    half_t = thickness * 0.5
    mesh = bpy.data.meshes.new(name)
    verts = [
        (-half_w, y - half_t, base_z),
        (half_w, y - half_t, base_z),
        (0.0, y - half_t, peak_z),
        (-half_w, y + half_t, base_z),
        (half_w, y + half_t, base_z),
        (0.0, y + half_t, peak_z),
    ]
    faces = [
        (0, 1, 2),
        (3, 5, 4),
        (0, 3, 4, 1),
        (1, 4, 5, 2),
        (2, 5, 3, 0),
    ]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def add_parenting(root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        obj.parent = root


def build_house(materials: dict[str, bpy.types.Material]) -> list[bpy.types.Object]:
    rng = random.Random(SEED)
    made: list[bpy.types.Object] = []

    foundation = cube("House_Foundation", (2.92, 2.3, 0.28), (0.0, 0.0, 0.14))
    set_material(foundation, materials["stone"])
    apply_bevel(foundation, 0.02, 2)
    smart_uv(foundation)
    made.append(foundation)

    for index, (x, y) in enumerate(((-1.28, -0.98), (1.28, -0.98), (-1.28, 0.98), (1.28, 0.98)), start=1):
        stone = cube(f"House_CornerStone_{index}", (0.42, 0.42, 0.46), (x, y, 0.23))
        stone.rotation_euler = Euler((0.0, 0.0, math.radians(rng.uniform(-4.0, 4.0))), "XYZ")
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        set_material(stone, materials["stone"])
        apply_bevel(stone, 0.03, 2)
        smart_uv(stone)
        made.append(stone)

    wall_core = cube("House_WallCore", (2.5, 1.88, 2.0), (0.0, 0.0, 1.28))
    set_material(wall_core, materials["plaster"])
    apply_bevel(wall_core, 0.018, 2)
    smart_uv(wall_core)
    made.append(wall_core)

    for idx, y in enumerate((0.95, -0.95), start=1):
        gable = gable_mesh(f"House_Gable_{idx}", 2.48, 0.16, 2.14, 3.1, y)
        set_material(gable, materials["plaster"])
        apply_bevel(gable, 0.012, 2)
        smart_uv(gable)
        made.append(gable)

    timber_specs = [
        ("Timber_Front_Left", (0.18, 0.18, 2.38), (-1.17, 0.96, 1.34), 0.0),
        ("Timber_Front_Right", (0.18, 0.18, 2.38), (1.17, 0.96, 1.34), 0.0),
        ("Timber_Back_Left", (0.18, 0.18, 2.38), (-1.17, -0.96, 1.34), 0.0),
        ("Timber_Back_Right", (0.18, 0.18, 2.38), (1.17, -0.96, 1.34), 0.0),
        ("Timber_Left_Mid", (0.16, 1.7, 0.16), (-1.17, 0.0, 1.55), 0.0),
        ("Timber_Right_Mid", (0.16, 1.7, 0.16), (1.17, 0.0, 1.55), 0.0),
        ("Timber_Front_Mid", (2.0, 0.16, 0.16), (0.0, 0.96, 1.62), 0.0),
        ("Timber_Back_Mid", (2.0, 0.16, 0.16), (0.0, -0.96, 1.62), 0.0),
        ("Timber_Front_Top", (2.2, 0.16, 0.18), (0.0, 0.96, 2.28), 0.0),
        ("Timber_Back_Top", (2.2, 0.16, 0.18), (0.0, -0.96, 2.28), 0.0),
        ("Timber_Left_Top", (0.18, 1.9, 0.18), (-1.17, 0.0, 2.15), 0.0),
        ("Timber_Right_Top", (0.18, 1.9, 0.18), (1.17, 0.0, 2.15), 0.0),
    ]

    for name, size, location, angle in timber_specs:
        obj = cube(name, size, location)
        if angle:
            obj.rotation_euler = Euler((0.0, 0.0, math.radians(angle)), "XYZ")
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        obj.location.x += rng.uniform(-0.012, 0.012)
        obj.location.y += rng.uniform(-0.012, 0.012)
        set_material(obj, materials["wood"])
        apply_bevel(obj, 0.026, 2)
        smart_uv(obj)
        made.append(obj)

    brace_specs = [
        ("Front_Brace_Left", (-0.66, 0.96, 1.86), 42.0),
        ("Front_Brace_Right", (0.66, 0.96, 1.86), -42.0),
        ("Back_Brace_Left", (-0.66, -0.96, 1.86), -42.0),
        ("Back_Brace_Right", (0.66, -0.96, 1.86), 42.0),
    ]
    for name, location, angle in brace_specs:
        obj = cube(name, (0.16, 0.16, 1.16), location)
        obj.rotation_euler = Euler((0.0, math.radians(90.0), math.radians(angle)), "XYZ")
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        set_material(obj, materials["wood"])
        apply_bevel(obj, 0.022, 2)
        smart_uv(obj)
        made.append(obj)

    door_frame = cube("Door_Frame", (1.18, 0.22, 1.78), (0.0, 1.01, 0.95))
    set_material(door_frame, materials["wood"])
    apply_bevel(door_frame, 0.03, 2)
    smart_uv(door_frame)
    made.append(door_frame)

    door_leaf = cube("Door_Leaf", (0.82, 0.12, 1.28), (0.0, 1.065, 0.76))
    set_material(door_leaf, materials["wood"])
    apply_bevel(door_leaf, 0.018, 2)
    smart_uv(door_leaf)
    made.append(door_leaf)

    door_header = cube("Door_Header", (1.38, 0.22, 0.18), (0.0, 1.02, 1.78))
    set_material(door_header, materials["wood"])
    apply_bevel(door_header, 0.02, 2)
    smart_uv(door_header)
    made.append(door_header)

    knob = cube("Door_Knob", (0.08, 0.06, 0.08), (-0.28, 1.12, 0.62))
    set_material(knob, materials["stone"])
    apply_bevel(knob, 0.012, 2)
    smart_uv(knob)
    made.append(knob)

    window_specs = [
        ("Front_Window", (0.58, 0.12, 0.62), (0.0, 1.03, 1.44)),
        ("Side_Window", (0.72, 0.12, 0.58), (1.08, -0.12, 1.28), (0.0, 0.0, math.radians(90.0))),
        ("Gable_Window", (0.46, 0.12, 0.48), (0.0, 1.01, 2.42)),
    ]
    for spec in window_specs:
        if len(spec) == 3:
            name, size, location = spec
            rotation = (0.0, 0.0, 0.0)
        else:
            name, size, location, rotation = spec
        frame = cube(f"{name}_Frame", size, location, rotation)
        set_material(frame, materials["wood"])
        apply_bevel(frame, 0.018, 2)
        smart_uv(frame)
        made.append(frame)

        glass = plane(
            f"{name}_Glass",
            (size[0] * 0.68, size[2] * 0.68),
            (
                location[0] + (0.065 if abs(rotation[2]) > 0.1 else 0.0),
                location[1] + (0.065 if abs(rotation[2]) < 0.1 else 0.0),
                location[2],
            ),
            (math.radians(90.0), 0.0, rotation[2]),
        )
        set_material(glass, materials["lantern"])
        smart_uv(glass)
        made.append(glass)

    shutter_specs = [
        ("Side_Shutter_Left", (0.16, 0.08, 0.56), (1.12, -0.56, 1.28), math.radians(90.0)),
        ("Side_Shutter_Right", (0.16, 0.08, 0.56), (1.12, 0.32, 1.28), math.radians(90.0)),
    ]
    for name, size, location, zrot in shutter_specs:
        shutter = cube(name, size, location, (0.0, 0.0, zrot))
        set_material(shutter, materials["wood"])
        apply_bevel(shutter, 0.016, 2)
        smart_uv(shutter)
        made.append(shutter)

    sign = cube("Front_Sign", (0.38, 0.12, 0.12), (-0.88, 1.0, 1.06))
    peg = cube("Front_Sign_Peg", (0.1, 0.1, 0.34), (-1.02, 0.99, 1.16))
    for obj in (sign, peg):
        set_material(obj, materials["wood"])
        apply_bevel(obj, 0.016, 2)
        smart_uv(obj)
        made.append(obj)

    roof_tiles_left: list[bpy.types.Object] = []
    roof_tiles_right: list[bpy.types.Object] = []
    tile_w = 0.56
    tile_d = 0.42
    tile_t = 0.11
    cols = 4
    rows = 6
    for side, x_sign in (("L", -1), ("R", 1)):
        slope_x = 1.48 * x_sign
        z_top = 3.08
        local_tiles: list[bpy.types.Object] = []
        for row in range(rows):
            for col in range(cols):
                depth = -0.95 + col * 0.56 + (0.15 if row % 2 else 0.0)
                x = x_sign * (0.38 + row * 0.28)
                z = z_top - row * 0.2
                obj = cube(
                    f"RoofTile_{side}_{row}_{col}",
                    (tile_w + rng.uniform(-0.04, 0.04), tile_d + rng.uniform(-0.03, 0.03), tile_t),
                    (x, depth + rng.uniform(-0.02, 0.02), z + rng.uniform(-0.015, 0.015)),
                    (0.0, x_sign * ROOF_ANGLE, math.radians(rng.uniform(-3.0, 3.0))),
                )
                set_material(obj, materials["roof"])
                apply_bevel(obj, 0.03, 2)
                smart_uv(obj)
                local_tiles.append(obj)
                made.append(obj)
        joined = join_objects(f"Roof_{'Left' if x_sign < 0 else 'Right'}", local_tiles)
        set_material(joined, materials["roof"])
        roof_tiles_left.append(joined) if x_sign < 0 else roof_tiles_right.append(joined)

    ridge_tiles: list[bpy.types.Object] = []
    for idx in range(6):
        ridge = cube(
            f"Ridge_{idx}",
            (0.34, 0.46, 0.14),
            (0.0, -1.08 + idx * 0.43, 3.21 + rng.uniform(-0.02, 0.02)),
            (math.radians(90.0), 0.0, math.radians(rng.uniform(-4.0, 4.0))),
        )
        set_material(ridge, materials["roof"])
        apply_bevel(ridge, 0.025, 2)
        smart_uv(ridge)
        ridge_tiles.append(ridge)
        made.append(ridge)

    ridge = join_objects("Roof_Ridge", ridge_tiles)
    set_material(ridge, materials["roof"])

    eave_specs = [
        ("Eave_Left", (0.18, 2.54, 0.18), (-1.42, 0.0, 2.5), -ROOF_ANGLE),
        ("Eave_Right", (0.18, 2.54, 0.18), (1.42, 0.0, 2.5), ROOF_ANGLE),
        ("Eave_Front", (2.38, 0.18, 0.18), (0.0, 1.09, 2.62), 0.0),
    ]
    for name, size, location, angle in eave_specs:
        rotation = (0.0, angle, 0.0) if "Left" in name or "Right" in name else (0.0, 0.0, 0.0)
        obj = cube(name, size, location, rotation)
        set_material(obj, materials["wood"])
        apply_bevel(obj, 0.02, 2)
        smart_uv(obj)
        made.append(obj)

    chimney_blocks: list[bpy.types.Object] = []
    for i in range(4):
        block = cube(
            f"Chimney_Block_{i}",
            (0.38 + rng.uniform(-0.02, 0.02), 0.34 + rng.uniform(-0.02, 0.02), 0.28),
            (0.74, -0.38, 2.28 + i * 0.26),
            (0.0, 0.0, math.radians(rng.uniform(-4.0, 4.0))),
        )
        set_material(block, materials["stone"])
        apply_bevel(block, 0.02, 2)
        smart_uv(block)
        chimney_blocks.append(block)
        made.append(block)

    chimney = join_objects("House_Chimney", chimney_blocks)
    set_material(chimney, materials["stone"])

    lantern_hook = cube("Lantern_Hook", (0.08, 0.28, 0.08), (0.86, 1.0, 1.3))
    lantern_body = cube("Lantern_Body", (0.26, 0.22, 0.38), (0.86, 1.1, 1.0))
    lantern_core = cube("Lantern_Core", (0.15, 0.12, 0.22), (0.86, 1.12, 1.0))
    for obj, material in (
        (lantern_hook, materials["wood"]),
        (lantern_body, materials["stone"]),
        (lantern_core, materials["lantern"]),
    ):
        set_material(obj, material)
        apply_bevel(obj, 0.014, 2)
        smart_uv(obj)
        made.append(obj)

    return made


def finalize(root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    add_parenting(root, [obj for obj in bpy.context.scene.objects if obj != root])


def export_asset(root: bpy.types.Object) -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_normals=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )


def main() -> None:
    clear_scene()
    configure_world()

    materials = {
        "plaster": create_textured_material("MAT_HousePlaster", "village_house_plaster_albedo.png", roughness=0.94, specular=0.15),
        "wood": create_textured_material("MAT_HouseWood", "village_house_wood_albedo.png", roughness=0.82, specular=0.22),
        "roof": create_textured_material("MAT_HouseRoof", "village_house_roof_albedo.png", roughness=0.88, specular=0.18),
        "stone": create_textured_material("MAT_HouseStone", "village_house_stone_albedo.png", roughness=0.95, specular=0.12),
        "lantern": create_textured_material(
            "MAT_HouseLantern",
            "village_house_lantern_emissive.png",
            roughness=0.2,
            specular=0.4,
            emission_strength=2.8,
        ),
    }

    root = bpy.data.objects.new("Village_House_A", None)
    bpy.context.collection.objects.link(root)
    built = build_house(materials)
    finalize(root, built)
    export_asset(root)
    print(f"Saved {BLEND_PATH}")
    print(f"Exported {GLB_PATH}")


if __name__ == "__main__":
    main()
