"""Generates the previous Undertone app icon (the Prism Fan) as an Icon Composer document.

This script no longer builds the shipped icon. Icon/Undertone.icon is now a different design (a
gradient panel with three glass discs, see docs/ICON.md), maintained directly in Icon Composer, so
the script refuses to write over it. It is kept as a record and writes only to another .icon bundle.

Icon Composer allows four visible groups: the pin and three chips each get their own, so every chip
gets the system's glass. Chips that share a group (more chips than groups) are flattened before the
glass is applied, so they lose their own edge highlight and the shadow they cast on the chip behind.
This script bakes those two things into each shared chip's artwork instead.

usage: python3 scripts/build-prism-fan-icon.py OUT.icon ['{"shift": -24, "translucency": 0.9}']

OUT is required and is replaced wholesale, so close it in Icon Composer first.
The optional JSON overrides any key of P below. Preview a build with Icon Composer's ictool:
  "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" OUT.icon \\
      --export-image --output-file preview.png --platform macOS --rendition Default \\
      --width 512 --height 512 --scale 2 --design-generation 26
"""
import json, math, os, shutil, sys

if len(sys.argv) < 2:
    sys.exit("usage: python3 scripts/build-prism-fan-icon.py OUT.icon [JSON]")
OUT = sys.argv[1]
SHIPPED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Icon", "Undertone.icon")
if os.path.realpath(OUT.rstrip("/")) == os.path.realpath(SHIPPED):
    sys.exit("refusing to replace %s: the shipped icon is edited in Icon Composer, not generated" % os.path.normpath(SHIPPED))
if not OUT.rstrip("/").endswith(".icon"):
    sys.exit("refusing to replace %s: the output must be an .icon bundle" % OUT)
# angle and grad are keyed by chip number, back to front; each gradient runs corner to corner.
# bg is the tile's two gradient colors, or None for the system's own light and dark backgrounds.
P = {"groups": [["pin"], [3], [2], [1]], "bake": True,
     "angle": {"1": -32, "2": 0, "3": 32},
     "grad": {"1": ["#FFB347", "#FF3B3B", "#D9145A"], "2": ["#E4F55A", "#2ED16A", "#0FA3A0"],
              "3": ["#6EF0FF", "#2F7BFF", "#5A2BE8"]},
     "translucency": 0.5, "blur": 0.1, "refract": [0.5, 0], "shadow": 0.4,
     "spec_opacity": 0.9, "inner_shadow": 0.45, "caustic_opacity": 0.6, "caustic_y": 846, "shift": 6,
     "scale": 1.10, "tilt": 16, "center": True, "nudge": 18, "bg": None}
if len(sys.argv) > 2:
    P.update(json.loads(sys.argv[2]))

A = os.path.join(OUT, "Assets")
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(A)

# shift moves the whole composition (chips, pin, caustic) vertically
PIV = (512, 750); DY = -34 + P["shift"]
X0, Y0, W, H, R = 417, 236, 190, 600, 56
X1, Y1 = X0 + W, Y0 + H
ANGLE = {int(k): v for k, v in P["angle"].items()}
GRAD = {int(k): v for k, v in P["grad"].items()}
SPECTRUM = ["#FF4D6D", "#FFB84D", "#F2FF5C", "#4DFFB0", "#4DC3FF", "#8F5CFF", "#FF5CE1"]
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'


def tf(p, a, dx=0, dy=0):
    t = math.radians(a); x, y = p[0] - PIV[0], p[1] - PIV[1]
    return sc((PIV[0] + x*math.cos(t) - y*math.sin(t) + dx, PIV[1] + x*math.sin(t) + y*math.cos(t) + DY + dy))


def sc(p):
    """Scale the composition about the canvas centre, then tilt it there (degrees, clockwise)."""
    k, t = P["scale"], math.radians(P["tilt"])
    x, y = (p[0] - 512)*k, (p[1] - 512)*k
    return (512 + x*math.cos(t) - y*math.sin(t) + OFF[0], 512 + x*math.sin(t) + y*math.cos(t) + OFF[1])


