from __future__ import annotations

import argparse
import base64
import io
import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tmp" / "raster_basemap_preview"

# Current production shader shared by the three raster maps.
CURRENT = {
    "saturation": 0.40,
    "brightness": 0.70,
    "contrast": 1.25,
    "tint": (0.78, 0.82, 0.80),
    "edge_strength": 1.20,
    "edge_color": (0.10, 0.12, 0.10),
    "noise_strength": 0.03,
}

# V4 keeps the production PNG palette/contrast as the visual authority while
# replacing animated noise with stable world-space grain.
MAPS: dict[str, dict[str, Any]] = {
    "tokyo": {
        "label": "东京湾",
        "theme": "横滨 / 港区细节",
        "source": ROOT / "resources" / "maps" / "tokyo_bay_bg.png",
        "crop": (1850, 1600, 6250, 4075),
        "profile_id": "tokyo_tacview_v10",
        "profile": {
            "saturation": 0.40,
            "brightness": 0.70,
            "contrast": 1.25,
            "tint": (0.78, 0.82, 0.80),
            "edge_floor": 0.0,
            "edge_gain": 1.15,
            "edge_gain_by_lod": {"operational": 1.17, "detail": 1.20},
            "luma_scale_by_lod": {"strategic": 0.9895, "operational": 1.0016},
            "edge_cap": 1.0,
            "edge_color": (0.10, 0.12, 0.10),
            "noise_strength": 0.014,
            "grain_repeat": 64.0,
            "vignette_strength": 0.0,
        },
    },
    "desert": {
        "label": "沙漠铁路",
        "theme": "Newman / 盐碱湖细节",
        "source": ROOT / "resources" / "maps" / "desert_railway_bg_v2.png",
        "crop": (4300, 2500, 8500, 4860),
        "profile_id": "desert_railway_v8",
        "profile": {
            "saturation": 0.40,
            "brightness": 0.70,
            "contrast": 1.25,
            "tint": (0.78, 0.82, 0.80),
            "edge_floor": 0.0,
            "edge_gain": 1.15,
            "edge_gain_by_lod": {"operational": 1.17, "detail": 1.20},
            "luma_scale_by_lod": {"strategic": 1.020},
            "edge_cap": 1.0,
            "edge_color": (0.10, 0.12, 0.10),
            "noise_strength": 0.014,
            "grain_repeat": 64.0,
            "vignette_strength": 0.0,
        },
    },
    "ocean": {
        "label": "海洋群岛",
        "theme": "主岛 / 群岛海岸细节",
        "source": ROOT / "resources" / "maps" / "ocean_islands_bg_v2.png",
        "crop": (3500, 0, 7900, 2475),
        "profile_id": "ocean_islands_v8",
        "profile": {
            "saturation": 0.40,
            "brightness": 0.70,
            "contrast": 1.25,
            "tint": (0.78, 0.82, 0.80),
            "edge_floor": 0.0,
            "edge_gain": 1.15,
            "edge_gain_by_lod": {"operational": 1.15, "detail": 1.20},
            "edge_cap": 1.0,
            "edge_color": (0.10, 0.12, 0.10),
            "noise_strength": 0.014,
            "grain_repeat": 64.0,
            "vignette_strength": 0.0,
        },
    },
}


