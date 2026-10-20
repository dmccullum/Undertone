# Claude skills

`undertone-backgrounds/` is a Claude Code skill that renders Undertone's Organic style with film
grain from Node or in a browser. See its [SKILL.md](undertone-backgrounds/SKILL.md).

## Install

```sh
zsh scripts/install-skill.sh
```

Copies the skill to `~/.claude/skills/undertone-backgrounds`. Run it again after changing the files
here.

## Check parity with the app

`scripts/undertone.js` must produce the same bytes as `GradientRenderer` for Organic recipes. Put
some `.json` recipes in a folder, then:

```sh
UNDERTONE_RENDER_IN=recipes UNDERTONE_RENDER_OUT=swift UNDERTONE_RENDER_SIZE=1350 \
  swift test -c release --filter SampleRenderTests
for f in recipes/*.json; do
  node skills/undertone-backgrounds/scripts/render.js --recipe "$f" --size 1080x1350 --out "js/$(basename "$f" .json).png"
done
```

`UNDERTONE_RENDER_SIZE` is the long side, so give the recipes a matching aspect ratio
(1080×1350 above). Then compare `swift/*.png` with `js/*.png`; every byte should match.
