#!/usr/bin/env python3
"""
store_preview.py — build an App-Store-compliant app preview: FULL-BLEED screen capture only.

Guideline 2.3.4 (Performance – Accurate Metadata) forbids, in an *app preview*:
  • framing around the video screen capture (background/letterbox/caption bands), and
  • device images or device frames.
Screenshots may be framed; previews may NOT. Apple's own remedy wording:
  "revise the app preview to only use video screen captures of the app that may include
   narration and video or textual overlays for added clarity."

So this renderer is deliberately the anti-`frame_reel.py`: no gradient background, no device
bezel, no branded outro card — the app fills every pixel. Captions, when enabled, are drawn
*on top of* the running app (the one thing Apple explicitly still allows).

Outputs (into --out-dir):
  store_preview_<W>x<H>_plain.mp4       full-bleed capture, no text
  store_preview_<W>x<H>_captions.mp4    full-bleed capture + overlaid scene captions
  …_music.mp4 for whichever variants were rendered, when --audio is given

Usage:
  store_preview.py --scenes <app>/marketing/reels/scenes.json \
                   --video  <app>/marketing/aso/ios/video/full.mp4 \
                   --out-dir <app>/marketing/aso/ios/video \
                   --audio  <app>/marketing/audio/jazz_groove.wav
"""
import argparse, json, os, subprocess, sys
from pathlib import Path

MARKETING = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(MARKETING))
from screenshots_generator.helpers import load_or_get_font, wrap_text   # noqa: E402
from PIL import Image, ImageDraw                                        # noqa: E402

ENC = ["-c:v", "libx264", "-profile:v", "high", "-crf", "20",
       "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an"]
FADE = 0.35          # caption alpha fade, seconds


def run(cmd):
    subprocess.run(cmd, check=True)


def probe(path, entries, stream=True):
    sel = ["-select_streams", "v:0"] if stream else []
    out = subprocess.check_output(["ffprobe", "-v", "error", *sel, "-show_entries", entries,
                                   "-of", "csv=p=0:s=x", str(path)]).decode().strip()
    return out.splitlines()[0]


def bold_font(size):
    for p in ("/System/Library/Fonts/HelveticaNeue.ttc",
              "/System/Library/Fonts/SFNS.ttf",
              "/Library/Fonts/Arial Bold.ttf"):
        if os.path.exists(p):
            try:
                from PIL import ImageFont
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return load_or_get_font(None, size)


