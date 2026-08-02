#!/usr/bin/env python3
"""
mac_frame_reel.py — assemble a LANDSCAPE macOS app-preview reel (1920x1080, Apple's mac
requirement) from per-tab window clips recorded by mac_reel.sh.

Layout mirrors the mac screenshots (TwoColumnStyle): caption on the left, the app window on
the right, on the brand gradient. Scenes cross-fade into each other and into a branded outro.

Usage:
  mac_frame_reel.py --scenes reels/ephemeris_scenes_mac.json --clips-dir <dir> \
                    --app-dir <app> --out-dir <app>/marketing/aso/mac/video
"""
import argparse, json, os, subprocess, sys
from pathlib import Path

MARKETING = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(MARKETING))
from screenshots_generator.helpers import (            # noqa: E402
    create_gradient_background, create_rounded_rectangle_mask, add_shadow,
    load_or_get_font, wrap_text, font_covers,
)
from PIL import Image, ImageDraw                        # noqa: E402

ENC = ["-c:v", "libx264", "-profile:v", "high", "-crf", "20",
       "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an"]


def run(cmd): subprocess.run(cmd, check=True)
def even(n): return int(n) - (int(n) % 2)


def probe_wh(p):
    o = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", str(p)]).decode().strip()
    return tuple(int(x) for x in o.split("x"))


def bold_font(size, text=""):
    """Bold where possible, but COVERAGE WINS — pass the text. Both faces below are Latin-only, so
    a Japanese caption in either renders as □□□□ and nothing errors: the .notdef box reports a
    perfectly normal width. Same trap as `store_preview.py` and `frame_reel.py`; this was the third
    copy of it."""
    for p in ("/System/Library/Fonts/HelveticaNeue.ttc", "/Library/Fonts/Arial Bold.ttf"):
        if os.path.exists(p):
            try:
                from PIL import ImageFont
                f = ImageFont.truetype(p, size)
            except Exception:
                continue
            if not text or font_covers(f, text):
                return f
    return load_or_get_font(None, size, text)


