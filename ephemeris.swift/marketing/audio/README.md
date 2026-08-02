# Reel audio

`bed30.wav` — the scored music bed for the Ephemeris Sky app-preview reels.

Generated with the on-device MLX port of **Stable Audio 3** (`sm-music` DiT, `same-s` decoder,
30 s, 8 steps) — see `marketing/reels/README.md` for the full generation procedure.

Prompt:
> calm cosmic ambient, warm analog pads, soft arpeggios, gentle heartbeat pulse, ethereal,
> spacious, hopeful, no drums

Note: this copy was recovered from an earlier mux, so a gentle fade-in/out and `volume=0.8`
are already baked in — mux it straight onto a ~30 s reel without re-applying fades.

Kept in the repo on purpose: the bed used to live only in a scratch dir and was lost when that
was cleared, which silently left stale `_music.mp4` files behind. Never overwrite this file;
add a new one beside it if the music changes.
