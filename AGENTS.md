## Project Notes

- For any 3D model created or edited for use in Godot, prefer a Godot-ready export workflow.
- If a Blender material uses procedural nodes, stripes, generated patterns, or any look that glTF may not preserve, bake the material to image textures before export.
- Default export target for game assets is `.glb` after bake, unless the user explicitly asks for another format or a Blender-only/procedural workflow.
- If there is a tradeoff between keeping the exact Blender look and a faster export, prioritize preserving the in-game look by baking first.