def render_captions(cfg, work):
    """One full-canvas RGBA PNG per scene: title + subtitle over a legibility backing.

    Two backing styles (the app still fills every pixel either way — this is a *textual overlay*,
    which Guideline 2.3.4 explicitly allows, not framing):
      • gradient scrim (default) — fine over dark or busy app content;
      • `caption_ribbon: true`   — a contained band sized to the text. Use this for LIGHT-themed
        apps, where a gradient strong enough to carry white text ends up greying out the whole
        lower third of the UI.
    """
    W, H = cfg["canvas"]
    st = cfg["style"]
    pad = st["side_padding"]
    title_font = bold_font(int(W * 0.058))
    sub_font = load_or_get_font(None, int(W * 0.038))
    title_lh, sub_lh = int(W * 0.070), int(W * 0.050)
    gap = int(W * 0.015)
    ribbon = bool(st.get("caption_ribbon", False))
    ribbon_a = int(round(255 * float(st.get("ribbon_opacity", 0.55))))
    ribbon_padv = int(H * float(st.get("ribbon_pad_percent", 0.035)))
    scrim_h = int(H * float(st.get("scrim_height_percent", 0.30)))
    scrim_a = int(st.get("scrim_opacity", 209))          # 0–255 alpha at the very bottom
    scrim_g = float(st.get("scrim_gamma", 1.6))          # lower = darkens higher up the frame

    for i, sc in enumerate(cfg["scenes"]):
        cap = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(cap)
        tlines = wrap_text(sc["title"], title_font, W - 2 * pad)
        slines = wrap_text(sc["subtitle"], sub_font, W - 2 * pad)
        block = len(tlines) * title_lh + gap + len(slines) * sub_lh
        y0 = H - int(H * 0.055) - block

        if ribbon:
            # Full-width band behind the text only. Hard top edge by default — a feathered edge
            # reads as a muddy smear over a light UI. `ribbon_feather_percent` re-enables a fade.
            top = max(0, y0 - ribbon_padv)
            band = Image.new("RGBA", (W, H - top), (0, 0, 0, ribbon_a))
            feather = int(H * float(st.get("ribbon_feather_percent", 0.0)))
            if feather > 0:
                bd = ImageDraw.Draw(band)
                feather = min(feather, H - top)
                for yy in range(feather):
                    bd.line([(0, yy), (W, yy)], fill=(0, 0, 0, int(ribbon_a * (yy / feather))))
            cap.alpha_composite(band, (0, top))
        else:
            scrim = Image.new("RGBA", (W, scrim_h))
            sd = ImageDraw.Draw(scrim)
            for y in range(scrim_h):
                sd.line([(0, y), (W, y)], fill=(0, 0, 0, int(scrim_a * (y / scrim_h) ** scrim_g)))
            cap.alpha_composite(scrim, (0, H - scrim_h))

        y = y0
        for ln in tlines:
            d.text(((W - d.textlength(ln, font=title_font)) // 2, y), ln,
                   font=title_font, fill=st["title_color"])
            y += title_lh
        y += gap
        for ln in slines:
            d.text(((W - d.textlength(ln, font=sub_font)) // 2, y), ln,
                   font=sub_font, fill=st["subtitle_color"])
            y += sub_lh
        cap.save(work / f"ovl_{i}.png")


def strip_pad_filter(video, source_aspect):
    """`make_reel.sh` conforms with force_original_aspect_ratio=decrease + pad, so full.mp4 can
    carry a 1–2px black letterbox. Recompute that inner rect from the ORIGINAL capture aspect and
    crop it away — deterministic, unlike cropdetect on a near-black UI. Even a hairline bar is
    'framing around the video screen capture'."""
    if not source_aspect:
        return None
    aw, ah = (int(x) for x in source_aspect.lower().split("x"))
    vw, vh = (int(x) for x in probe(video, "stream=width,height").split("x"))
    scale = min(vw / aw, vh / ah)
    iw, ih = int(aw * scale) - int(aw * scale) % 2, int(ah * scale) - int(ah * scale) % 2
    if (iw, ih) == (vw, vh):
        return None
    return f"crop={iw}:{ih}:{(vw - iw) // 2}:{(vh - ih) // 2}"


def fit_filter(video, W, H, source_aspect=None):
    """Scale-and-crop to EXACTLY WxH — fill the frame, never pad (pad bars read as framing)."""
    vw, vh = (int(x) for x in probe(video, "stream=width,height").split("x"))
    strip = strip_pad_filter(video, source_aspect)
    if strip:
        vw, vh = (int(x) for x in strip.split("=")[1].split(":")[:2])
    if vw / vh > W / H:                      # source wider → match height, crop the sides
        sw, sh = max(W, round(vw * H / vh)), H
    else:                                    # source taller → match width, crop top/bottom
        sw, sh = W, max(H, round(vh * W / vw))
    sw += sw % 2
    sh += sh % 2
    chain = [strip] if strip else []
    chain += [f"scale={sw}:{sh}:flags=lanczos",
              f"crop={W}:{H}:(iw-{W})/2:(ih-{H})/2", "setsar=1"]
    return ",".join(chain)


def compose_segments(cfg, video, work, out_dir, captions, source_aspect=None):
    """Scenes carry `src: [start, end]` — cut those windows out of the walkthrough and hard-cut
    them together, dropping the catalog-scrolling dead time between tools. Each caption is
    overlaid on its own segment, so timing can't drift out of sync with the content."""
    W, H = cfg["canvas"]
    scenes = cfg["scenes"]
    tag = "captions" if captions else "plain"
    out = Path(out_dir) / f"store_preview_{W}x{H}_{tag}.mp4"
    fit = fit_filter(video, W, H, source_aspect)

    parts, content = [], 0.0
    for i, sc in enumerate(scenes):
        s, e = (float(x) for x in sc["src"])
        dur = e - s
        content += dur
        seg = work / f"seg_{tag}_{i}.mp4"
        inputs = ["-ss", str(s), "-to", str(e), "-i", str(video)]
        fc = [f"[0:v]{fit},fps=30[base]"]
        if captions:
            inputs += ["-loop", "1", "-i", str(work / f"ovl_{i}.png")]
            fc.append(f"[1:v]format=rgba,fade=t=in:st=0.3:d={FADE}:alpha=1,"
                      f"fade=t=out:st={dur - 0.3 - FADE:.2f}:d={FADE}:alpha=1[o]")
            fc.append("[base][o]overlay=0:0[v]")
        else:
            fc.append("[base]null[v]")
        run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(fc),
             "-map", "[v]", "-t", str(dur), *ENC, str(seg)])
        parts.append(seg)

    listing = work / f"concat_{tag}.txt"
    listing.write_text("".join(f"file '{p.name}'\n" for p in parts))
    speed = max(1.0, content / float(cfg["preview_maxlen"]))
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-vf", f"setpts=PTS/{speed:.6f},fps=30,format=yuv420p", *ENC, str(out)])
    return out, speed


