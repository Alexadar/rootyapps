#!/usr/bin/env python3
"""
frame_reel.py — wrap a raw app-preview capture in a marketing frame: gradient background,
a rounded device frame, per-scene ad captions ("here it does this"), and a branded outro.

Reuses the screenshot generator's styling (fonts, gradients, rounded masks, shadows) so the
reel matches the App Store screenshots. Timing is deterministic: the tour runs on a metronome
(ReelTour.swift), so scene windows are the constants in <app>_scenes.json — no timestamp
parsing needed.

Outputs (into --out-dir):
  framed_full.mp4                — natural speed, whole-app walkthrough + outro
  framed_preview_886x1920.mp4    — speed-fit so the whole ad lands within Apple's 30s cap

Usage:
  frame_reel.py --scenes reels/ephemeris_scenes.json \
                --video  <app>/marketing/aso/ios/video/full.mp4 \
                --app-dir <app> --out-dir <app>/marketing/aso/ios/video
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


def run(cmd):
    subprocess.run(cmd, check=True)


def probe_wh(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", path]).decode().strip()
    w, h = out.split("x")
    return int(w), int(h)


def bold_font(size, text=""):
    """Bold caption face that can actually render `text`.

    The Latin bold faces below have no CJK glyphs, so a Japanese caption came out as tofu boxes
    over a perfectly Japanese app frame — and nothing errored. Pass the caption and fall back to
    the coverage-checked chain when the bold face cannot draw it.
    """
    for p in ("/System/Library/Fonts/HelveticaNeue.ttc",
              "/System/Library/Fonts/SFNS.ttf",
              "/Library/Fonts/Arial Bold.ttf"):
        if os.path.exists(p):
            try:
                from PIL import ImageFont
                f = ImageFont.truetype(p, size)
            except Exception:
                continue
            if not text or font_covers(f, text):
                return f
    return load_or_get_font(None, size, text)


def even(n):
    return int(n) - (int(n) % 2)


def render_assets(cfg, video, work, app_dir):
    W, H = cfg["canvas"]
    st = cfg["style"]
    band = int(H * st["caption_band_percent"] / 100)
    pad = st["side_padding"]
    bw, radius = st["border_width"], st["border_radius"]
    bcolor = st["border_color"]

    # ── video geometry: fit source aspect into the region below the caption band ──
    vw_src, vh_src = probe_wh(video)
    ratio = vw_src / vh_src
    avail_w = W - 2 * pad
    avail_h = H - band - int(H * 0.03)
    if avail_w / avail_h > ratio:
        VH = even(avail_h); VW = even(VH * ratio)
    else:
        VW = even(avail_w); VH = even(VW / ratio)
    VX = (W - VW) // 2
    VY = band + (avail_h - VH) // 2
    geom = dict(VW=VW, VH=VH, VX=VX, VY=VY)

    # rounded alpha mask for the video corners
    create_rounded_rectangle_mask((VW, VH), radius).save(work / "vmask.png")

    # ── background: gradient + shadow + rounded frame border ──
    bg = create_gradient_background(W, H, st["bg_color_top"], st["bg_color_bottom"]).convert("RGBA")
    frame_rect = Image.new("RGBA", (VW + 2 * bw, VH + 2 * bw), bcolor)
    frame_rect.putalpha(create_rounded_rectangle_mask((VW + 2 * bw, VH + 2 * bw), radius + bw))
    shadow = add_shadow(frame_rect, (0, 24), 60, "#000000")
    bg.alpha_composite(shadow, (VX - bw - 60, VY - bw - 60 + 24))
    bg.alpha_composite(frame_rect, (VX - bw, VY - bw))
    bg.convert("RGB").save(work / "bg.png")

    # ── caption cards: title + subtitle centred in the top band ──
    # Caption type is sized from canvas WIDTH, which is right for a portrait canvas and wrong
    # for a landscape one: at 1920 wide the title alone is 138px and overflows the band, printing
    # over the device frame. `caption_scale` lets a wide canvas shrink the type without changing
    # the proportions every portrait reel already depends on. Default 1.0 = unchanged.
    cs = st.get("caption_scale", 1.0)
    for i, sc in enumerate(cfg["scenes"]):
        # Per scene, not hoisted: font choice now depends on the caption's own characters, so a
        # Japanese line gets a CJK face while a Latin one keeps Helvetica. (Hoisting these while
        # referencing `sc` was an UnboundLocalError that killed framing outright.)
        title_font = bold_font(int(W * 0.072 * cs), sc["title"])      # ~64px at 886
        sub_font = load_or_get_font(None, int(W * 0.044 * cs), sc.get("subtitle", ""))  # ~39px
        cap = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(cap)
        tlines = wrap_text(sc["title"], title_font, W - 2 * pad)
        slines = wrap_text(sc["subtitle"], sub_font, W - 2 * pad)
        # Line heights and the gap scale with `cs` too. Scaling the FONT but not the leading made
        # the block measure ~2x its real height, so `y` went negative and the first title line was
        # drawn off the top of the canvas while the subtitle spilled over the device frame. It only
        # showed on a caption that wrapped — English fitted on one line, French did not.
        tline_h = int(W * 0.084 * cs)
        sline_h = int(W * 0.056 * cs)
        gap = int(W * 0.02 * cs)
        th = len(tlines) * tline_h
        sh = len(slines) * sline_h
        y = (band - th - sh - gap) // 2 + int(H * 0.02)
        for ln in tlines:
            w = d.textlength(ln, font=title_font)
            d.text(((W - w) // 2, y), ln, font=title_font, fill=st["title_color"])
            y += tline_h
        y += gap
        for ln in slines:
            w = d.textlength(ln, font=sub_font)
            d.text(((W - w) // 2, y), ln, font=sub_font, fill=st["subtitle_color"])
            y += sline_h
        cap.save(work / f"cap_{i}.png")

    # ── outro card: gradient + app icon + name + tagline ──
    outro = create_gradient_background(W, H, st["bg_color_top"], st["bg_color_bottom"]).convert("RGBA")
    app = cfg["app"]
    icon_path = Path(app_dir) / app["icon"]
    iy = int(H * 0.30)
    if icon_path.exists():
        isz = int(W * 0.34)
        icon = Image.open(icon_path).convert("RGBA").resize((isz, isz), Image.Resampling.LANCZOS)
        icon.putalpha(create_rounded_rectangle_mask((isz, isz), int(isz * 0.22)))
        ish = add_shadow(icon, (0, 18), 44, "#000000")
        outro.alpha_composite(ish, ((W - ish.width) // 2, iy - 44 + 18))
        outro.alpha_composite(icon, ((W - isz) // 2, iy))
        iy += isz + int(H * 0.03)
    od = ImageDraw.Draw(outro)
    nf = bold_font(int(W * 0.10 * st.get("caption_scale", 1.0)), app["name"])
    nw = od.textlength(app["name"], font=nf)
    od.text(((W - nw) // 2, iy), app["name"], font=nf, fill=st["title_color"])
    iy += int(W * 0.12)
    tf = load_or_get_font(None, int(W * 0.046 * st.get("caption_scale", 1.0)), app["tagline"])
    tw = od.textlength(app["tagline"], font=tf)
    od.text(((W - tw) // 2, iy), app["tagline"], font=tf, fill=st["subtitle_color"])
    outro.convert("RGB").save(work / "outro.png")
    return geom


def compose(cfg, video, work, out_dir):
    W, H = cfg["canvas"]
    g = cfg["_geom"]
    scenes = cfg["scenes"]
    content = float(cfg["content_len"])
    outro_dur = float(cfg["outro_dur"])
    main = work / "main_framed.mp4"
    outro_mp4 = work / "outro.mp4"

    # ── Pass A: bg + rounded video + timed captions ──
    inputs = ["-loop", "1", "-i", str(work / "bg.png"),
              "-i", str(video),
              "-i", str(work / "vmask.png")]
    for i in range(len(scenes)):
        inputs += ["-loop", "1", "-i", str(work / f"cap_{i}.png")]
    fc = [f"[1:v]scale={g['VW']}:{g['VH']}:flags=lanczos,setsar=1[vs]",
          "[vs][2:v]alphamerge[vr]",
          f"[0:v][vr]overlay={g['VX']}:{g['VY']}[b0]"]
    prev = "b0"
    for i, sc in enumerate(scenes):
        cap_in = 3 + i
        nxt = f"c{i}"
        tag = f",format=yuv420p[v]" if i == len(scenes) - 1 else f"[{nxt}]"
        fc.append(f"[{prev}][{cap_in}:v]overlay=0:0:enable='between(t,{sc['start']},{sc['end']})'{tag}")
        prev = nxt
    run(["ffmpeg", "-y", "-loglevel", "error", *inputs,
         "-filter_complex", ";".join(fc), "-map", "[v]",
         "-t", str(content), "-r", "30", *ENC, str(main)])

    # ── outro clip ──
    run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", str(outro_dur),
         "-i", str(work / "outro.png"),
         "-vf", "fps=30,format=yuv420p,setsar=1,fade=t=in:st=0:d=0.4",
         *ENC, str(outro_mp4)])

    # ── framed_full = main + outro ──
    full_out = Path(out_dir) / "framed_full.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(main), "-i", str(outro_mp4),
         "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0,format=yuv420p[v]",
         "-map", "[v]", *ENC, str(full_out)])

    # ── framed_preview = speed-fit(main) + outro, within the App Store cap ──
    target_main = float(cfg["preview_maxlen"]) - outro_dur
    speed = max(1.0, content / target_main)
    prev_out = Path(out_dir) / f"framed_preview_{W}x{H}.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(main), "-i", str(outro_mp4),
         "-filter_complex",
         f"[0:v]setpts=PTS/{speed},fps=30[m];[m][1:v]concat=n=2:v=1:a=0,format=yuv420p[v]",
         "-map", "[v]", *ENC, str(prev_out)])
    return full_out, prev_out, speed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", required=True)
    ap.add_argument("--video", required=True)
    ap.add_argument("--app-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()

    cfg = json.load(open(a.scenes))
    work = Path(a.out_dir) / "_assets"
    work.mkdir(parents=True, exist_ok=True)

    print("▶ rendering frame assets")
    cfg["_geom"] = render_assets(cfg, a.video, work, a.app_dir)
    print("▶ compositing framed reels")
    full_out, prev_out, speed = compose(cfg, a.video, work, a.out_dir)

    def info(p):
        d = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                     "format=duration", "-of", "csv=p=0", str(p)]).decode().strip()
        return f"{probe_wh(str(p))[0]}x{probe_wh(str(p))[1]}  {float(d):.1f}s  {os.path.getsize(p)//1024}KB"
    print(f"\n✅ framed reels (captions x{speed:.2f} on preview)")
    print(f"   framed_full:    {full_out}   {info(full_out)}")
    print(f"   framed_preview: {prev_out}   {info(prev_out)}")


if __name__ == "__main__":
    main()