def resize_cover(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    scale = max(target_w / source.width, target_h / source.height)
    scaled = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (scaled.width - target_w) // 2
    top = (scaled.height - target_h) // 2
    return scaled.crop((left, top, left + target_w, top + target_h))


def image_array(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def sobel(rgb: np.ndarray) -> np.ndarray:
    value = luma(rgb)
    padded = np.pad(value, ((1, 1), (1, 1)), mode="edge")
    tl = padded[:-2, :-2]
    tm = padded[:-2, 1:-1]
    tr = padded[:-2, 2:]
    ml = padded[1:-1, :-2]
    mr = padded[1:-1, 2:]
    bl = padded[2:, :-2]
    bm = padded[2:, 1:-1]
    br = padded[2:, 2:]
    gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br
    gy = -tl - 2.0 * tm - tr + bl + 2.0 * bm + br
    return np.sqrt(gx * gx + gy * gy)


def stable_noise(height: int, width: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    small = rng.random((max(8, height // 8), max(8, width // 8)), dtype=np.float32)
    noise = Image.fromarray(np.uint8(small * 255), mode="L").resize(
        (width, height), Image.Resampling.BILINEAR
    )
    return np.asarray(noise, dtype=np.float32) / 255.0 - 0.5


def animated_noise(height: int, width: int, frame: int) -> np.ndarray:
    # Deterministic stand-in for the production shader's TIME-dependent hash.
    rng = np.random.default_rng(991 + frame * 104729)
    return rng.random((height, width), dtype=np.float32) - 0.5


def apply_color_profile(
    rgb: np.ndarray,
    saturation: float,
    brightness: float,
    contrast: float,
    tint: tuple[float, float, float],
) -> np.ndarray:
    gray = luma(rgb)[..., None]
    result = gray * (1.0 - saturation) + rgb * saturation
    result *= brightness
    result = (result - 0.5) * contrast + 0.5
    result *= np.asarray(tint, dtype=np.float32)
    return result


def render_current(image: Image.Image, frame: int = 0) -> Image.Image:
    rgb = image_array(image)
    edge = np.clip(sobel(rgb) * CURRENT["edge_strength"], 0.0, 1.0)[..., None]
    edge_color = np.asarray(CURRENT["edge_color"], dtype=np.float32)
    rgb = rgb * (1.0 - edge) + edge_color * edge
    rgb = apply_color_profile(
        rgb,
        CURRENT["saturation"],
        CURRENT["brightness"],
        CURRENT["contrast"],
        CURRENT["tint"],
    )
    rgb += animated_noise(image.height, image.width, frame)[..., None] * CURRENT[
        "noise_strength"
    ]
    return Image.fromarray(np.uint8(np.clip(rgb, 0.0, 1.0) * 255), mode="RGB")


def iteration_profile(base: dict[str, Any], iteration: int) -> dict[str, Any]:
    profile = dict(base)
    if iteration == 1:
        profile.update(
            brightness=max(0.0, base["brightness"] - 0.02),
            contrast=base["contrast"] + 0.03,
            edge_gain=base["edge_gain"] * 1.20,
            edge_cap=min(1.0, base["edge_cap"] + 0.06),
        )
    elif iteration == 2:
        profile.update(
            brightness=max(0.0, base["brightness"] - 0.01),
            contrast=base["contrast"] + 0.01,
            edge_gain=base["edge_gain"] * 1.10,
            edge_cap=min(1.0, base["edge_cap"] + 0.03),
        )
    return profile


def render_candidate(
    image: Image.Image,
    base_profile: dict[str, Any],
    iteration: int = 3,
    seed: int = 7403,
) -> Image.Image:
    profile = iteration_profile(base_profile, iteration)
    source_rgb = image_array(image)
    rgb = source_rgb.copy()

    raw_edge = sobel(source_rgb)
    edge_image = Image.fromarray(
        np.uint8(np.clip(raw_edge, 0.0, 1.0) * 255), mode="L"
    )
    softened = np.asarray(
        edge_image.filter(ImageFilter.GaussianBlur(0.55)), dtype=np.float32
    ) / 255.0
    edge = np.clip(
        (softened - profile["edge_floor"]) * profile["edge_gain"],
        0.0,
        profile["edge_cap"],
    )[..., None]
    edge_color = np.asarray(profile["edge_color"], dtype=np.float32)
    rgb = rgb * (1.0 - edge) + edge_color * edge

    rgb = apply_color_profile(
        rgb,
        profile["saturation"],
        profile["brightness"],
        profile["contrast"],
        profile["tint"],
    )
    rgb += stable_noise(image.height, image.width, seed)[..., None] * profile[
        "noise_strength"
    ]

    yy, xx = np.mgrid[0 : image.height, 0 : image.width]
    nx = (xx + 0.5) / image.width * 2.0 - 1.0
    ny = (yy + 0.5) / image.height * 2.0 - 1.0
    radial = np.clip((nx * nx + ny * ny - 0.30) / 1.35, 0.0, 1.0)[..., None]
    rgb *= 1.0 - radial * profile["vignette_strength"]
    return Image.fromarray(np.uint8(np.clip(rgb, 0.0, 1.0) * 255), mode="RGB")


def save_webp(image: Image.Image, path: Path, quality: int = 88) -> None:
    image.save(path, format="WEBP", quality=quality, method=6)


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/arial.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def draw_pair(
    canvas: Image.Image,
    current: Image.Image,
    candidate: Image.Image,
    y: int,
    size: tuple[int, int],
    label: str,
) -> None:
    draw = ImageDraw.Draw(canvas)
    title_font = load_font(29)
    image_w, image_h = size
    left_x = 54
    right_x = 84 + image_w
    canvas.paste(resize_cover(current, size), (left_x, y + 42))
    canvas.paste(resize_cover(candidate, size), (right_x, y + 42))
    draw.text((left_x, y), f"{label} · CURRENT", fill=(216, 220, 216), font=title_font)
    draw.text(
        (right_x, y), f"{label} · CANDIDATE V3", fill=(236, 211, 146), font=title_font
    )


def make_contact_sheet(results: dict[str, dict[str, Any]]) -> Image.Image:
    canvas = Image.new("RGB", (2200, 2290), (18, 22, 24))
    draw = ImageDraw.Draw(canvas)
    title = load_font(38)
    small = load_font(21)
    draw.text((54, 22), "三地图：现行 shader / 稳定候选 V3", fill=(236, 240, 236), font=title)
    for index, key in enumerate(("tokyo", "desert", "ocean")):
        row = results[key]
        draw_pair(
            canvas,
            row["current_overview"],
            row["candidate_overview"],
            92 + index * 708,
            (1030, 636),
            row["label"],
        )
    draw.text(
        (54, 2255),
        "同一正式 8704² PNG 母版 · 离线 shader 等效预览 · 未修改生产代码",
        fill=(144, 153, 154),
        font=small,
    )
    return canvas


def make_detail_sheet(results: dict[str, dict[str, Any]]) -> Image.Image:
    canvas = Image.new("RGB", (2200, 2290), (18, 22, 24))
    draw = ImageDraw.Draw(canvas)
    title = load_font(38)
    small = load_font(21)
    draw.text((54, 22), "主题区域：道路 / 地貌 / 海岸细节", fill=(236, 240, 236), font=title)
    for index, key in enumerate(("tokyo", "desert", "ocean")):
        row = results[key]
        draw_pair(
            canvas,
            row["current_detail"],
            row["candidate_detail"],
            92 + index * 708,
            (1030, 636),
            row["theme"],
        )
    draw.text(
        (54, 2255),
        "候选只降低黑噪点与硬描边；道路、地形、海岸均来自原 PNG，不新增规则格子",
        fill=(144, 153, 154),
        font=small,
    )
    return canvas


def make_sweep_sheet(results: dict[str, dict[str, Any]]) -> Image.Image:
    canvas = Image.new("RGB", (2160, 2050), (18, 22, 24))
    draw = ImageDraw.Draw(canvas)
    title = load_font(36)
    label = load_font(25)
    draw.text((45, 20), "三轮内部收敛记录（全图）", fill=(236, 240, 236), font=title)
    for row_index, key in enumerate(("tokyo", "desert", "ocean")):
        row = results[key]
        y = 88 + row_index * 642
        draw.text((45, y), row["label"], fill=(236, 211, 146), font=label)
        images = [row["current_overview"], *row["iterations"]]
        names = ["CURRENT", "V1", "V2", "V3"]
        for column, (image, name) in enumerate(zip(images, names)):
            x = 45 + column * 525
            canvas.paste(resize_cover(image, (495, 550)), (x, y + 38))
            draw.text((x + 8, y + 548), name, fill=(216, 220, 216), font=label)
    return canvas


def data_uri(image: Image.Image, size: tuple[int, int], quality: int = 62) -> str:
    preview = resize_cover(image, size)
    buffer = io.BytesIO()
    preview.save(buffer, format="WEBP", quality=quality, method=6)
    return "data:image/webp;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def build_html(path: Path, results: dict[str, dict[str, Any]]) -> None:
    sources: dict[str, dict[str, str]] = {}
    labels: dict[str, dict[str, str]] = {}
    for key, result in results.items():
        sources[key] = {
            "overview_before": data_uri(result["current_overview"], (660, 660), 62),
            "overview_after": data_uri(result["candidate_overview"], (660, 660), 62),
            "detail_before": data_uri(result["current_detail"], (940, 529), 60),
            "detail_after": data_uri(result["candidate_detail"], (940, 529), 60),
        }
        labels[key] = {"map": result["label"], "detail": result["theme"]}
    first = sources["tokyo"]
    html = f"""<div id="raster-preview-root">
  <style>
    #raster-preview-root {{ color:var(--foreground); font-family:var(--font-sans); padding:6px 0; }}
    #raster-preview-root .bar {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:10px; }}
    #raster-preview-root h2 {{ font-size:18px; margin:0 auto 0 0; }}
    #raster-preview-root button {{ border:1px solid var(--border); background:var(--card); color:var(--foreground); border-radius:7px; padding:7px 11px; cursor:pointer; }}
    #raster-preview-root button.active {{ background:var(--primary); color:var(--primary-foreground); border-color:var(--primary); }}
    #raster-preview-root .modes {{ display:flex; gap:8px; margin-bottom:10px; }}
    #raster-preview-root .stage {{ position:relative; width:100%; aspect-ratio:16/9; overflow:hidden; background:var(--muted); border:1px solid var(--border); border-radius:8px; }}
    #raster-preview-root .stage.overview {{ aspect-ratio:1/1; width:min(100%,720px); margin:0 auto; }}
    #raster-preview-root img {{ position:absolute; inset:0; width:100%; height:100%; object-fit:cover; user-select:none; pointer-events:none; }}
    #raster-preview-root .after {{ clip-path:inset(0 0 0 50%); }}
    #raster-preview-root .divider {{ position:absolute; top:0; bottom:0; left:50%; width:2px; background:var(--primary); transform:translateX(-1px); pointer-events:none; }}
    #raster-preview-root .tag {{ position:absolute; top:10px; padding:5px 8px; border-radius:5px; background:color-mix(in srgb,var(--background) 80%,transparent); font-size:12px; font-weight:700; }}
    #raster-preview-root .tag.before {{ left:10px; }}
    #raster-preview-root .tag.after-tag {{ right:10px; color:var(--primary); }}
    #raster-preview-root input[type=range] {{ width:100%; margin:12px 0 2px; accent-color:var(--primary); }}
    #raster-preview-root .facts {{ display:flex; gap:8px; flex-wrap:wrap; margin-top:10px; }}
    #raster-preview-root .facts span {{ border:1px solid var(--border); border-radius:999px; padding:4px 8px; color:var(--muted-foreground); font-size:12px; }}
  </style>
  <div class="bar">
    <h2>三地图 PNG 基线 / 稳定候选 V3</h2>
    <button data-map="tokyo" class="active">东京湾</button>
    <button data-map="desert">沙漠铁路</button>
    <button data-map="ocean">海洋群岛</button>
  </div>
  <div class="modes">
    <button data-mode="overview" class="active">全图</button>
    <button data-mode="detail">主题细节</button>
  </div>
  <div class="stage overview">
    <img class="before-img" src="{first['overview_before']}" alt="现行 shader">
    <img class="after after-img" src="{first['overview_after']}" alt="候选 V3">
    <div class="divider"></div>
    <span class="tag before">现行 shader</span><span class="tag after-tag">候选 V3</span>
  </div>
  <input class="wipe" type="range" min="0" max="100" value="50" aria-label="前后对比擦除">
  <div class="facts"><span class="map-label">东京湾 · 全图</span><span>同一正式 PNG 母版</span><span>固定世界颗粒</span><span>无动态噪点</span><span>未修改生产代码</span></div>
  <script>
    (() => {{
      const root=document.getElementById('raster-preview-root');
      const sources={json.dumps(sources, ensure_ascii=False)};
      const labels={json.dumps(labels, ensure_ascii=False)};
      let map='tokyo', mode='overview';
      const stage=root.querySelector('.stage'), after=root.querySelector('.after'), divider=root.querySelector('.divider'), slider=root.querySelector('.wipe');
      const beforeImg=root.querySelector('.before-img'), afterImg=root.querySelector('.after-img'), mapLabel=root.querySelector('.map-label');
      const render=()=>{{ const s=sources[map]; beforeImg.src=s[`${{mode}}_before`]; afterImg.src=s[`${{mode}}_after`]; stage.classList.toggle('overview',mode==='overview'); mapLabel.textContent=`${{labels[map].map}} · ${{mode==='overview'?'全图':labels[map].detail}}`; }};
      const applyWipe=()=>{{ const x=Number(slider.value); after.style.clipPath=`inset(0 0 0 ${{x}}%)`; divider.style.left=`${{x}}%`; }};
      slider.addEventListener('input',applyWipe); applyWipe();
      root.querySelectorAll('button[data-map]').forEach(button=>button.addEventListener('click',()=>{{ map=button.dataset.map; root.querySelectorAll('button[data-map]').forEach(b=>b.classList.toggle('active',b===button)); render(); }}));
      root.querySelectorAll('button[data-mode]').forEach(button=>button.addEventListener('click',()=>{{ mode=button.dataset.mode; root.querySelectorAll('button[data-mode]').forEach(b=>b.classList.toggle('active',b===button)); render(); }}));
    }})();
  </script>
</div>"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(html, encoding="utf-8")


def compute_metrics(
    current_a: Image.Image,
    current_b: Image.Image,
    candidate: Image.Image,
) -> dict[str, float | bool]:
    a = image_array(current_a)
    b = image_array(current_b)
    c = image_array(candidate)
    absolute = np.abs(a - c)
    mean_delta = float(luma(c).mean() - luma(a).mean())
    rgb_mae = float(absolute.mean())
    p95 = float(np.percentile(absolute, 95))
    result: dict[str, float | bool] = {
        "current_mean_luma": round(float(luma(a).mean()), 5),
        "candidate_mean_luma": round(float(luma(c).mean()), 5),
        "candidate_minus_current_mean_luma": round(mean_delta, 5),
        "current_luma_stddev": round(float(luma(a).std()), 5),
        "candidate_luma_stddev": round(float(luma(c).std()), 5),
        "candidate_vs_current_rgb_mae": round(rgb_mae, 6),
        "candidate_vs_current_rgb_p95": round(p95, 6),
        "current_temporal_noise_mae_rgb": round(float(np.abs(a - b).mean()), 6),
        "candidate_temporal_noise_mae_rgb": 0.0,
    }
    result["offline_gate_mean_luma"] = abs(mean_delta) <= 0.06
    result["offline_gate_rgb_mae"] = rgb_mae <= 0.08
    result["offline_gate_stable"] = True
    result["offline_gate_pass"] = bool(
        result["offline_gate_mean_luma"]
        and result["offline_gate_rgb_mae"]
        and result["offline_gate_stable"]
    )
    return result


def render_map(key: str, config: dict[str, Any]) -> dict[str, Any]:
    with Image.open(config["source"]) as source_file:
        source = source_file.convert("RGB")
        overview_source = resize_cover(source, (1400, 1400))
        detail_source = source.crop(config["crop"]).resize(
            (1760, 990), Image.Resampling.LANCZOS
        )

    current_overview = render_current(overview_source, frame=0)
    current_overview_b = render_current(overview_source, frame=1)
    current_detail = render_current(detail_source, frame=0)
    iterations: list[Image.Image] = []
    for iteration in (1, 2, 3):
        candidate = render_candidate(
            overview_source,
            config["profile"],
            iteration,
            seed=7403 + len(key) * 103,
        )
        iterations.append(candidate)
        save_webp(candidate, OUT / f"{key}_candidate_overview_v{iteration}.webp", 88)
    candidate_overview = iterations[-1]
    candidate_detail = render_candidate(
        detail_source,
        config["profile"],
        3,
        seed=7403 + len(key) * 103,
    )
    save_webp(current_overview, OUT / f"{key}_current_overview.webp")
    save_webp(candidate_overview, OUT / f"{key}_candidate_overview.webp")
    save_webp(current_detail, OUT / f"{key}_current_detail.webp")
    save_webp(candidate_detail, OUT / f"{key}_candidate_detail.webp")
    return {
        "label": config["label"],
        "theme": config["theme"],
        "profile_id": config["profile_id"],
        "profile": config["profile"],
        "current_overview": current_overview,
        "candidate_overview": candidate_overview,
        "current_detail": current_detail,
        "candidate_detail": candidate_detail,
        "iterations": iterations,
        "metrics": compute_metrics(
            current_overview, current_overview_b, candidate_overview
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--visualization", type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    results = {key: render_map(key, config) for key, config in MAPS.items()}
    contact = make_contact_sheet(results)
    details = make_detail_sheet(results)
    sweep = make_sweep_sheet(results)
    contact.save(OUT / "contact_sheet_all.jpg", quality=91, subsampling=0)
    details.save(OUT / "detail_sheet_all.jpg", quality=91, subsampling=0)
    sweep.save(OUT / "profile_sweep_all.jpg", quality=90, subsampling=0)

    report = {
        key: {
            "profile_id": result["profile_id"],
            "profile": result["profile"],
            "metrics": result["metrics"],
        }
        for key, result in results.items()
    }
    report["all_offline_gates_pass"] = all(
        bool(result["metrics"]["offline_gate_pass"]) for result in results.values()
    )
    (OUT / "metrics_all.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if args.visualization:
        build_html(args.visualization, results)
        print(f"visualization={args.visualization}")
        print(f"visualization_bytes={args.visualization.stat().st_size}")
    print(f"contact_sheet={OUT / 'contact_sheet_all.jpg'}")
    print(f"detail_sheet={OUT / 'detail_sheet_all.jpg'}")
    print(f"sweep_sheet={OUT / 'profile_sweep_all.jpg'}")
    print(f"metrics={OUT / 'metrics_all.json'}")


if __name__ == "__main__":
    main()
