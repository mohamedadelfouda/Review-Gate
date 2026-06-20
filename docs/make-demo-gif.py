#!/usr/bin/env python3
"""Render the animated terminal-style demo GIF for review-gate.

The on-screen text mirrors the REAL output captured by running the tool
(commit blocked -> attest -> commit lands). Re-run after editing LINES to
regenerate the asset:  python3 docs/make-demo-gif.py
Requires Pillow and a DejaVu Sans Mono font."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "review-gate-demo.gif")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
FS = 21
font = ImageFont.truetype(FONT, FS)
fontb = ImageFont.truetype(FONT_B, FS)

# colors (GitHub dark)
BG = (13, 17, 23)
BAR = (28, 33, 40)
FG = (201, 209, 217)
GREEN = (63, 185, 80)
RED = (248, 81, 73)
CYAN = (88, 166, 255)
GREY = (139, 148, 158)
WHITE = (240, 246, 252)

# each rendered line is a list of (text, color, bold) spans
def cmd(c): return [("$ ", GREEN, True), (c, WHITE, True)]

LINES = [
    cmd('git commit -m "add feature"'),
    [("", FG, False)],
    [("  REVIEW GATE ", RED, True), ("— review has NOT run for this commit", FG, False)],
    [("  main @ e4b1377 · commit BLOCKED", GREY, False)],
    [("  Run the gate, then attest:", FG, False)],
    [("    review-gate attest --ran review,clean-code,docs", CYAN, False)],
    [("", FG, False)],
    cmd('review-gate attest --ran review,clean-code,docs'),
    [("", FG, False)],
    [("  ", FG, False), ("▶", CYAN, True), (" review-gate attest [commit mode] — main @ e4b1377", FG, False)],
    [("    • binding: staged tree 80f82ab", GREY, False)],
    [("    • gate steps acknowledged: review,clean-code,docs", GREY, False)],
    [("    ✓ typecheck clean", GREEN, False)],
    [("  ✓ attested — commit unlocked", GREEN, True)],
    [("", FG, False)],
    cmd('git commit -m "add feature"'),
    [("", FG, False)],
    [("  [main 8a85825] add feature", GREEN, True), ("   ✓ lands", GREEN, False)],
]

PAD = 24
LH = FS + 9
TOPBAR = 38
CW = font.getbbox("M")[2]  # mono char width
W = 940
H = TOPBAR + PAD*2 + LH*len(LINES)

def draw_frame(n_lines, cursor=True):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # title bar
    d.rectangle([0, 0, W, TOPBAR], fill=BAR)
    for i, col in enumerate([(255,95,86),(255,189,46),(39,201,63)]):
        d.ellipse([18+i*22, 13, 30+i*22, 25], fill=col)
    d.text((W/2-90, 9), "review-gate — demo", font=font, fill=GREY)
    # lines
    y = TOPBAR + PAD
    for li in range(n_lines):
        x = PAD
        for (txt, col, bold) in LINES[li]:
            f = fontb if bold else font
            d.text((x, y), txt, font=f, fill=col)
            x += int(d.textlength(txt, font=f))
        # cursor on last revealed line
        if cursor and li == n_lines-1:
            d.rectangle([x+3, y+3, x+3+CW, y+FS+2], fill=FG)
        y += LH
    return img

frames = []
# reveal line by line
for n in range(1, len(LINES)+1):
    # blank lines reveal fast
    reps = 1 if LINES[n-1] == [("", FG, False)] else 3
    for r in range(reps):
        frames.append(draw_frame(n, cursor=True))
# final hold with blinking cursor
for _ in range(6):
    frames.append(draw_frame(len(LINES), cursor=True))
    frames.append(draw_frame(len(LINES), cursor=False))

# per-line reveal is quick; the final state holds longer with a blinking cursor
durations = []
for n in range(1, len(LINES)+1):
    reps = 1 if LINES[n-1] == [("", FG, False)] else 3
    for r in range(reps):
        durations.append(70)
for _ in range(6):
    durations += [450, 450]

frames[0].save(OUT, save_all=True, append_images=frames[1:],
               duration=durations, loop=0, optimize=True)
print("wrote", OUT, "-", len(frames), "frames", W, "x", H)
