#!/usr/bin/env python3
import argparse
import csv
import glob
import json
import os
from dataclasses import asdict, dataclass

import cv2
import numpy as np


@dataclass
class Segment:
    file: str
    start: float
    end: float
    duration: float


def fmt_time(seconds: float) -> str:
    millis = int(round(seconds * 1000))
    s, ms = divmod(millis, 1000)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def camera_ui_score(frame):
    h, w = frame.shape[:2]
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    white = (hsv[:, :, 2] > 210) & (hsv[:, :, 1] < 70)

    bottom = white[int(h * 0.91):int(h * 0.995), :].mean()
    camera_button = white[int(h * 0.74):int(h * 0.96), int(w * 0.82):int(w * 0.99)].mean()
    left_icons = white[int(h * 0.05):int(h * 0.36), :int(w * 0.12)].mean()
    center_reticle = white[int(h * 0.42):int(h * 0.60), int(w * 0.42):int(w * 0.58)].mean()

    # The camera mode UI has both the lower button bar and a large camera-button
    # cluster. Bright scenery alone often raises one of these values, but not both.
    is_ui = (
        (bottom >= 0.24 and camera_button >= 0.22)
        or (bottom >= 0.30 and left_icons >= 0.10 and center_reticle >= 0.015)
    )
    score = bottom * 3.0 + camera_button * 2.0 + left_icons + center_reticle
    return is_ui, score, {
        "bottom": float(bottom),
        "camera_button": float(camera_button),
        "left_icons": float(left_icons),
        "center_reticle": float(center_reticle),
    }


def merge_flags(flags, max_gap):
    out = flags[:]
    i = 0
    while i < len(out):
        if out[i]:
            i += 1
            continue
        start = i
        while i < len(out) and not out[i]:
            i += 1
        end = i
        if start > 0 and end < len(out) and end - start <= max_gap:
            for j in range(start, end):
                out[j] = True
    return out


def detect_ui(path, sample_fps, pad):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration = frame_count / fps if fps else 0
    step = 1.0 / sample_fps
    times = np.arange(0, duration, step)
    flags = []
    diagnostics = []

    for t in times:
        cap.set(cv2.CAP_PROP_POS_MSEC, float(t) * 1000)
        ok, frame = cap.read()
        if not ok:
            flags.append(False)
            continue
        is_ui, score, parts = camera_ui_score(frame)
        flags.append(is_ui)
        diagnostics.append({"t": float(t), "ui": bool(is_ui), "score": float(score), **parts})

    cap.release()
    flags = merge_flags(flags, max_gap=max(1, int(round(sample_fps * 0.4))))

    segments = []
    i = 0
    while i < len(flags):
        if not flags[i]:
            i += 1
            continue
        start_i = i
        while i < len(flags) and flags[i]:
            i += 1
        end_i = i - 1
        start = max(0.0, float(times[start_i]) - pad)
        end = min(duration, float(times[end_i]) + step + pad)
        segments.append(Segment(os.path.basename(path), start, end, end - start))

    return segments, diagnostics


def subtract_interval(source, cuts):
    remaining = [(source.start, source.end)]
    for cut in cuts:
        next_remaining = []
        for start, end in remaining:
            if cut.end <= start or cut.start >= end:
                next_remaining.append((start, end))
                continue
            if cut.start > start:
                next_remaining.append((start, cut.start))
            if cut.end < end:
                next_remaining.append((cut.end, end))
        remaining = next_remaining
    return [
        Segment(source.file, start, end, end - start)
        for start, end in remaining
        if end - start >= 0.75
    ]


def load_keep_segments(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [Segment(**s) for s in data["segments"]], data


def main():
    parser = argparse.ArgumentParser(description="Remove Nintendo-style camera UI overlay intervals from detected keep segments.")
    parser.add_argument("--keep-json", default="fixed_segments.json")
    parser.add_argument("--out-json", default="fixed_no_camera_ui_segments.json")
    parser.add_argument("--out-csv", default="fixed_no_camera_ui_segments.csv")
    parser.add_argument("--sample-fps", type=float, default=5.0)
    parser.add_argument("--pad", type=float, default=0.25)
    parser.add_argument("inputs", nargs="*", default=glob.glob("*.mp4"))
    args = parser.parse_args()

    ui_by_file = {}
    diagnostics = {}
    for path in sorted(args.inputs):
        if not os.path.isfile(path):
            continue
        segments, diag = detect_ui(path, args.sample_fps, args.pad)
        ui_by_file[os.path.basename(path)] = segments
        diagnostics[os.path.basename(path)] = diag
        print(f"{os.path.basename(path)}: camera UI {sum(s.duration for s in segments):.2f}s")
        for seg in segments:
            print(f"  cut {fmt_time(seg.start)} - {fmt_time(seg.end)} ({seg.duration:.2f}s)")

    keep_segments, keep_data = load_keep_segments(args.keep_json)
    final_segments = []
    for seg in keep_segments:
        final_segments.extend(subtract_interval(seg, ui_by_file.get(seg.file, [])))

    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(
            {
                "segments": [asdict(s) for s in final_segments],
                "source_keep_json": args.keep_json,
                "camera_ui_cuts": {k: [asdict(s) for s in v] for k, v in ui_by_file.items()},
                "settings": vars(args),
                "fixed_detection_settings": keep_data.get("settings"),
                "diagnostics": diagnostics,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    with open(args.out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "start", "end", "duration", "start_time", "end_time"])
        for seg in final_segments:
            writer.writerow([seg.file, f"{seg.start:.3f}", f"{seg.end:.3f}", f"{seg.duration:.3f}", fmt_time(seg.start), fmt_time(seg.end)])

    print(f"keep after UI removal: {sum(s.duration for s in final_segments):.2f}s")


if __name__ == "__main__":
    main()
