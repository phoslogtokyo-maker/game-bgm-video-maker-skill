# Game BGM Video Maker Skill

A Codex skill for building polished YouTube-ready BGM loop videos from local game, townscape, ambience, or environmental footage and a local music file.

It helps an agent:

- detect fixed-camera or low-motion footage
- remove common camera/control UI overlays from keep lists
- render 30-minute or 60-minute music-only loop videos
- add smooth scene crossfades
- add a short opening title overlay
- generate review images for visual checks
- organize final outputs, metadata, reviews, and intermediate renders

This repository contains the skill instructions and helper scripts only. It does not include game footage, music, rendered videos, or other copyrighted media.

## Installation

From this repository:

```bash
./install.sh
```

Or copy the skill folder manually:

```bash
mkdir -p "$HOME/.codex/skills"
cp -R skills/game-bgm-video-maker "$HOME/.codex/skills/"
```

After installing, start Codex and ask it to create a YouTube-ready BGM loop video from local footage and music.

## Expected Project Layout

The skill works best when your media project uses this layout:

```text
your-project/
├── sozai_movie/
│   └── source-footage.mp4
├── sozai_music/
│   └── music.m4a
├── 00_FINAL/
├── 80_work/
└── tools/
```

Codex can also search the current workspace for video and audio files when this layout is not present.

## Requirements

- macOS for the included Swift/AVFoundation render scripts
- Python 3
- OpenCV and NumPy for motion detection
- Pillow for title PNG rendering

Typical Python dependencies:

```bash
python3 -m pip install opencv-python numpy pillow
```

## Example Prompt

```text
Use the game-bgm-video-maker skill to create a 30-minute YouTube BGM video from the footage in sozai_movie/ and music in sozai_music/. Remove camera UI if present, add smooth crossfades, add an opening title, and generate review images.
```

## Notes On Rights

Only use footage, music, titles, logos, and artwork you have the right to use. This skill intentionally avoids downloading or extracting audio from third-party uploads.

## License

MIT. See [LICENSE](LICENSE).
