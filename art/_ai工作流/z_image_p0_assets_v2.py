# -*- coding: utf-8 -*-
"""P0.5 战斗画面资产 v2（新布局重出 + 女版主角）

按新布局重出（其余 v1 复用）：
  1. 战场棋盘 600×600——无格线（引擎画网格线），整图缩放四边齐整
  2. 解说栏底板 632×420（横版；旧 378×628 改为横版后直出，不再拉伸旧图）
  3. 信息横条 1256×56（超宽 22:1，AI 直出不可行——生成横卷轴后中段平铺）
  4. 整屏背景 1280×720——纯氛围画，无硬格线无文字框
  5. 女版主角精灵（剑修·女）256×256 透明底

用法: ""ComfyUI/.venv/Scripts/python.exe" art/_ai工作流/z_image_p0_assets_v2.py"
"""
import json
import os
import shutil
import time

import requests
from PIL import Image, ImageDraw

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

# (job, 输出类别, 宽度, 高度, seed, 英文提示词)
JOBS = [
    ("board_v2", "03_场景资产", 1024, 1024, 5001,
     "Top-down orthographic view of an ancient Chinese ink-wash battlefield ground for a strategy board game, "
     "terrain elements spread edge to edge: mountains, pine forest, river, rocks, bamboo groves and mist, "
     "muted ink brush strokes on aged rice paper texture, full-canvas seamless composition, "
     "no grid lines, no text, no UI, no border frame"),
    ("panel_dialogue_v2", "04_UI界面", 1152, 768, 5002,
     "Ancient Chinese scroll UI panel, wide horizontal empty ornate frame, ink-wash style, bamboo-slip texture, "
     "decorative carved cloud ornaments in four corners, plain blank parchment center for message text, "
     "game UI element, isolated on plain solid white background, no text"),
    ("panel_info_v2", "04_UI界面", 1216, 256, 5003,
     "Ancient Chinese long horizontal parchment banner strip, scroll-roll ends on both sides, "
     "decorative carved cloud corner ornaments, plain empty parchment center, ink-wash style, "
     "game UI element, isolated on plain solid white background, no text"),
    ("board_atmos_v2", "03_场景资产", 1344, 768, 5004,
     "Top-down aerial cinematic view of a xianxia battlefield landscape in Chinese ink-wash painting, "
     "mountains, pine forest, winding river, drifting mist, aged rice paper texture, atmospheric wide scenery, "
     "no grid lines, no text, no markers, no UI"),
    ("sprite_female", "02_角色立绘", 1024, 1024, 5005,
     "Full-body character sprite of a young female Chinese sword cultivator in white and blue hanfu robes, "
     "long black hair in a ponytail, holding a slender longsword, upright standing pose, clean simple silhouette, "
     "traditional Chinese ink-wash painting style, game battle asset, "
     "isolated on plain solid white background, no text, full body, feet visible"),
]

# 成品基础名（最终名 = 基础名 + _v的序号 + _ai.png）
FINAL = {
    "board_v2": ("战场棋盘_战斗背景", "03_场景资产", 2),
    "board_atmos_v2": ("战场棋盘_整屏背景", "03_场景资产", 2),
    "panel_dialogue_v2": ("UI_解说栏底板", "04_UI界面", 2),
    "panel_info_v2": ("UI_信息栏底板", "04_UI界面", 2),
    "sprite_female": ("玩家_女剑修_战斗精灵", "02_角色立绘", 1),
}
# 被 v2 替代的旧成品 -> 移入 art/废弃/
DEPRECATED = [
    "art/03_场景资产/战场棋盘_战斗背景_v1_ai.png",
    "art/03_场景资产/战场棋盘_整屏背景_v1_ai.png",
    "art/04_UI界面/UI_解说栏底板_v1_ai.png",
    "art/04_UI界面/UI_信息栏底板_v1_ai.png",
]


def log(msg):
    print(msg, flush=True)


def out_dir(cat):
    return os.path.join(REPO, "art", cat)


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


