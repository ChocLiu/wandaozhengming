# -*- coding: utf-8 -*-
"""男女主角精灵 v3：统一「半侧身面向右」

主角男/女两张精灵姿态统一：三人侧身（three-quarter）面向画面右侧。
白袍 u2net 误切问题（见 z_fix_female_sprite_alpha.py）内联进后处理：
  alpha = max(u2net 软alpha, 255 × ~背景)
  背景 = 近白像素连通分量中与四角相连者（裙/袍内白织物被衣纹隔开，不会误删）；
  u2net 负责发丝 soft alpha，颜色分量负责补白袍实心。无 median_filter
  （5×5 在 1024 图上会抹掉发丝半透明，已实测剔除）。
成品 = 主角 战斗精灵 v2（旧 v1 成品移 art/废弃/；生成原始图归档 ai_generated/）。

用法: ""ComfyUI/.venv/Scripts/python.exe" art/_ai工作流/z_image_p0_sprites_v3.py"
"""
import json
import os
import shutil
import time

import numpy as np
import requests
from PIL import Image
from scipy import ndimage

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMFY_OUT = r"D:\GameCoding\ComfyUI\ComfyUI\output"
API = "http://127.0.0.1:8188"
SAVE_ID = "9"
MODEL_NOTE = ("Z-Image Turbo NVFP4（z_image_turbo_nvfp4 + qwen_3_4b_fp4_mixed + ae, "
              "8 步 cfg1 res_multistep simple, ModelSamplingAuraFlow shift=3）")

MODEL = dict(
    unet="z_image_turbo_nvfp4.safetensors",
    clip="qwen_3_4b_fp4_mixed.safetensors",
    vae="ae.safetensors",
)

# 姿态定式：男女统一「半侧身面向右」（中文提示词，方向表述更明确）
ORIENT = "半侧身面向画面右侧（身体和脸朝右，约45度侧转，胸口与双肩可见，不是正侧面）"
JOBS = [
    # (job, 类别, 宽, 高, seed, 提示词)
    ("sprite_male", "02_角色立绘", 1024, 1024, 5141,
     "中国水墨修仙风游戏立绘，年轻男性剑修全身立绘，白衣蓝边交领汉服，右手持长剑，"
     + ORIENT + "，站姿挺拔，剪影干净简洁，游戏战斗单位资产，"
     "纯白背景无边框独立画面，无文字，全身可见，脚部可见"),
    ("sprite_female", "02_角色立绘", 1024, 1024, 5142,
     "中国水墨修仙风游戏立绘，年轻女性剑修全身立绘，白衣蓝边交领汉服，黑色长发扎马尾，"
     "手持细长剑，"
     + ORIENT + "，站姿端正，剪影干净简洁，游戏战斗单位资产，"
     "纯白背景无边框独立画面，无文字，全身可见，脚部可见"),
]

# 成品基础名 / 版本
FINAL = {
    "sprite_male": ("玩家_剑修_战斗精灵", "02_角色立绘", 2),
    "sprite_female": ("玩家_女剑修_战斗精灵", "02_角色立绘", 2),
}
# 被替换的旧成品 -> art/废弃/（归档红线：成品换代不丢旧档）
DEPRECATED = [
    "art/02_角色立绘/玩家_剑修_战斗精灵_v1_ai.png",
    "art/02_角色立绘/玩家_女剑修_战斗精灵_v1_ai.png",
]


def log(msg):
    print(msg, flush=True)


def build_prompt(name, w, h, seed, text):
    return {
        "30": {"class_type": "CLIPLoader", "inputs": {"clip_name": MODEL["clip"], "type": "lumina2", "device": "default"}},
        "29": {"class_type": "VAELoader", "inputs": {"vae_name": MODEL["vae"]}},
        "28": {"class_type": "UNETLoader", "inputs": {"unet_name": MODEL["unet"], "weight_dtype": "default"}},
        "27": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["30", 0], "text": text}},
        "33": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["27", 0]}},
        "11": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["28", 0], "shift": 3}},
        "13": {"class_type": "EmptySD3LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "3": {"class_type": "KSampler", "inputs": {
            "model": ["11", 0], "positive": ["27", 0], "negative": ["33", 0],
            "latent_image": ["13", 0], "seed": seed, "steps": 8, "cfg": 1.0,
            "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1.0}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["29", 0]}},
        SAVE_ID: {"class_type": "SaveImage",
                  "inputs": {"images": ["8", 0], "filename_prefix": f"p0_{name}"}},
    }