def render_assets(cfg, clips_dir, work, app_dir):
    W, H = cfg["canvas"]; st = cfg["style"]
    tcw = int(W * st["text_col_percent"] / 100)
    pad, bw, radius, bcolor = st["side_padding"], st["border_width"], st["border_radius"], st["border_color"]

    cw, ch = probe_wh(Path(clips_dir) / cfg["scenes"][0]["clip"])
    ratio = cw / ch
    avail_w, avail_h = (W - tcw) - 2 * pad, H - 2 * pad
    if avail_w / avail_h > ratio:
        WH = even(avail_h); WW = even(WH * ratio)
    else:
        WW = even(avail_w); WH = even(WW / ratio)
    WX = tcw + ((W - tcw) - WW) // 2
    WY = (H - WH) // 2
    geom = dict(WW=WW, WH=WH, WX=WX, WY=WY)

    create_rounded_rectangle_mask((WW, WH), radius).save(work / "vmask.png")

    bg = create_gradient_background(W, H, st["bg_color_top"], st["bg_color_bottom"]).convert("RGBA")
    frame = Image.new("RGBA", (WW + 2 * bw, WH + 2 * bw), bcolor)
    frame.putalpha(create_rounded_rectangle_mask((WW + 2 * bw, WH + 2 * bw), radius + bw))
    bg.alpha_composite(add_shadow(frame, (0, 24), 60, "#000000"), (WX - bw - 60, WY - bw - 60 + 24))
    bg.alpha_composite(frame, (WX - bw, WY - bw))
    bg.convert("RGB").save(work / "bg.png")

    tx = pad + 20
    for i, sc in enumerate(cfg["scenes"]):
        cap = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(cap)
        # Per scene, from that scene's own text — one font chosen up front can only suit whichever
        # language the first caption happens to be in.
        title_font = bold_font(int(W * 0.040), sc["title"])
        sub_font = load_or_get_font(None, int(W * 0.023), sc["subtitle"])
        tlines = wrap_text(sc["title"], title_font, tcw - pad - tx)
        slines = wrap_text(sc["subtitle"], sub_font, tcw - pad - tx)
        th, sh = len(tlines) * int(W * 0.05), len(slines) * int(W * 0.032)
        y = (H - th - sh - int(W * 0.02)) // 2
        for ln in tlines:
            d.text((tx, y), ln, font=title_font, fill=st["title_color"]); y += int(W * 0.05)
        y += int(W * 0.02)
        for ln in slines:
            d.text((tx, y), ln, font=sub_font, fill=st["subtitle_color"]); y += int(W * 0.032)
        cap.save(work / f"cap_{i}.png")

    outro = create_gradient_background(W, H, st["bg_color_top"], st["bg_color_bottom"]).convert("RGBA")
    app = cfg["app"]; icon_path = Path(app_dir) / app["icon"]
    cxp = W // 2; iy = int(H * 0.24)
    if icon_path.exists():
        isz = int(H * 0.30)
        icon = Image.open(icon_path).convert("RGBA").resize((isz, isz), Image.Resampling.LANCZOS)
        icon.putalpha(create_rounded_rectangle_mask((isz, isz), int(isz * 0.22)))
        outro.alpha_composite(add_shadow(icon, (0, 16), 40, "#000000"), (cxp - isz // 2 - 40, iy - 40 + 16))
        outro.alpha_composite(icon, (cxp - isz // 2, iy)); iy += isz + int(H * 0.04)
    od = ImageDraw.Draw(outro)
    nf = bold_font(int(H * 0.09), app["name"]); nw = od.textlength(app["name"], font=nf)
    od.text((cxp - nw / 2, iy), app["name"], font=nf, fill=st["title_color"]); iy += int(H * 0.11)
    tf = load_or_get_font(None, int(H * 0.038), app["tagline"]); tw = od.textlength(app["tagline"], font=tf)
    od.text((cxp - tw / 2, iy), app["tagline"], font=tf, fill=st["subtitle_color"])
    outro.convert("RGB").save(work / "outro.png")
    return geom


def main():
    ap = argparse.ArgumentParser()
    for a in ("--scenes", "--clips-dir", "--app-dir", "--out-dir"): ap.add_argument(a, required=True)
    args = ap.parse_args()
    cfg = json.load(open(args.scenes))
    W, H = cfg["canvas"]; dur = float(cfg["scene_dur"]); xf = float(cfg["xfade"])
    work = Path(args.out_dir) / "_assets"; work.mkdir(parents=True, exist_ok=True)
    print("▶ rendering mac frame assets")
    g = render_assets(cfg, args.clips_dir, work, args.app_dir)

    # ── composite each scene (window + caption on bg) ──
    scene_mp4s = []
    for i, sc in enumerate(cfg["scenes"]):
        out = work / f"scene_{i}.mp4"
        run(["ffmpeg", "-y", "-loglevel", "error",
             "-loop", "1", "-i", str(work / "bg.png"),
             "-i", str(Path(args.clips_dir) / sc["clip"]),
             "-i", str(work / "vmask.png"),
             "-loop", "1", "-i", str(work / f"cap_{i}.png"),
             "-filter_complex",
             f"[1:v]scale={g['WW']}:{g['WH']}:flags=lanczos,setsar=1[vs];[vs][2:v]alphamerge[vr];"
             f"[0:v][vr]overlay={g['WX']}:{g['WY']}[b];[b][3:v]overlay=0:0,fps=30,format=yuv420p[v]",
             "-map", "[v]", "-t", str(dur), "-r", "30", *ENC, str(out)])
        scene_mp4s.append(out)
    outro = work / "outro.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", str(cfg["outro_dur"]),
         "-i", str(work / "outro.png"), "-vf", "fps=30,format=yuv420p,setsar=1,fade=t=in:st=0:d=0.4",
         "-r", "30", *ENC, str(outro)])
    clips = scene_mp4s + [outro]

    # ── cross-fade chain ──
    inputs, fc, prev, off = [], [], "0:v", 0.0
    for c in clips: inputs += ["-i", str(c)]
    durs = [dur] * len(scene_mp4s) + [float(cfg["outro_dur"])]
    for i in range(1, len(clips)):
        off += durs[i - 1] - xf
        lbl = "v" if i == len(clips) - 1 else f"x{i}"
        fc.append(f"[{prev}][{i}:v]xfade=transition=fade:duration={xf}:offset={off:.3f}[{lbl}]")
        prev = lbl
    out = Path(args.out_dir) / f"framed_preview_{W}x{H}.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", *inputs,
         "-filter_complex", ";".join(fc), "-map", "[v]", "-r", "30", *ENC, str(out)])
    d = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "csv=p=0", str(out)]).decode().strip()
    print(f"\n✅ mac reel: {out}  {probe_wh(out)[0]}x{probe_wh(out)[1]}  {float(d):.1f}s  {os.path.getsize(out)//1024}KB")


if __name__ == "__main__":
    main()
