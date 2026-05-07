---
name: game-bgm-video-maker
description: Build polished YouTube-ready BGM loop videos from game, townscape, ambience, or environmental footage and a local music file. Use when Codex is asked to make作業用BGM videos, loop gameplay/ambience footage to 30 or 60 minutes, remove camera/UI overlays, add smooth scene crossfades, add an opening title, generate review contact sheets, or organize final video outputs.
---

# Game BGM Video Maker

## Workflow

Use this skill to turn local video captures and a local music file into a finished long-form BGM video. Prefer local processing; do not download or extract audio from YouTube or other third-party uploads. Assume the user is responsible for rights to supplied media, but call out obvious copyright risk when relevant.

When running bundled scripts, first check whether the project already has matching scripts in `tools/` or `scripts/`. If not, copy this skill's bundled scripts into a project-local `tools/` directory and run them from there. Keep source media and rendered outputs in the user's project, not inside the skill folder.

1. **Find inputs**
   - Prefer `sozai_movie/` for video and `sozai_music/` for audio when present.
   - Otherwise search the current workspace for video files (`mp4`, `mov`, `m4v`, `mkv`, `webm`) and audio files (`m4a`, `mp3`, `wav`, `aac`, `flac`).
   - Use `cv2`/AVFoundation metadata to confirm duration, resolution, frame rate, and audio/video track counts.

2. **Detect usable footage**
   - Run `tools/detect_fixed_segments.py` or `scripts/detect_fixed_segments.py` to find low-motion/fixed-camera segments.
   - Inspect the generated CSV/JSON and review frames before trusting the cut list.
   - Tune thresholds only when the result is too strict or too loose.

3. **Remove UI overlays**
   - Run `tools/remove_camera_ui_segments.py` or `scripts/remove_camera_ui_segments.py` when camera UI, control bars, or white overlay chrome appears in the capture.
   - The detector is optimized for white camera/button overlays; treat it as a draft and verify with review images.

4. **Render the main loop**
   - Default output length is 30 minutes. Use 60 minutes only if the user asks or the source has enough variety.
   - Use `tools/make_youtube_from_segments_crossfade.swift` or `scripts/make_youtube_from_segments_crossfade.swift` with `--transition 1.5` to loop selected segments and add soft scene transitions.
   - Use music-only output by default. Do not keep source video audio unless the user explicitly wants ambience/SFX.

5. **Add an opening title**
   - Generate a transparent PNG title card with `tools/render_title_png.py` or `scripts/render_title_png.py`.
   - Burn it into the first 8 seconds with `tools/add_title_overlay.swift` or `scripts/add_title_overlay.swift --overlay-image`.
   - Use title text supplied by the user. If missing, choose concise title/subtitle from the project and music names, then mention the assumption.

6. **Verify and organize**
   - Generate contact-sheet review images around the opening title and transition points.
   - Verify final duration, resolution, and track counts.
   - Organize with `tools/organize_bgm_video_project.py` or `scripts/organize_bgm_video_project.py`: final files in `00_FINAL/`, intermediates in `80_work/`, scripts in `tools/` or the skill `scripts/`, and source media in `sozai_*`.

## Default Commands

Run commands from the project workspace. Set `CLANG_MODULE_CACHE_PATH` to a workspace-local directory for Swift/AVFoundation:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.clang-module-cache" swift tools/make_youtube_from_segments_crossfade.swift \
  --segments final_timeline_segments.json \
  --music sozai_music/music_01.m4a \
  --output youtube_30min_bgm_smooth.mp4 \
  --minutes 30 \
  --transition 1.5
```

Title workflow:

```bash
python3 tools/render_title_png.py \
  --output title_overlay.png \
  --title "Project Title" \
  --subtitle "Music or Scene Subtitle"

CLANG_MODULE_CACHE_PATH="$PWD/.clang-module-cache" swift tools/add_title_overlay.swift \
  --input youtube_30min_bgm_smooth.mp4 \
  --output youtube_30min_bgm_final_with_title.mp4 \
  --overlay-image title_overlay.png \
  --duration 8
```

## Review Standards

- Always create a short test render first when adding crossfades or titles.
- Confirm the title is visible in generated frames at roughly 1s, 2s, 4s, and absent after the title duration.
- Confirm crossfades by sampling frames around known transition starts every 0.25s.
- Confirm final media has exactly one video track and one audio track unless the user requested otherwise.
- Preserve source files and earlier renders unless the user explicitly asks to delete them.

## Bundled Scripts

- `detect_fixed_segments.py`: detects fixed-camera intervals with OpenCV optical flow.
- `remove_camera_ui_segments.py`: subtracts camera/control UI intervals from a keep-list JSON.
- `make_youtube_from_segments_crossfade.swift`: builds a long video with looped music and crossfaded scene transitions.
- `render_title_png.py`: creates a transparent PNG title overlay.
- `add_title_overlay.swift`: burns a PNG overlay into the opening seconds of an MP4.
- `organize_bgm_video_project.py`: moves final, review, metadata, and intermediate files into a clean folder layout.