def generate(flat, timeout=300):
    r = requests.post(f"{API}/prompt", json={"prompt": flat, "client_id": "wzmg-p0v2"}, timeout=60)
    r.raise_for_status()
    pid = r.json()["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(8)
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


def alpha_bbox(img):
    return img.getchannel("A").getbbox()


def fit_canvas(img_rgba, size):
    img_rgba.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(img_rgba, ((size - img_rgba.width) // 2, (size - img_rgba.height) // 2), img_rgba)
    return canvas


def nine_slice(img, w, h, corner):
    src = img.convert("RGBA")
    sw, sh = src.size
    corner = max(1, min(corner, (w - 1) // 2, (h - 1) // 2))
    cw = min(corner, sw // 3, sh // 3)
    boxes = ((0, 0, cw, cw), (cw, 0, sw - cw, cw), (sw - cw, 0, sw, cw),
             (0, cw, cw, sh - cw), (cw, cw, sw - cw, sh - cw), (sw - cw, cw, sw, sh - cw),
             (0, sh - cw, cw, sh), (cw, sh - cw, sw - cw, sh), (sw - cw, sh - cw, sw, sh))
    targets = ((0, 0, corner, corner), (corner, 0, w - corner, corner), (w - corner, 0, w, corner),
               (0, corner, corner, h - corner), (corner, corner, w - corner, h - corner), (w - corner, corner, w, h - corner),
               (0, h - corner, corner, h), (corner, h - corner, w - corner, h), (w - corner, h - corner, w, h))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for box, (t0, t1, t2, t3) in zip(boxes, targets):
        piece = src.crop(box)
        tw, th = t2 - t0, t3 - t1
        if piece.size != (tw, th):
            piece = piece.resize((tw, th), Image.LANCZOS)
        out.paste(piece, (t0, t1), piece)
    return out


def tile_banner(img, target_w, target_h, end_w):
    """两端轴头保留 + 中段平铺拼接——超宽条（如 1256×56）无法 AI 直出"""
    src = img.convert("RGBA")
    w, h = src.size
    ew = min(end_w, w // 5)
    left = src.crop((0, 0, ew, h))
    right = src.crop((w - ew, 0, w, h))
    mid = src.crop((ew, 0, w - ew, h))
    mw = mid.width
    need = target_w - 2 * ew
    pieces = []
    while need > 0:
        take = min(mw, need)
        pieces.append(mid.crop((0, 0, take, h)))
        need -= take
    strip = Image.new("RGBA", (target_w - 2 * ew, h), (0, 0, 0, 0))
    x = 0
    for p in pieces:
        strip.paste(p, (x, 0))
        x += p.width
    out = Image.new("RGBA", (target_w, h), (0, 0, 0, 0))
    out.paste(left, (0, 0))
    out.paste(strip, (ew, 0))
    out.paste(right, (target_w - ew, 0))
    return out.resize((target_w, target_h), Image.LANCZOS)


def write_txt(path, prompt, post):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"提示词: {prompt}\n模型: {MODEL_NOTE}\n后处理: {post}\n")


def main():
    from rembg import new_session
    sess = new_session("u2net")

    # 0) 旧成品移入 废弃/（保留本地，不提交 git）
    for rel in DEPRECATED:
        dst_dir = os.path.join(REPO, "art", "废弃")
        os.makedirs(dst_dir, exist_ok=True)
        for suffix in ("", ".txt"):
            p = os.path.join(REPO, rel + suffix)
            if os.path.exists(p):
                shutil.move(p, os.path.join(dst_dir, os.path.basename(p)))
                log(f"废弃: {rel}{suffix}")

    # 1) 生成
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

    finals = []  # (PIL, cat, base, ver, post, job)

    # 2) 棋盘 600×600：无格线，整图等比缩放（四边齐整）
    board = Image.open(raws["board_v2"]).convert("RGB").resize((600, 600), Image.LANCZOS)
    finals.append((board, "03_场景资产", "战场棋盘_战斗背景", 2,
                   "原图 1024² 整图缩放至 600×600，不画格线（引擎绘制网格线）；四边齐整", "board_v2"))

    # 3) 解说栏 632×420：rembg + 9-slice
    img = Image.open(raws["panel_dialogue_v2"]).convert("RGB")
    cut = remove_bg(img, sess)
    cut = cut.crop(alpha_bbox(cut))
    finals.append((nine_slice(cut, 632, 420, 56), "04_UI界面", "UI_解说栏底板", 2,
                   "rembg 去底，9-slice 拉伸至 632×420（四角装饰不拉伸）", "panel_dialogue_v2"))

    # 4) 信息横条 1256×56：rembg + 两端轴头 + 中段平铺
    img = Image.open(raws["panel_info_v2"]).convert("RGB")
    cut = remove_bg(img, sess)
    cut = cut.crop(alpha_bbox(cut))
    finals.append((tile_banner(cut, 1256, 56, 72), "04_UI界面", "UI_信息栏底板", 2,
                   "rembg 去底，两端轴头保留 + 中段平铺至 1256×56（22:1 超宽条拼接）", "panel_info_v2"))

    # 5) 整屏氛围版：无格线无文字框
    atmos = Image.open(raws["board_atmos_v2"]).convert("RGB").resize((1280, 720), Image.LANCZOS)
    finals.append((atmos, "03_场景资产", "战场棋盘_整屏背景", 2,
                   "1344×768 氛围画整图缩放至 1280×720，无硬格线无文字框（仅氛围底图）", "board_atmos_v2"))

    # 6) 女版主角精灵
    img = Image.open(raws["sprite_female"]).convert("RGB")
    cut = remove_bg(img, sess)
    cut = cut.crop(alpha_bbox(cut))
    finals.append((fit_canvas(cut, 256), "02_角色立绘", "玩家_女剑修_战斗精灵", 1,
                   "rembg 去底，等比缩放至 256×256 透明画布", "sprite_female"))

    # 7) 归档
    log("\n===== 归档 =====")
    for img, cat, base, ver, post, job in finals:
        cat_dir = out_dir(cat)
        raw_dir = os.path.join(cat_dir, "ai_generated")
        os.makedirs(raw_dir, exist_ok=True)
        prompt = next(t for j, c, w, h, s, t in JOBS if j == job)
        raw_name = f"{base}_v{ver}_生成原始.png"
        shutil.copy2(raws[job], os.path.join(raw_dir, raw_name))
        write_txt(os.path.join(raw_dir, raw_name + ".txt"), prompt, "无（原始生成原图）")
        final_name = f"{base}_v{ver}_ai.png"
        img.save(os.path.join(cat_dir, final_name))
        write_txt(os.path.join(cat_dir, final_name + ".txt"), prompt, post)
        log(f"  {cat}/{final_name}  {img.size[0]}×{img.size[1]}  {img.mode}")

    wf = {job: build_prompt(job, w, h, seed, text) for job, cat, w, h, seed, text in JOBS}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "z_image_p0_assets_v2_workflow.json"),
              "w", encoding="utf-8") as f:
        json.dump(wf, f, ensure_ascii=False, indent=2)
    log("\n全部完成")


if __name__ == "__main__":
    main()
