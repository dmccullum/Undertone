# Blender direction

The Blender scene script in this folder replaces the flat diagram approach with a true 3D, open half-twisted ribbon. It makes the strip, its 180° rotation, edge thickness, rounded icon slab, lighting, camera, and a cyan-to-coral material palette from scratch.

Run it with Blender 4.x:

```sh
blender --background --python undertone_ribbon.py
```

It writes `undertone-ribbon.blend` and `renders/undertone-ribbon-beauty.png` beside the script.

Use the render as the art-direction source. For Icon Composer, the best workflow is to preserve the editable SVG masks for responsive Liquid Glass, then tune their gradients and shared group properties to the approved Blender render. Importing a photoreal Blender render as a glass layer would stack one simulated material under Composer’s dynamic material and usually looks muddy.
