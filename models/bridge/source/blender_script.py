import bpy
from math import radians
import os

# ============================================================
# CAMINHO DA TEXTURA
# ============================================================

WOOD_TEXTURE_PATH = "/home/viniciuscgp/Desktop/v-games/RelicMiner/relicminer/models/bridge/textures/bridge_texture_1.png"


# ============================================================
# LIMPAR CENA
# ============================================================

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()


# ============================================================
# MATERIAIS
# ============================================================

def create_material(name, color, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness

    return mat


def create_image_material(name, image_path, fallback_color, roughness=0.75, texture_scale=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness

    if os.path.exists(image_path):
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image_path)
        tex.extension = "REPEAT"
        tex.projection = "BOX"
        tex.projection_blend = 0.15

        coord = nodes.new("ShaderNodeTexCoord")

        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value[0] = texture_scale
        mapping.inputs["Scale"].default_value[1] = texture_scale
        mapping.inputs["Scale"].default_value[2] = texture_scale

        links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

        print("Textura carregada:", image_path)
    else:
        bsdf.inputs["Base Color"].default_value = fallback_color
        print("Textura não encontrada. Usando cor simples:", image_path)

    return mat


wood_mat = create_image_material(
    "Bridge_Wood_Texture",
    WOOD_TEXTURE_PATH,
    (0.48, 0.25, 0.10, 1.0),
    roughness=0.75,
    texture_scale=0.6
)

metal_mat = create_material(
    "Dark_Metal",
    (0.18, 0.17, 0.16, 1.0),
    0.45
)


# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

def cube(name, location, scale, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)

    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale

    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    if material:
        obj.data.materials.append(material)

    bevel = obj.modifiers.new("Small_Bevel", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 1

    obj.modifiers.new("Weighted_Normals", "WEIGHTED_NORMAL")

    return obj


def add_post_cap(name, location, radius, depth, material):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6,
        radius=radius,
        depth=depth,
        location=location
    )

    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler[2] = radians(30)

    if material:
        obj.data.materials.append(material)

    bevel = obj.modifiers.new("Small_Bevel", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 1

    obj.modifiers.new("Weighted_Normals", "WEIGHTED_NORMAL")

    return obj


# ============================================================
# MEDIDAS GERAIS
# ============================================================

bridge_length = 6.0
bridge_width = 2.2
deck_height = 0.8

plank_count = 10
plank_width = bridge_length / plank_count


# ============================================================
# TABLADO PRINCIPAL
# ============================================================

for i in range(plank_count):
    x = -bridge_length / 2 + plank_width / 2 + i * plank_width

    plank = cube(
        "Bridge_Plank",
        (x, 0, deck_height),
        (plank_width * 0.92, bridge_width, 0.18),
        wood_mat
    )

    if i % 2 == 0:
        plank.location.z += 0.015
    else:
        plank.location.z -= 0.005


# ============================================================
# VIGAS LATERAIS DO TABLADO
# ============================================================

cube(
    "Left_Side_Beam",
    (0, -bridge_width / 2 - 0.12, deck_height - 0.12),
    (bridge_length + 0.4, 0.18, 0.26),
    wood_mat
)

cube(
    "Right_Side_Beam",
    (0, bridge_width / 2 + 0.12, deck_height - 0.12),
    (bridge_length + 0.4, 0.18, 0.26),
    wood_mat
)


# ============================================================
# RAMPAS NAS PONTAS
# ============================================================

front_ramp = cube(
    "Front_Ramp",
    (-bridge_length / 2 - 0.55, 0, deck_height - 0.10),
    (1.1, bridge_width, 0.16),
    wood_mat
)
front_ramp.rotation_euler[1] = radians(-10)

back_ramp = cube(
    "Back_Ramp",
    (bridge_length / 2 + 0.55, 0, deck_height - 0.10),
    (1.1, bridge_width, 0.16),
    wood_mat
)
back_ramp.rotation_euler[1] = radians(10)


# ============================================================
# POSTES
# ============================================================

post_positions = [
    (-bridge_length / 2 + 0.25, -bridge_width / 2 - 0.25),
    (-bridge_length / 2 + 0.25,  bridge_width / 2 + 0.25),

    (0, -bridge_width / 2 - 0.25),
    (0,  bridge_width / 2 + 0.25),

    (bridge_length / 2 - 0.25, -bridge_width / 2 - 0.25),
    (bridge_length / 2 - 0.25,  bridge_width / 2 + 0.25),
]

for index, (x, y) in enumerate(post_positions):
    cube(
        f"Post_{index}",
        (x, y, deck_height + 0.65),
        (0.28, 0.28, 1.3),
        wood_mat
    )

    add_post_cap(
        f"Post_Cap_{index}",
        (x, y, deck_height + 1.35),
        0.22,
        0.18,
        wood_mat
    )


# ============================================================
# CORRIMÕES
# ============================================================

for y in [-bridge_width / 2 - 0.25, bridge_width / 2 + 0.25]:
    cube(
        "Top_Rail",
        (0, y, deck_height + 1.15),
        (bridge_length + 0.2, 0.16, 0.16),
        wood_mat
    )

    cube(
        "Middle_Rail",
        (0, y, deck_height + 0.75),
        (bridge_length + 0.1, 0.12, 0.12),
        wood_mat
    )


# ============================================================
# SUPORTES INFERIORES
# ============================================================

support_positions = [
    (-1.8, -0.75, 25),
    (-1.8,  0.75, -25),
    (1.8, -0.75, -25),
    (1.8,  0.75, 25),
]

for index, (x, y, rot) in enumerate(support_positions):
    support = cube(
        f"Diagonal_Support_{index}",
        (x, y, deck_height - 0.55),
        (1.4, 0.14, 0.18),
        wood_mat
    )
    support.rotation_euler[1] = radians(rot)


# ============================================================
# DETALHES DE METAL NOS POSTES
# ============================================================

for index, (x, y) in enumerate(post_positions):
    cube(
        f"Metal_Band_{index}",
        (x, y, deck_height + 0.95),
        (0.34, 0.34, 0.08),
        metal_mat
    )


# ============================================================
# LUZ E CÂMERA
# ============================================================

bpy.ops.object.light_add(type='AREA', location=(0, -5, 6))
light = bpy.context.object
light.name = "Key_Light"
light.data.energy = 600
light.data.size = 5

bpy.ops.object.camera_add(
    location=(4.5, -5.5, 4.0),
    rotation=(radians(60), 0, radians(38))
)

camera = bpy.context.object
bpy.context.scene.camera = camera
camera.data.lens = 35


# ============================================================
# ORGANIZAÇÃO
# ============================================================

empty = bpy.data.objects.new("WoodenBridge_Root", None)
bpy.context.collection.objects.link(empty)

for obj in bpy.context.scene.objects:
    if obj.name != "WoodenBridge_Root" and obj.type not in ["CAMERA", "LIGHT"]:
        obj.parent = empty


# ============================================================
# CONFIGURAÇÃO VISUAL
# ============================================================

try:
    bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'
except:
    bpy.context.scene.render.engine = 'BLENDER_EEVEE'

bpy.context.scene.world.color = (0.78, 0.78, 0.78)

print("WoodenBridge criado com textura aplicada em toda madeira.")