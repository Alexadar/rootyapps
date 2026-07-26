# App Store preview reels

Generic tooling to capture a screen-recorded "reel" from the iOS Simulator (iPhone/iPad) or a
real macOS app window, frame it (gradient bg + device/window frame + per-scene captions +
branded outro), and optionally score it with an on-device Stable Audio 3 music bed.

The **scripts here are app-agnostic**; each app owns its own scene config under
`<app>/marketing/reels/scenes*.json` and is selected via env vars.

## ⛔️ NEVER upload a *framed* reel as an App Store preview (READ THIS FIRST)

**Screenshots may be framed. App previews may NOT.** Overtone Lab's iOS 1.0 was rejected
2026-07-09 under **Guideline 2.3.4 — Performance: Accurate Metadata**:

> The app preview includes content that does not sufficiently show the app in use. Specifically,
> the app preview: – Includes framing around the video screen capture of the app. – Includes
> device images and/or device frames. […] revise the app preview to only use video screen
> captures of the app that **may include narration and video or textual overlays** for added
> clarity.

So `frame_reel.py` / `mac_frame_reel.py` output (gradient bg + device bezel + caption band +
branded outro card) is for **the site, socials and internal review only** — never for the store.

| Destination | Renderer | Allowed |
|---|---|---|
| **App Store preview** | **`store_preview.py`** | full-bleed capture; text overlays *on top of* the app; music |
| Screenshots (any) | `generate_screenshots.py` | bg, device frames, caption bands — all fine |
| Site / social reel | `frame_reel.py`, `mac_frame_reel.py` | anything |

`store_preview.py` is the compliant renderer: **no background, no bezel, no letterbox, no outro
card** — the app fills every pixel. It also strips the 1–2px pad bars `make_reel.sh` leaves
(`--source-aspect <capture WxH>`), because even a hairline bar is "framing".

```bash
store_preview.py --scenes <app>/marketing/reels/scenes.json \
                 --video  <app>/marketing/aso/ios/video/full.mp4 \
                 --out-dir <app>/marketing/aso/ios/video \
                 --audio  <app>/marketing/audio/<bed>.wav \
                 --source-aspect 1320x2868          # iPhone 17 Pro Max capture
# → store_preview_886x1920_{plain,captions}[_music].mp4
```

Give each scene a **`src: [start, end]`** window in `scenes*.json` and the segments are cut out
of the walkthrough and hard-cut together — dropping catalog-scrolling dead time, keeping every
tool in the 30s cap at near-natural speed, and pinning each caption to its own segment so
captions can't drift out of sync with the content. Verify the result by tiling it
(`-vf "fps=1/2,scale=160:-1,tile=7x2"`) and *looking* at it before upload.

Note the macOS preview of a live app may still be the old framed cut — Apple approved
Overtone Lab's Mac preview on the same day it rejected the iOS one. It is still non-compliant;
re-render it with `store_preview.py` on the next macOS update rather than as its own submission.

## Pipeline

| File | Role |
|---|---|
| `make_reel.sh` | iPhone/iPad: xcodegen → build-for-testing → pre-launch → `simctl recordVideo` → run the app's `ReelTour` XCUITest → ffmpeg conform → `frame_reel.py` |
| `frame_reel.py` | Portrait compositor: bg + rounded device frame + timed captions + outro; speed-fits the preview to the scene's `preview_maxlen`. **Site/social only — a framed reel is a 2.3.4 rejection as a store preview** |
| `store_preview.py` | **The App Store cut**: full-bleed capture, no frame/bezel/outro, optional caption overlays, `src`-window segment cuts, AAC mux |
| `RecordWindow.swift` | macOS: **ScreenCaptureKit single-window** recorder (occlusion-proof). `swiftc -O RecordWindow.swift -o recordwindow` |
| `mac_frame_reel.py` | macOS landscape (1920×1080) compositor from per-tab window clips (caption-left / window-right) + cross-fades |
| `align_scenes.py` | Turns the tour's `REEL_SCENE` sim-log markers into measured caption windows |
| `<app>/marketing/reels/scenes*.json` | **Per-app** scene config: canvas, captions, branding, timeline, `preview_maxlen` |

Apple spec (all cuts conform to it): 15–30s, ≤30fps, H.264, AAC 256k stereo; 886×1920 (iPhone
6.9"), 1200×1600 (iPad 13"), 1920×1080 (macOS landscape).

## Audio — ALWAYS score, then get approval (READ THIS)

