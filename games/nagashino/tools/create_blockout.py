import math
import random
import zlib
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "samples" / "nagashino" / "assets" / "models"
BLEND_PATH = MODEL_DIR / "nagashino_blockout.blend"
OBJ_PATH = MODEL_DIR / "battlefield.obj"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


def assign(obj, mat):
    obj.data.materials.append(mat)
    return obj


def cube(name, loc, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return assign(obj, mat)


def cylinder(name, loc, radius, depth, mat, vertices=12, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    return assign(obj, mat)


def cone(name, loc, radius1, radius2, depth, mat, vertices=12, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=loc,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    return assign(obj, mat)


def plane_mesh(name, vertices, faces, mat):
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return assign(obj, mat)


def uv_plane_mesh(name, vertices, faces, uvs, mat):
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    cursor = 0
    for face_uvs, face in zip(uvs, faces):
        for uv in face_uvs:
            uv_layer.data[cursor].uv = uv
            cursor += 1
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return assign(obj, mat)


def planar_uv_mesh(name, vertices, faces, mat, uv_scale=0.1):
    uvs = []
    for face in faces:
        uvs.append([(vertices[index][0] * uv_scale, vertices[index][1] * uv_scale) for index in face])
    return uv_plane_mesh(name, vertices, faces, uvs, mat)


def ribbon_mesh(name, points, widths, z, mat, uv_scale=0.12):
    if not isinstance(widths, (list, tuple)):
        widths = [widths] * len(points)
    vertices = []
    faces = []
    face_uvs = []
    distances = [0.0]

    for i in range(1, len(points)):
        dx = points[i][0] - points[i - 1][0]
        dy = points[i][1] - points[i - 1][1]
        distances.append(distances[-1] + math.sqrt(dx * dx + dy * dy))

    for i, (x, y) in enumerate(points):
        prev = points[max(0, i - 1)]
        nxt = points[min(len(points) - 1, i + 1)]
        tx, ty = nxt[0] - prev[0], nxt[1] - prev[1]
        length = math.sqrt(tx * tx + ty * ty)
        nx, ny = -ty / length, tx / length
        half_width = widths[i] * 0.5
        vertices.append((x + nx * half_width, y + ny * half_width, z))
        vertices.append((x - nx * half_width, y - ny * half_width, z))

    for i in range(len(points) - 1):
        faces.append((i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2))
        u0, u1 = distances[i] * uv_scale, distances[i + 1] * uv_scale
        face_uvs.append([(u0, 0), (u0, 1), (u1, 1), (u1, 0)])
    return uv_plane_mesh(name, vertices, faces, face_uvs, mat)


def mountain_ridge(name, x, y, sx, sy, height, mat, phase=0.0):
    cols, rows = 17, 11
    vertices = []
    faces = []
    for row in range(rows):
        ny = -1.0 + 2.0 * row / (rows - 1)
        for col in range(cols):
            nx = -1.0 + 2.0 * col / (cols - 1)
            radius = math.sqrt(nx * nx + ny * ny)
            mask = max(0.0, 1.0 - radius * radius)
            ridge = 0.74 + 0.18 * math.sin(nx * 7.0 + phase) + 0.08 * math.cos(ny * 9.0 - phase)
            z = -0.08 + height * (mask ** 1.45) * ridge
            vertices.append((x + nx * sx, y + ny * sy, z))
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            faces.append((a, a + 1, a + 1 + cols, a + cols))
    return planar_uv_mesh(name, vertices, faces, mat, 0.075)


def river_rock(name, x, y, scale, mat, rotation=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=(x, y, scale * 0.34))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.scale = (scale, scale * 0.72, scale * 0.52)
    obj.rotation_euler[2] = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return assign(obj, mat)


def banner(name, x, y, z, height, width, mat_pole, mat_cloth, facing=1):
    cube(name + "_pole", (x, y, z + height * 0.5), (0.08, 0.08, height), mat_pole)
    bottom = z + height * 0.52
    top = z + height * 0.94
    left = x + 0.08 * facing
    right = x + width * facing
    verts = [
        (left, y, bottom), (right, y, bottom), (right, y, top), (left, y, top),
    ]
    faces = [(0, 1, 2, 3), (3, 2, 1, 0)]
    uvs = [
        [(0, 1), (1, 1), (1, 0), (0, 0)],
        [(0, 0), (1, 0), (1, 1), (0, 1)],
    ]
    return uv_plane_mesh(name, verts, faces, uvs, mat_cloth)


def fence_segment(name, x, y, angle, mat, stake_side=1):
    length = 7.0
    dir_x = math.cos(angle)
    dir_y = math.sin(angle)
    normal_x = -math.sin(angle) * stake_side
    normal_y = math.cos(angle) * stake_side
    normal_angle = math.atan2(normal_y, normal_x)
    for i in range(5):
        offset = (i - 2) * (length / 4.0)
        px = x + dir_x * offset
        py = y + dir_y * offset
        post = cube(f"{name}_post_{i+1}", (px, py, 0.75), (0.18, 0.18, 1.5), mat)
        post.rotation_euler[2] = angle
    rail1 = cube(name + "_rail_low", (x, y, 0.75), (length, 0.16, 0.16), mat)
    rail2 = cube(name + "_rail_high", (x, y, 1.25), (length, 0.16, 0.16), mat)
    rail1.rotation_euler[2] = angle
    rail2.rotation_euler[2] = angle
    for i in range(4):
        offset = (i - 1.5) * (length / 4.0)
        px = x + dir_x * offset + normal_x * 0.45
        py = y + dir_y * offset + normal_y * 0.45
        spike = cube(f"{name}_anti_cavalry_stake_{i+1}", (px, py, 0.78), (1.05, 0.08, 0.08), mat)
        spike.rotation_euler[1] = math.radians(-24)
        spike.rotation_euler[2] = normal_angle


def soldier(name, x, y, mat_body, mat_hat, facing=1):
    cube(name + "_legs", (x - 0.02 * facing, y, 0.28), (0.24, 0.18, 0.50), mat_body)
    cube(name + "_body", (x, y, 0.74), (0.34, 0.24, 0.58), mat_body)
    cylinder(name + "_head", (x, y, 1.14), 0.12, 0.18, mat_hat, vertices=10)
    cone(name + "_jingasa", (x, y, 1.28), 0.22, 0.03, 0.16, mat_hat, vertices=12)
    gun = cylinder(name + "_teppo", (x + 0.36 * facing, y, 0.98), 0.025, 0.95, mat_hat, vertices=8, rotation=(0, math.radians(90 * facing), 0))
    gun.rotation_euler[2] = 0.02 * facing


def rider(name, x, y, mat_body, mat_horse, facing=1):
    cube(name + "_horse_body", (x, y, 0.62), (1.05, 0.34, 0.45), mat_horse)
    cube(name + "_horse_neck", (x + 0.48 * facing, y, 0.88), (0.24, 0.22, 0.46), mat_horse)
    for i, dx in enumerate([-0.36, -0.12, 0.18, 0.42], start=1):
        cube(f"{name}_horse_leg_{i}", (x + dx * facing, y + 0.08 * ((i % 2) * 2 - 1), 0.26), (0.08, 0.08, 0.50), mat_horse)
    cube(name + "_rider_body", (x - 0.05 * facing, y, 1.08), (0.30, 0.24, 0.58), mat_body)
    cone(name + "_kabuto", (x - 0.05 * facing, y, 1.43), 0.18, 0.06, 0.18, mat_body, vertices=10)
    spear = cylinder(name + "_yari", (x + 0.52 * facing, y, 1.22), 0.025, 1.35, mat_body, vertices=8, rotation=(0, math.radians(86 * facing), 0))
    spear.rotation_euler[2] = 0.12 * facing


def smoke_marker(name, x, y, mat):
    cylinder(name + "_base", (x, y, 0.1), 0.18, 0.2, mat, vertices=10)
    cone(name + "_plume", (x, y, 0.62), 0.38, 0.12, 0.9, mat, vertices=12)


LEAF_ATLAS = [
    (0.015, 0.47, 0.180, 0.985), (0.185, 0.47, 0.395, 0.985),
    (0.390, 0.47, 0.595, 0.985), (0.585, 0.47, 0.790, 0.985),
    (0.780, 0.47, 0.990, 0.985), (0.010, 0.010, 0.215, 0.455),
    (0.215, 0.010, 0.410, 0.455), (0.415, 0.010, 0.610, 0.455),
]


def branch_between(name, start, end, radius, mat):
    """沿任意方向生成一段低面数枝干；对象稍后合并成一个树干 draw call。"""
    start, end = Vector(start), Vector(end)
    direction = end - start
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=radius, radius2=radius * 0.42,
                                    depth=direction.length, location=(start + end) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return assign(obj, mat)


def join_parts(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    return obj


def leaf_cluster(name, center, radius, leaf_count, mat, rng):
    """一棵树的一整个叶片簇：所有双面叶片合并到一个网格，避免逐叶 draw call。"""
    vertices, faces, uvs = [], [], []
    for _ in range(leaf_count):
        theta = rng.uniform(0.0, math.tau)
        vertical = rng.uniform(-0.76, 0.86)
        radial = math.sqrt(max(0.12, 1.0 - vertical * vertical)) * rng.uniform(0.32, 1.0)
        cx = center[0] + math.cos(theta) * radius * radial
        cy = center[1] + math.sin(theta) * radius * radial
        cz = center[2] + vertical * radius * 0.82
        rotation = theta + rng.uniform(-0.72, 0.72)
        width = radius * rng.uniform(0.25, 0.34)
        height = width * rng.uniform(1.55, 2.05)
        rx, ry = math.cos(rotation) * width * 0.5, math.sin(rotation) * width * 0.5
        base = len(vertices)
        vertices.extend([
            (cx - rx, cy - ry, cz - height * 0.5), (cx + rx, cy + ry, cz - height * 0.5),
            (cx + rx, cy + ry, cz + height * 0.5), (cx - rx, cy - ry, cz + height * 0.5),
        ])
        u0, v0, u1, v1 = rng.choice(LEAF_ATLAS)
        faces.extend([(base, base + 1, base + 2, base + 3), (base + 3, base + 2, base + 1, base)])
        uvs.extend([
            [(u0, v0), (u1, v0), (u1, v1), (u0, v1)],
            [(u0, v1), (u1, v1), (u1, v0), (u0, v0)],
        ])
    return uv_plane_mesh(name, vertices, faces, uvs, mat)


def tree(name, x, y, mat_trunk, mat_leaves, height=2.2, leaf_count=48):
    """分枝树干加真实叶片卡的阔叶树；固定种子保证关卡资产可复现。"""
    rng = random.Random(zlib.crc32(name.encode("utf-8")))
    height *= rng.uniform(0.90, 1.16)
    lean_x, lean_y = rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07)
    trunk_top = (x + lean_x * height, y + lean_y * height, height * 0.78)
    branches = [branch_between(name + "_trunk", (x, y, 0.0), trunk_top, height * 0.055, mat_trunk)]
    for index in range(rng.randint(6, 8)):
        angle = (index / 7.0) * math.tau + rng.uniform(-0.34, 0.34)
        branch_z = height * (0.42 + index * 0.045 + rng.uniform(-0.025, 0.025))
        start = (x + lean_x * branch_z, y + lean_y * branch_z, branch_z)
        reach = height * rng.uniform(0.22, 0.34)
        end = (start[0] + math.cos(angle) * reach, start[1] + math.sin(angle) * reach,
               branch_z + height * rng.uniform(0.10, 0.20))
        branches.append(branch_between(f"{name}_branch_{index + 1}", start, end, height * 0.024, mat_trunk))
    join_parts(branches, name + "_trunk")
    canopy_center = (trunk_top[0], trunk_top[1], height * 0.76)
    leaf_cluster(name + "_leaves", canopy_center, height * 0.43, leaf_count, mat_leaves, rng)


def low_hill(name, x, y, sx, sy, height, mat):
    verts = [
        (x - sx, y - sy, 0), (x + sx, y - sy, 0), (x + sx, y + sy, 0), (x - sx, y + sy, 0),
        (x, y, height),
    ]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)]
    return planar_uv_mesh(name, verts, faces, mat, 0.08)


def surrounding_landscape(mat):
    half_x, half_y = 320.0, 240.0
    cols, rows = 33, 25
    vertices = []
    faces = []

    for row in range(rows):
        y = -half_y + (half_y * 2.0) * row / (rows - 1)
        for col in range(cols):
            x = -half_x + (half_x * 2.0) * col / (cols - 1)
            radial = math.sqrt((x / 92.0) ** 2 + (y / 68.0) ** 2)
            distant_rise = max(0.0, radial - 0.72)
            relief_blend = max(0.0, min(1.0, (radial - 0.42) / 0.48))
            undulation = (math.sin(x * 0.024) * 0.34 + math.cos(y * 0.031) * 0.28) * relief_blend
            z = -0.35 + undulation + min(distant_rise * distant_rise * 0.72, 15.0)
            vertices.append((x, y, z))

    for row in range(rows - 1):
        for col in range(cols - 1):
            center_x = (vertices[row * cols + col][0] + vertices[row * cols + col + 1][0]) * 0.5
            center_y = (vertices[row * cols + col][1] + vertices[(row + 1) * cols + col][1]) * 0.5
            if abs(center_x) < 40.0 and abs(center_y) < 25.0:
                continue
            a = row * cols + col
            b = a + 1
            d = (row + 1) * cols + col
            c = d + 1
            faces.append((a, b, c, d))

    return planar_uv_mesh("surrounding_landscape", vertices, faces, mat, 0.055)


def make_scene():
    clear_scene()
    mats = {
        "grass_battlefield": material("grass_battlefield", (0.28, 0.42, 0.20, 1.0)),
        "mud_road": material("mud_road", (0.34, 0.23, 0.15, 1.0)),
        "wood_dark": material("wood_dark", (0.36, 0.22, 0.12, 1.0)),
        "cloth_takeda": material("cloth_takeda", (0.78, 0.05, 0.04, 1.0)),
        "cloth_oda": material("cloth_oda", (0.12, 0.10, 0.10, 1.0)),
        "cloth_tokugawa": material("cloth_tokugawa", (0.04, 0.18, 0.60, 1.0)),
        "ashigaru_cloth": material("ashigaru_cloth", (0.28, 0.30, 0.30, 1.0)),
        "takeda_armor": material("takeda_armor", (0.52, 0.06, 0.04, 1.0)),
        "horse_brown": material("horse_brown", (0.29, 0.16, 0.09, 1.0)),
        "gun_smoke": material("gun_smoke", (0.66, 0.68, 0.66, 0.7)),
        "water_stream": material("water_stream", (0.08, 0.22, 0.34, 1.0)),
        "river_bank": material("river_bank", (0.24, 0.22, 0.16, 1.0)),
        "tree_bark": material("tree_bark", (0.27, 0.20, 0.12, 1.0)),
        "tree_leaves": material("tree_leaves", (0.25, 0.40, 0.16, 1.0)),
        "hill_earth": material("hill_earth", (0.20, 0.25, 0.15, 1.0)),
        "collision": material("collision", (0.0, 0.8, 1.0, 0.25)),
        "trigger": material("trigger", (1.0, 0.8, 0.0, 0.25)),
    }

    surrounding_landscape(mats["grass_battlefield"])
    planar_uv_mesh(
        "battlefield_terrain",
        [(-40, -25, 0), (40, -25, 0.25), (40, 25, -0.10), (-40, 25, 0.05)],
        [(0, 1, 2, 3)],
        mats["grass_battlefield"],
        0.11,
    )
    charge_path = [(-39, -0.8), (-31, -1.6), (-23, -0.3), (-15, 0.9), (-7, 0.2), (2, -0.7), (10, 0.4), (19, 1.1)]
    ribbon_mesh("mud_charge_road", charge_path, [4.2, 4.8, 4.4, 5.2, 4.6, 4.9, 4.3, 4.0],
                0.035, mats["mud_road"], 0.14)

    river_path = [(-45, 15.6), (-36, 14.2), (-27, 15.0), (-18, 13.3), (-8, 14.1),
                  (2, 12.8), (12, 13.8), (22, 12.5), (33, 14.0), (45, 13.1)]
    water_widths = [3.1, 3.8, 3.3, 4.5, 3.7, 4.2, 3.5, 4.4, 3.6, 3.2]
    bank_widths = [width + 2.2 + (i % 3) * 0.35 for i, width in enumerate(water_widths)]
    ribbon_mesh("shitaragahara_river_bank", river_path, bank_widths, 0.026, mats["river_bank"], 0.13)
    ribbon_mesh("shitaragahara_stream", river_path, water_widths, 0.045, mats["water_stream"], 0.10)

    mountain_ridge("rear_hill_left", 24, -20, 17, 9, 1.8, mats["grass_battlefield"], 0.8)
    mountain_ridge("rear_hill_right", 28, 20, 19, 10, 2.2, mats["grass_battlefield"], 2.1)
    mountain_ridge("outer_ridge_west", -67, -30, 30, 20, 10.5, mats["hill_earth"], 1.4)
    mountain_ridge("outer_ridge_east", 72, 31, 34, 22, 12.0, mats["hill_earth"], 2.8)

    for i, (rx, ry, scale, rotation) in enumerate([
        (-34, 12.6, 0.70, 0.2), (-25, 17.0, 0.48, 1.1), (-14, 11.9, 0.58, 0.5),
        (-2, 15.5, 0.42, 1.8), (9, 11.8, 0.66, 0.9), (20, 15.2, 0.50, 2.4),
        (31, 11.8, 0.74, 0.4), (38, 15.1, 0.46, 1.5),
    ], start=1):
        river_rock(f"river_bank_rock_{i}", rx, ry, scale, mats["hill_earth"], rotation)
    forest_edge = [
        (-37, -21), (-34, -20), (-31, -19), (-28, -22), (-25, -20),
        (-28, 18), (-25, 20), (-22, 21), (-19, 19),
        (18, -22), (22, -20), (26, -21), (30, -18), (34, -20),
        (27, 18), (31, 20), (35, 19), (38, 21),
    ]
    for i, (tx, ty) in enumerate(forest_edge, start=1):
        tree(f"forest_edge_tree_{i}", tx, ty, mats["tree_bark"], mats["tree_leaves"],
             5.4 + (i % 3) * 0.85, leaf_count=100)

    outer_trees = [
        (-58, -34), (-66, -27), (-72, -18), (-69, 21), (-61, 34), (-52, 39),
        (54, -38), (63, -31), (72, -19), (70, 20), (62, 32), (51, 40),
        (-38, -48), (-20, -52), (5, -55), (30, -50),
        (-35, 48), (-12, 53), (12, 54), (36, 47),
    ]
    for i, (tx, ty) in enumerate(outer_trees, start=1):
        tree(f"outer_forest_tree_{i}", tx, ty, mats["tree_bark"], mats["tree_leaves"],
             7.8 + (i % 4) * 1.05, leaf_count=70)

    for idx, y in enumerate([-7.0, 0.0, 7.0], start=1):
        fence_segment(f"oda_horse_fence_{idx}", 8.0, y, math.pi * 0.5, mats["wood_dark"])

    for row, x in enumerate([10.0, 12.0, 14.0], start=1):
        for i, y in enumerate([-8, -4, 0, 4, 8], start=1):
            soldier(f"oda_gunner_r{row}_{i}", x, y, mats["ashigaru_cloth"], mats["wood_dark"], facing=-1)
    for i, y in enumerate([-7.5, -3.8, 0.0, 3.8, 7.5], start=1):
        smoke_marker(f"teppo_smoke_{i}", 8.8, y, mats["gun_smoke"])

    for i, y in enumerate([-5.5, -2.0, 1.5, 5.0], start=1):
        rider(f"takeda_rider_{i}", -18.0 - i * 2.2, y, mats["takeda_armor"], mats["horse_brown"], facing=1)

    banner("banner_takeda", -24.0, -8.5, 0.0, 3.2, 1.2, mats["wood_dark"], mats["cloth_takeda"])
    banner("banner_oda", 15.5, -9.5, 0.0, 3.0, 1.1, mats["wood_dark"], mats["cloth_oda"], facing=-1)
    banner("banner_tokugawa", 15.5, 9.5, 0.0, 3.0, 1.1, mats["wood_dark"], mats["cloth_tokugawa"], facing=-1)

    cube("terrain_col", (0.0, 0.0, -0.08), (80.0, 50.0, 0.18), mats["collision"])
    cube("oda_fireline_trigger", (11.0, 0.0, 1.1), (10.0, 20.0, 2.2), mats["trigger"])
    cube("takeda_charge_lane_trigger", (-14.0, 0.0, 1.0), (34.0, 10.0, 2.0), mats["trigger"])
    cube("command_view_trigger", (1.0, -18.0, 1.0), (8.0, 5.0, 2.0), mats["trigger"])

    bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
    bpy.context.object.name = "sun_preview"
    bpy.context.object.data.energy = 2.0
    bpy.context.object.rotation_euler = (math.radians(50), 0, math.radians(35))

    bpy.ops.object.camera_add(location=(-12, -28, 16), rotation=(math.radians(60), 0, math.radians(-22)))
    bpy.context.scene.camera = bpy.context.object


def export_obj():
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    if hasattr(bpy.ops.wm, "obj_export"):
        bpy.ops.wm.obj_export(
            filepath=str(OBJ_PATH),
            export_selected_objects=False,
            export_materials=True,
            forward_axis="NEGATIVE_Z",
            up_axis="Y",
        )
    else:
        bpy.ops.export_scene.obj(
            filepath=str(OBJ_PATH),
            use_selection=False,
            use_materials=True,
            axis_forward="-Z",
            axis_up="Y",
        )


if __name__ == "__main__":
    make_scene()
    export_obj()
