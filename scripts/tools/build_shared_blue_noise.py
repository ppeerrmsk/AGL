#!/usr/bin/env python3
"""Build the deterministic, map-agnostic 64x64 grain texture used by basemaps."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "resources" / "maps" / "shared_blue_noise_64.png"
SIZE = 64
SEED = 7403


def build_blue_noise() -> np.ndarray:
    rng = np.random.default_rng(SEED)
    white = rng.random((SIZE, SIZE), dtype=np.float64) - 0.5
    spectrum = np.fft.fft2(white)
    fy = np.fft.fftfreq(SIZE)[:, None]
    fx = np.fft.fftfreq(SIZE)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)
    # Remove DC and bias energy away from low spatial frequencies. Ranking the
    # filtered field restores a uniform histogram without reintroducing map data.
    shaped = np.fft.ifft2(spectrum * np.sqrt(radius)).real
    order = np.argsort(shaped, axis=None, kind="stable")
    ranks = np.empty(SIZE * SIZE, dtype=np.float64)
    ranks[order] = (np.arange(SIZE * SIZE, dtype=np.float64) + 0.5) / (SIZE * SIZE)
    return np.uint8(np.rint(ranks.reshape((SIZE, SIZE)) * 255.0))


def spectral_low_frequency_ratio(values: np.ndarray) -> float:
    centered = values.astype(np.float64) - float(values.mean())
    power = np.abs(np.fft.fftshift(np.fft.fft2(centered))) ** 2
    yy, xx = np.mgrid[:SIZE, :SIZE]
    radius = np.sqrt((xx - SIZE / 2) ** 2 + (yy - SIZE / 2) ** 2)
    low = float(power[(radius > 0.0) & (radius <= 6.0)].sum())
    total = float(power[radius > 0.0].sum())
    return low / total if total > 0.0 else 1.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    values = build_blue_noise()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(values).save(args.output, optimize=True)
    payload = args.output.read_bytes()
    print(f"output={args.output}")
    print(f"bytes={len(payload)}")
    print(f"sha256={hashlib.sha256(payload).hexdigest()}")
    print(f"mean={float(values.mean()):.6f}")
    print(f"low_frequency_power_ratio={spectral_low_frequency_ratio(values):.6f}")


if __name__ == "__main__":
    main()