**Always generate the scored `_music.mp4` for every reel and send it to the user for approval.** The
music bed is part of the deliverable, not an optional social extra — the user decides. Treat
`_music.mp4` as **the App Store upload** unless the user explicitly asks for silence. Previews
autoplay **muted** and only play sound when a viewer taps to unmute, so scored audio is safe on the
store and simply rewards the curious.

**Never upload a video-only file.** App Store Connect requires every app preview to carry a valid
**AAC** audio track. A `framed_preview_*.mp4` with *no audio stream* uploads but is then rejected —
*"Your app preview contains unsupported or corrupted audio."* So the only two valid uploads are:
1. `_music.mp4` (scored) — **the default**, and
2. a silent cut **only if the user asks for silence**, and only after muxing a real silent AAC track
   (`ffmpeg -i in.mp4 -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -c:v copy -c:a aac
   -b:a 256k -shortest out.mp4`) — never the raw video-only `framed_preview`.

**Verify before upload:** `ffprobe -show_entries stream=codec_type,codec_name <file>` must list an
`aac` audio stream. Confirm each `appPreview.assetDeliveryState` = `COMPLETE`, `errors=[]` afterward.

## Run (iPhone / iPad)

`make_reel.sh` is parameterised entirely by env vars — point it at any app:

```bash
APP_DIR=/path/to/<app>.swift \
PROJECT=<app>.swift.xcodeproj SCHEME=<app>Reel APP_BUNDLE=<bundle.id> \
SIM_NAME=<booted-6.9"-sim> \
marketing/reels/make_reel.sh
```

Defaults target the reference app when unset. `SCENES` defaults to
`$APP_DIR/marketing/reels/scenes.json`; override per platform:

```bash
# iPad 13"
PLATFORM=ipad SIM_NAME=<ipad-sim> \
  SCENES=$APP_DIR/marketing/reels/scenes_ipad.json marketing/reels/make_reel.sh

# override the shown time zone (default America/Los_Angeles)
REEL_TZ=Europe/Kyiv marketing/reels/make_reel.sh
```

The app drives its own on-screen demo during the Chart scene via env flags the app reads at
launch — e.g. `<APP>_TAB=<n>` (open a tab), `<APP>_DEMO=1` (run the demo animation),
`<APP>_TZ=<id>` (shown time zone). The `ReelTour` XCUITest just navigates + lingers and emits
`REEL_T0 / REEL_SCENE / REEL_END` NSLog markers that `align_scenes.py` reads for caption timing.

## Run (macOS) — occlusion-proof window capture (READ THIS, future Claude)

**The trap:** do NOT use `ffmpeg -f avfoundation`. It can only grab a whole *display*, so the
terminal, dock, other app windows, and anything the user clicks all leak into the "app preview."
And you cannot fix it from outside — macOS blocks AppleScript/System Events from repositioning or
raising another app's window without Accessibility permission, and focus-stealing keeps whatever
the user is in (your terminal) on top. Do not waste renders hiding/moving/raising windows.

**The fix:** `RecordWindow.swift` — an ~85-line ScreenCaptureKit CLI using
`SCContentFilter(desktopIndependentWindow: win)`, which records that window's *own composited
content* — occlusion-proof, nothing else appears, no permission dance, app untouched.

```bash
swiftc -O marketing/reels/RecordWindow.swift -o marketing/reels/recordwindow   # once
./recordwindow <windowID> <seconds> <out.mov>
```

**The four gotchas that kill naive attempts (all handled inside `RecordWindow.swift`):**
1. **`CGS_REQUIRE_INIT` crash** — a plain CLI has no window-server connection. Fix at the top of
   `main`: `_ = NSApplication.shared; NSApplication.shared.setActivationPolicy(.accessory)`.
2. **Black / flicker frames** — SCK emits blank "idle" frames; only append sample buffers whose
   attachment `.status == .complete`.