def compose(cfg, video, work, out_dir, captions, source_aspect=None):
    if all("src" in sc for sc in cfg["scenes"]):
        return compose_segments(cfg, video, work, out_dir, captions, source_aspect)

    W, H = cfg["canvas"]
    content = float(cfg["content_len"])
    speed = max(1.0, content / float(cfg["preview_maxlen"]))
    scenes = cfg["scenes"]
    tag = "captions" if captions else "plain"
    out = Path(out_dir) / f"store_preview_{W}x{H}_{tag}.mp4"

    inputs = ["-i", str(video)]
    fc = [f"[0:v]{fit_filter(video, W, H, source_aspect)},fps=30[base]"]
    prev = "base"
    if captions:
        for i in range(len(scenes)):
            inputs += ["-loop", "1", "-i", str(work / f"ovl_{i}.png")]
        for i, sc in enumerate(scenes):
            s, e = float(sc["start"]), float(sc["end"])
            fc.append(f"[{i + 1}:v]format=rgba,"
                      f"fade=t=in:st={s}:d={FADE}:alpha=1,"
                      f"fade=t=out:st={max(s, e - FADE):.2f}:d={FADE}:alpha=1[o{i}]")
            nxt = f"m{i}"
            fc.append(f"[{prev}][o{i}]overlay=0:0:enable='between(t,{s},{e})'[{nxt}]")
            prev = nxt
    # speed-fit the whole walkthrough under Apple's 30s cap (no outro card — not "app in use")
    fc.append(f"[{prev}]setpts=PTS/{speed:.6f},fps=30,format=yuv420p[v]")
    run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(fc),
         "-map", "[v]", "-t", str(content / speed), *ENC, str(out)])
    return out, speed


def mux(video, bed):
    """App Store requires a real AAC track on every preview — never upload a video-only file."""
    dur = float(probe(video, "format=duration", stream=False))
    out = Path(str(video).replace(".mp4", "_music.mp4"))
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(video), "-i", str(bed),
         "-filter_complex",
         f"[1:a]atrim=0:{dur},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,"
         f"afade=t=out:st={dur - 1.5:.2f}:d=1.5,volume=0.85[a]",
         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k",
         "-ar", "44100", "-movflags", "+faststart", str(out)])
    return out


def report(path):
    wh = probe(path, "stream=width,height")
    dur = float(probe(path, "format=duration", stream=False))
    fps = probe(path, "stream=r_frame_rate")
    codecs = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                      "stream=codec_type,codec_name", "-of", "csv=p=0",
                                      str(path)]).decode().split()
    print(f"   {path}\n     {wh}  {dur:.1f}s  {fps}  {' '.join(codecs)}  "
          f"{os.path.getsize(path) // 1024}KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", required=True)
    ap.add_argument("--video", required=True, help="conformed natural-speed walkthrough (full.mp4)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--audio", help="music bed .wav; muxed as AAC 256k (required for upload)")
    ap.add_argument("--variants", default="plain,captions")
    ap.add_argument("--source-aspect", help="WxH of the ORIGINAL capture (e.g. 1320x2868) — used "
                                            "to strip the letterbox make_reel.sh padded in")
    a = ap.parse_args()

    cfg = json.load(open(a.scenes))
    work = Path(a.out_dir) / "_assets"
    work.mkdir(parents=True, exist_ok=True)
    wanted = [v.strip() for v in a.variants.split(",") if v.strip()]

    if "captions" in wanted:
        print("▶ rendering caption overlays")
        render_captions(cfg, work)
    for variant in wanted:
        print(f"▶ compositing full-bleed preview ({variant})")
        out, speed = compose(cfg, a.video, work, a.out_dir, variant == "captions", a.source_aspect)
        print(f"✅ {variant} (walkthrough x{speed:.2f}, no frame / no bezel / no outro)")
        report(out)
        if a.audio:
            report(mux(out, a.audio))


if __name__ == "__main__":
    main()
