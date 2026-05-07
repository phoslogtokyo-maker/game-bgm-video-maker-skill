#!/usr/bin/env python3
import argparse
import csv
import glob
import json
import os
from dataclasses import dataclass, asdict

import cv2
import numpy as np


@dataclass
class Sample:
    t: float
    motion_px: float
    stationary_ratio: float
    stable: bool


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


def read_gray(cap, t, width):
    cap.set(cv2.CAP_PROP_POS_MSEC, max(0, t) * 1000)
    ok, frame = cap.read()
    if not ok:
        return None
    h, w = frame.shape[:2]
    scale = width / float(w)
    resized = cv2.resize(frame, (width, int(h * scale)), interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)


def motion_score(prev, cur):
    points = cv2.goodFeaturesToTrack(prev, maxCorners=350, qualityLevel=0.01, minDistance=8, blockSize=7)
    if points is None or len(points) < 20:
        diff = cv2.absdiff(prev, cur)
        return float(np.mean(diff) / 255.0 * 8.0), 0.0

    nxt, status, _ = cv2.calcOpticalFlowPyrLK(
        prev,
        cur,
        points,
        None,
        winSize=(21, 21),
        maxLevel=3,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 20, 0.03),
    )
    status = status.reshape(-1).astype(bool)
    if nxt is None or status.sum() < 20:
        diff = cv2.absdiff(prev, cur)
        return float(np.mean(diff) / 255.0 * 8.0), 0.0

    movement = nxt[status].reshape(-1, 2) - points[status].reshape(-1, 2)
    mags = np.linalg.norm(movement, axis=1)
    return float(np.median(mags)), float(np.mean(mags <= 0.8))


def merge_short_gaps(flags, max_gap_samples):
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
        left_ok = start > 0 and out[start - 1]
        right_ok = end < len(out) and out[end]
        if left_ok and right_ok and end - start <= max_gap_samples:
            for j in range(start, end):
                out[j] = True
    return out


def find_segments(path, sample_fps, resize_width, max_motion_px, min_stationary_ratio, min_duration, pad):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration = frame_count / fps if fps else 0
    if duration <= 0:
        return [], []

    step = 1.0 / sample_fps
    times = np.arange(0, duration, step)
    prev = read_gray(cap, 0, resize_width)
    samples = []

    for t in times[1:]:
        cur = read_gray(cap, float(t), resize_width)
        if prev is None or cur is None:
            break
        motion, stationary = motion_score(prev, cur)
        stable = motion <= max_motion_px and stationary >= min_stationary_ratio
        samples.append(Sample(float(t), motion, stationary, stable))
        prev = cur

    cap.release()

    flags = [s.stable for s in samples]
    flags = merge_short_gaps(flags, max(1, int(round(sample_fps * 0.5))))

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
        start = max(0.0, samples[start_i].t - step - pad)
        end = min(duration, samples[end_i].t + pad)
        if end - start >= min_duration:
            segments.append(Segment(os.path.basename(path), start, end, end - start))

    return segments, samples


def main():
    parser = argparse.ArgumentParser(description="Detect intervals where the camera/screen appears fixed.")
    parser.add_argument("inputs", nargs="*", default=glob.glob("*.mp4"))
    parser.add_argument("--sample-fps", type=float, default=5.0)
    parser.add_argument("--resize-width", type=int, default=480)
    parser.add_argument("--max-motion-px", type=float, default=0.9)
    parser.add_argument("--min-stationary-ratio", type=float, default=0.55)
    parser.add_argument("--min-duration", type=float, default=1.0)
    parser.add_argument("--pad", type=float, default=0.15)
    parser.add_argument("--json", default="fixed_segments.json")
    parser.add_argument("--csv", default="fixed_segments.csv")
    args = parser.parse_args()

    all_segments = []
    diagnostics = {}
    for path in sorted(args.inputs):
        if not os.path.isfile(path):
            continue
        segments, samples = find_segments(
            path,
            args.sample_fps,
            args.resize_width,
            args.max_motion_px,
            args.min_stationary_ratio,
            args.min_duration,
            args.pad,
        )
        all_segments.extend(segments)
        diagnostics[os.path.basename(path)] = [asdict(s) for s in samples]
        kept = sum(s.duration for s in segments)
        print(f"{os.path.basename(path)}: {len(segments)} segments, keep {kept:.2f}s")
        for seg in segments:
            print(f"  {fmt_time(seg.start)} - {fmt_time(seg.end)} ({seg.duration:.2f}s)")

    with open(args.json, "w", encoding="utf-8") as f:
        json.dump(
            {
                "segments": [asdict(s) for s in all_segments],
                "settings": vars(args),
                "diagnostics": diagnostics,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    with open(args.csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "start", "end", "duration", "start_time", "end_time"])
        for seg in all_segments:
            writer.writerow([seg.file, f"{seg.start:.3f}", f"{seg.end:.3f}", f"{seg.duration:.3f}", fmt_time(seg.start), fmt_time(seg.end)])


if __name__ == "__main__":
    main()