3. **Window ID via Quartz, NOT AppleScript** — AppleScript throws "Not authorized to send Apple
   events" in a headless shell. Use `CGWindowListCopyWindowInfo([.optionOnScreenOnly,
   .excludeDesktopElements], kCGNullWindowID)` filtered by `kCGWindowOwnerName` + `kCGWindowLayer
   == 0` (layer 0 skips phantom/utility windows). See `winid.swift`.
4. **Single-instance apps ignore your deep-link** — SwiftUI apps are single-instance, so
   relaunching with a new `<APP>_TAB=…`/`<APP>_DEMO=…` env just foregrounds the old window and
   drops your env. `pkill -9` the app and wait for it to die before launching fresh.

Plus a host requirement: **Screen Recording permission** must be granted once to the terminal you
run from (System Settings → Privacy & Security → Screen Recording), or SCK silently records black.

**Per-scene loop:**
```bash
pkill -9 -f "MacOS/<app>"; while pgrep -f "MacOS/<app>" >/dev/null; do sleep 0.3; done
open -n "<app>.app" --env <APP>_TZ=America/Los_Angeles --env <APP>_TAB=0 --env <APP>_DEMO=1
sleep 3.3                                   # let the window settle
WID=$(swift winid.swift)                     # Quartz lookup (owner + layer 0)
./recordwindow "$WID" 7 macclip_chart.mov
```

Then compose + frame:
```bash
mac_frame_reel.py --scenes $APP_DIR/marketing/reels/scenes_mac.json --clips-dir <clips> \
  --app-dir $APP_DIR --out-dir $APP_DIR/marketing/aso/mac/video
```
and mux the audio bed (see below). Screenshots use `screencapture -o -x -l<winID>` — also
window-specific and occlusion-proof, so those are fine on a cluttered screen regardless.

---

## Generate the music bed (Stable Audio 3, on-device, no download)

Uses the pure-MLX Stable Audio 3 port in `~/Projects/AudioProto/reference/stable-audio-3/optimized/mlx`,
running on Apple Silicon GPU (conda env `fantastic`). ~4s to render 10s of audio, ~2 GB RAM.

**Prereqs (one-time):**
```bash
/Users/oleksandr/miniconda3/envs/fantastic/bin/pip install "mlx>=0.30" "sentencepiece>=0.2"
```

**Weights (zero download).** The `sa3-sm-music` weights already exist as `.safetensors` in
`~/Library/Application Support/AudioProto/Weights/` (fetched once, gated — HF `alexadar`).
The MLX CLI wants `.npz` in `optimized/mlx/models/mlx/`; convert the local safetensors instead
of re-downloading (~1.9 GB) — the T5Gemma npz must be rebuilt to include a `META` (config JSON)
blob + `TOKENIZER_MODEL` bytes or `from_npz` errors:
```python
# run with: /Users/oleksandr/miniconda3/envs/fantastic/bin/python
import mlx.core as mx, numpy as np, json
from pathlib import Path
WD  = Path.home()/"Library/Application Support/AudioProto/Weights"
OUT = Path("/Users/oleksandr/Projects/AudioProto/reference/stable-audio-3/optimized/mlx/models/mlx")
OUT.mkdir(parents=True, exist_ok=True)
for src, dst in {"dit_sm-music_f16.safetensors":"dit_sm-music_f16.npz",
                 "same_s_decoder_f32.safetensors":"same_s_decoder_f32.npz",
                 "same_s_encoder_f32.safetensors":"same_s_encoder_f32.npz"}.items():
    mx.savez(str(OUT/dst), **mx.load(str(WD/src)))
w = mx.load(str(WD/"t5gemma_f16.safetensors"))
arrs = {k: np.array(v) for k, v in w.items()}
arrs["META"] = np.frombuffer(json.dumps({}).encode(), np.uint8)
arrs["TOKENIZER_MODEL"] = np.frombuffer((WD/"t5gemma_tokenizer.model").read_bytes(), np.uint8)
np.savez(str(OUT/"t5gemma_f16.npz"), **arrs)
```

**Generate a bed** (tailor the `--prompt` to the app's mood):
```bash
cd ~/Projects/AudioProto/reference/stable-audio-3/optimized/mlx
/Users/oleksandr/miniconda3/envs/fantastic/bin/python scripts/sa3_mlx.py \
  --prompt "calm cosmic ambient, warm analog pads, soft arpeggios, ethereal, spacious, no drums" \
  --dit sm-music --decoder same-s --seconds 30 --steps 8 --out /tmp/bed30.wav
```
`--dit sm-music|sm-sfx|medium`, `--decoder same-s|same-l`, `--seconds N`. Output is 44.1 kHz
stereo WAV. (License: Stability AI Community License, free < $1M revenue; + Gemma license.)

## Mux the bed into a framed preview
Fit/fade the bed to the clip length and encode AAC 256k (Apple spec):
```bash
V=<app>/marketing/aso/<platform>/video/framed_preview_<W>x<H>.mp4
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V")
ffmpeg -y -i "$V" -i /tmp/bed30.wav \
  -filter_complex "[1:a]atrim=0:${DUR},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=$(echo "$DUR-1.7"|bc):d=1.7,volume=0.8[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "${V%.mp4}_music.mp4"
```
Upload to App Store Connect with `marketing/logic/upload_previews.py` (see that folder).
