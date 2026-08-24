window.EMBEDDED_MAPS = {
  "shader_maze_1.json": {
    "metadata": {
      "name": "ShaderMazeScene-PerPixel",
      "version": "1.0",
      "width": 24,
      "height": 18,
      "tileSize": 0.5,
      "unit": "meter"
    },
    "layers": [
      {
        "name": "maze",
        "type": "tilelayer",
        "data": [
          1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,3,3,0,0,0,0,3,3,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,3,0,0,0,0,0,0,3,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,3,0,0,0,0,0,0,3,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,3,3,0,0,0,0,3,3,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
          1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        ]
      },
      {
        "name": "entities",
        "type": "objectlayer",
        "objects": [
          {
            "id": 101,
            "type": "player_spawn",
            "x": 2.5,
            "y": 2.5,
            "properties": {
              "angle": 18,
              "fov": 84,
              "height": 1.28
            }
          },
          {
            "id": 201,
            "type": "table",
            "x": 12.0,
            "y": 9.0,
            "properties": {
              "width": 1.8,
              "depth": 1.1,
              "topHeight": 0.80,
              "thickness": 0.08,
              "legThickness": 0.10
            }
          },
          {
            "id": 200,
            "type": "pyramid",
            "x": 12.0,
            "y": 9.0,
            "properties": {
              "size": 0.70,
              "height": 0.68
            }
          }
        ]
      }
    ],
    "tilesets": [
      {
        "id": 1,
        "name": "outer_wall",
        "color": "#5F4339",
        "passable": false,
        "height": 2.8,
        "properties": {
          "kind": "wall",
          "blocksMovement": true,
          "raycastBarrier": true,
          "occluder": true,
          "visible": true,
          "renderType": "solid"
        }
      },
      {
        "id": 0,
        "name": "maze_wall",
        "color": "#7B6A58",
        "passable": false,
        "height": 2.6,
        "properties": {
          "kind": "wall",
          "blocksMovement": true,
          "raycastBarrier": true,
          "occluder": true,
          "visible": true,
          "renderType": "solid"
        }
      },
      {
        "id": 3,
        "name": "chamber_wall",
        "color": "#9E8D77",
        "passable": false,
        "height": 2.4,
        "properties": {
          "kind": "wall",
          "blocksMovement": true,
          "raycastBarrier": true,
          "occluder": true,
          "visible": true,
          "renderType": "solid"
        }
      }
    ]
  }
};