def generate(flat, timeout=420):
    r = requests.post(f"{API}/prompt", json={"prompt": flat, "client_id": "wzmg-p0v3"}, timeout=60)
    r.raise_for_status()
    pid = r.json()["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(6)
        e = requests.get(f"{API}/history/{pid}", timeout=60).json().get(pid)
        if e:
            st = e.get("status", {})
            if st.get("completed"):
                return e["outputs"][SAVE_ID]["images"][0]
            if st.get("status_str") == "error":
                raise RuntimeError(f"生成失败: {json.dumps(st, ensure_ascii=False)[:500]}")
    raise TimeoutError(f"{timeout}s 超时")


def remove_bg(img, sess):
    from rembg import remove
    return remove(img, session=sess)


def color_fg(rgb, thr=245):
    """近白像素 -> 闭运算 -> 连通分量 -> 与四角相连者 = 背景；返回前景 mask 与背景占比"""
    near = (rgb.min(axis=2) > thr).astype(np.uint8)
    closed = ndimage.binary_closing(near, structure=np.ones((5, 5)), border_value=1).astype(np.uint8)
    labels, _ = ndimage.label(closed)
    corners = {labels[0, 0], labels[0, -1], labels[-1, 0], labels[-1, -1]}
    corners.discard(0)
    bg = np.isin(labels, list(corners)) if corners else np.zeros_like(near, dtype=bool)
    return ~bg, bg.mean()


def alpha_fix(img_rgb, u2_alpha):
    """合成 alpha：u2net 软 alpha 保发丝细节；颜色连通域补白袍/白裙实心"""
    fg, bg_ratio = color_fg(np.array(img_rgb))
    if bg_ratio < 0.25:
        log(f"  ⚠️ 背景占比仅 {bg_ratio:.2f}（底色非纯白？）——颜色法可能失效，请人工检查")
    return np.maximum(u2_alpha, np.where(fg, 255.0, 0.0)).astype(np.uint8), bg_ratio


def fit_canvas(img_rgba, size):
    img_rgba.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(img_rgba, ((size - img_rgba.width) // 2, (size - img_rgba.height) // 2), img_rgba)
    return canvas


def write_txt(path, prompt, post):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"提示词: {prompt}\n模型: {MODEL_NOTE}\n后处理: {post}\n")


def alpha_stats(img):
    a = np.array(img.getchannel("A"))
    bbox = a > 10
    return (a > 10).mean(), bbox.mean()


def make_checker(w, h, s=16):
    base = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(0, h, s):
        for x in range(0, w, s):
            v = 255 if ((x // s) + (y // s)) % 2 == 0 else 205
            base[y:y + s, x:x + s] = v
    return Image.fromarray(base, "RGB")


def main():
    from rembg import new_session
    sess = new_session("u2net")

    # 1) 生成（输出目录已有同前缀则跳过，便于续跑）
    raws = {}
    for job, cat, w, h, seed, text in JOBS:
        existing = sorted(f for f in os.listdir(COMFY_OUT) if f.startswith(f"p0_{job}_"))
        if existing:
            raws[job] = os.path.join(COMFY_OUT, existing[0])
            log(f"[{job}] 使用已有 {existing[0]}")
            continue
        t0 = time.time()
        info = generate(build_prompt(job, w, h, seed, text))
        raws[job] = os.path.join(COMFY_OUT, info["filename"])
        log(f"[{job}] {info['filename']} {time.time() - t0:.0f}s")

    # 2) 后处理 + 归档
    log("\n===== 后处理 =====")
    previews = []
    for job, cat, w, h, seed, text in JOBS:
        base, _, ver = FINAL[job]
        img = Image.open(raws[job]).convert("RGB")
        log(f"[{job}] rembg(u2net)...")
        cut = remove_bg(img, sess)
        u2_alpha = np.array(cut.getchannel("A")).astype(np.float32)
        alpha, bg_ratio = alpha_fix(img, u2_alpha)
        rgba = Image.fromarray(np.dstack([np.array(img), alpha]), "RGBA")
        # 裁到实体内容（alpha>0 bbox + 3px 余量），再等比进 256 透明画布
        bbox = (np.array(rgba.getchannel("A")) > 10)
        ys, xs = np.where(bbox)
        pad = 3
        box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0),
               min(xs.max() + pad + 1, rgba.width), min(ys.max() + pad + 1, rgba.height))
        cut = rgba.crop(box)
        final = fit_canvas(cut, 256)

        cov, fill = alpha_stats(final)
        log(f"[{job}] 成品 256×256 RGBA  alpha>10 覆盖={cov:.3f}  实体区填充={fill:.3f}  背景占比={bg_ratio:.3f}")

        cat_dir = os.path.join(REPO, "art", cat)
        raw_dir = os.path.join(cat_dir, "ai_generated")
        os.makedirs(raw_dir, exist_ok=True)
        raw_name = f"{base}_v{ver}_生成原始.png"
        shutil.copy2(raws[job], os.path.join(raw_dir, raw_name))
        write_txt(os.path.join(raw_dir, raw_name + ".txt"), text, "无（原始生成原图，纯白底）")
        final_name = f"{base}_v{ver}_ai.png"
        final.save(os.path.join(cat_dir, final_name))
        post = ("rembg(u2net) 去底 + 颜色连通域白袍修复（alpha=max(u2net软alpha, 255×非背景)，无中值滤波），"
                "裁实体区 + 3px 余量后等比缩放至 256×256 透明画布居中（主体约占 80%）")
        write_txt(os.path.join(cat_dir, final_name + ".txt"), text, post)
        log(f"  {cat}/{final_name}  {final.size}  {final.mode}")
        previews.append((final_name, final))

    # 3) 棋盘格预览（透明底验收）
    gap, tile = 24, 16
    cw = gap + 256 + gap + 256 + gap
    ch = gap + 256 + gap
    chk = make_checker(cw, ch, tile)
    for i, (name, im) in enumerate(previews):
        chk.paste(im, (gap + i * (256 + gap), gap), im)
    pv = os.path.join(REPO, "art", "_ai工作流", "sprites_v3_checker.png")
    chk.save(pv)
    log(f"棋盘格预览: art/_ai工作流/sprites_v3_checker.png")

    # 4) 旧成品移入 废弃/（最后执行——新成品落盘无误才换代）
    log("\n===== 换代 =====")
    dst_dir = os.path.join(REPO, "art", "废弃")
    os.makedirs(dst_dir, exist_ok=True)
    for rel in DEPRECATED:
        for suffix in ("", ".txt"):
            p = os.path.join(REPO, rel + suffix)
            if os.path.exists(p):
                shutil.move(p, os.path.join(dst_dir, os.path.basename(p)))
                log(f"废弃: {os.path.basename(p)}")
    log("\n全部完成")


if __name__ == "__main__":
    main()