OFF = (0, 0)
if P["center"]:
    # move the chips' bounding box to the canvas centre, then apply nudge and shift on top
    # (a tilted fan's weight sits off its bounding box, so nudge moves it toward the eye's centre)
    pts = [tf((cx + R*math.cos(math.radians(d)), cy + R*math.sin(math.radians(d))), ANGLE[i])
           for i in ANGLE for cx in (X0+R, X1-R) for cy in (Y0+R, Y1-R) for d in range(0, 360, 5)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    OFF = (512 - (min(xs) + max(xs))/2 + P["nudge"], 512 - (min(ys) + max(ys))/2 + P["shift"])


def chip_path(i, dx=0, dy=0):
    a = ANGLE[i]
    f = lambda x, y: "%.2f %.2f" % tf((x, y), a, dx, dy)
    arc = "A%.2f %.2f 0 0 1 " % (R*P["scale"], R*P["scale"])
    return ("M" + f(X0+R, Y0) + " L" + f(X1-R, Y0) + " " + arc + f(X1, Y0+R) + " L" + f(X1, Y1-R) + " " + arc + f(X1-R, Y1)
            + " L" + f(X0+R, Y1) + " " + arc + f(X0, Y1-R) + " L" + f(X0, Y0+R) + " " + arc + f(X0+R, Y0) + " Z")


def grad(id_, stops, p0, p1, opacities=None):
    n = len(stops) - 1
    s = "".join('<stop offset="%.3f" stop-color="%s"%s/>' % (
        k/n, c, ' stop-opacity="%.2f"' % opacities[k] if opacities else "") for k, c in enumerate(stops))
    return ('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f">%s</linearGradient>'
            % (id_, p0[0], p0[1], p1[0], p1[1], s))


def write(name, body):
    with open(os.path.join(A, name), "w") as fh:
        fh.write(HEAD + body + "</svg>\n")


for i in ANGLE:
    a = ANGLE[i]
    tl, br = tf((X0, Y0), a), tf((X1, Y1), a)
    write("chip-%d.svg" % i, "<defs>" + grad("g", GRAD[i], tl, br) + '</defs><path d="%s" fill="url(#g)"/>' % chip_path(i))
    # baked specular edge: what the group glass would have drawn on this chip's own outline
    write("spec-%d.svg" % i, "<defs>" + grad("h", ["#FFFFFF"] * 4, tl, br, [0.95, 0.15, 0.05, 0.55])
          + '<clipPath id="c"><path d="%s"/></clipPath></defs>' % chip_path(i)
          + '<g clip-path="url(#c)"><path d="%s" fill="none" stroke="url(#h)" stroke-width="9"/></g>' % chip_path(i))


def inner_shadow(i, behind, tag):
    """Chip i's tinted shadow, kept inside the chips behind it in the same group."""
    name = "shadow-%d-%s.svg" % (i, tag)
    clips = "".join('<path d="%s"/>' % chip_path(j) for j in behind)
    write(name, '<defs><clipPath id="c">%s</clipPath>' % clips
          + '<filter id="b" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter></defs>'
          + '<g clip-path="url(#c)"><path d="%s" fill="%s" fill-opacity="%.2f" filter="url(#b)"/></g>'
          % (chip_path(i, 0, 16), GRAD[i][1], P["inner_shadow"]))
    return name


# caustic: blurred spectrum pooled under the rivet (CoreSVG renders blur filters)
# when the caustic shares the front group with the pin, mask the chips out so it still reads as behind them
caustic_front = any("caustic" in g and "pin" in g for g in P["groups"])
chip_mask = ('<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#FFFFFF"/>'
             + "".join('<path d="%s" fill="#000000"/>' % chip_path(i) for i in ANGLE) + '</mask>') if caustic_front else ""
write("caustic.svg", "<defs>" + grad("s", SPECTRUM, (212, 0), (812, 0))
      + '<filter id="b" x="-50%" y="-100%" width="200%" height="300%"><feGaussianBlur stdDeviation="34"/></filter>' + chip_mask + '</defs>'
      + ('<g mask="url(#m)">' if caustic_front else "<g>")
      + '<ellipse cx="512" cy="%.1f" rx="%.1f" ry="%.1f" fill="url(#s)" filter="url(#b)"/></g>'
      % (sc((512, P["caustic_y"] + P["shift"]))[1], 300*P["scale"], 50*P["scale"]))

cx, cy = sc((PIV[0], PIV[1] + DY))
pin_shares = any("pin" in g and len(g) > 1 for g in P["groups"])
pin_shadow = ('<filter id="ps" x="-80%" y="-80%" width="260%" height="280%"><feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#1E1240" flood-opacity="0.35"/>'
              '<feDropShadow dx="0" dy="12" stdDeviation="12" flood-color="#1E1240" flood-opacity="0.3"/></filter>') if pin_shares else ""
if any("pin" in g for g in P["groups"]):
  write("pin.svg", "<defs>"
      '<linearGradient id="ring" x1="0.1" y1="0" x2="0.9" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.22" stop-color="#C8C4D6"/><stop offset="0.42" stop-color="#F7F6FB"/><stop offset="0.62" stop-color="#9590A8"/><stop offset="0.8" stop-color="#E4E1EC"/><stop offset="1" stop-color="#77728C"/></linearGradient>'
      '<radialGradient id="dome" cx="0.4" cy="0.32" r="0.75"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.35" stop-color="#ECEAF3"/><stop offset="0.75" stop-color="#B3AEC4"/><stop offset="1" stop-color="#8A85A0"/></radialGradient>'
      '<linearGradient id="seam" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5A5470" stop-opacity="0.55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.8"/></linearGradient>'
      '<linearGradient id="spec" x1="0" y1="0" x2="1" y2="0">' + "".join('<stop offset="%.3f" stop-color="%s"/>' % (k/6, c) for k, c in enumerate(SPECTRUM)) + '</linearGradient>'
      + pin_shadow + "</defs>"
      '<g transform="translate(%.1f %.1f) scale(%.3f)">' % (cx, cy, P["scale"])
      + ('<circle r="44" fill="url(#ring)" filter="url(#ps)"/>' if pin_shares else '<circle r="44" fill="url(#ring)"/>')
      + '<circle r="43" fill="none" stroke="#5E5874" stroke-opacity="0.45" stroke-width="2"/>'
      '<circle r="40" fill="none" stroke="url(#spec)" stroke-opacity="0.22" stroke-width="5"/>'
      '<circle r="29" fill="url(#dome)"/>'
      '<circle r="29.5" fill="none" stroke="url(#seam)" stroke-width="3"/>'
      '<circle r="9" fill="#6E6886" fill-opacity="0.4"/>'
      '<circle r="9" cy="1.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="1.5"/>'
      '<ellipse cx="-10" cy="-13" rx="13" ry="7" fill="#FFFFFF" fill-opacity="0.95" transform="rotate(-32 -10 -13)"/>'
      '<path d="M -30 26 A 40 40 0 0 0 30 26" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="2.5" stroke-linecap="round"/>'
      "</g>")


def srgb(h):
    h = h.lstrip("#"); return "srgb:%.5f,%.5f,%.5f,1.00000" % tuple(int(h[k:k+2], 16)/255 for k in (0, 2, 4))


def group(members, gi):
    chips = [m for m in members if isinstance(m, int)]
    layers = []
    if "pin" in members:
        layers.append({"name": "pin", "image-name": "pin.svg"})
    for n, i in enumerate(chips):
        behind = chips[n+1:]
        if P["bake"] and len(chips) > 1:
            # white layers make dark mode render the whole group as pale glass, so the baked highlight is light-only
            layers.append({"name": "spec-%d" % i, "image-name": "spec-%d.svg" % i, "opacity": P["spec_opacity"],
                           "hidden-specializations": [{"appearance": "dark", "value": True}]})
        layers.append({"name": "chip-%d" % i, "image-name": "chip-%d.svg" % i})
        if P["bake"] and behind:
            layers.append({"name": "shadow-%d" % i, "image-name": inner_shadow(i, behind, "g%d" % gi)})
    if "caustic" in members:
        layers.append({"name": "caustic", "image-name": "caustic.svg", "opacity": P["caustic_opacity"]})
    names = {"pin": "Pin", "caustic": "Caustic"}
    g = {"name": " + ".join(names[m] if m in names else "Chip %d" % m for m in members), "layers": layers}
    if chips:
        g.update({"blur-material": P["blur"], "lighting": "individual",
                  "shadow": {"kind": "layer-color", "opacity": P["shadow"]}, "specular": True,
                  "translucency": {"enabled": True, "value": P["translucency"]}})
        if P["refract"]:
            g["refractivity"] = {"depth": P["refract"][1], "enabled": True, "strength": P["refract"][0]}
    elif "pin" in members:
        # sharing with the caustic: specular would put a hard glass edge on its soft blur, so the pin's
        # highlight and shadow are baked into pin.svg and the group stays flat
        g.update({"shadow": {"kind": "none" if pin_shares else "neutral", "opacity": 0 if pin_shares else 0.5},
                  "specular": not pin_shares, "translucency": {"enabled": False, "value": 0}})
    else:
        g.update({"shadow": {"kind": "none", "opacity": 0}, "specular": False, "translucency": {"enabled": False, "value": 0}})
    return g


doc = {
    "features": ["refractivity"],
    "groups": [group(m, gi) for gi, m in enumerate(P["groups"])],
    "supported-platforms": {"squares": "shared"},
}
if P["bg"]:
    doc["fill"] = {"linear-gradient": [srgb(P["bg"][0]), srgb(P["bg"][1])],
                   "orientation": {"start": {"x": 0.2, "y": 0}, "stop": {"x": 0.8, "y": 1}}}
# drop artwork no layer uses (highlights for chips that keep their own group, the pin when it is left out)
used = {l["image-name"] for g in doc["groups"] for l in g["layers"]}
for name in os.listdir(A):
    if name not in used:
        os.remove(os.path.join(A, name))
with open(os.path.join(OUT, "icon.json"), "w") as fh:
    json.dump(doc, fh, indent=2); fh.write("\n")
print(len(doc["groups"]), "groups")
