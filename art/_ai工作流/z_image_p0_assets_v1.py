# -*- coding: utf-8 -*-
"""P0.5 战斗画面资产批量生成（Z-Image Turbo NVFP4 + ComfyUI API）

对应《多媒体资产清单》1.1 四组资产：
  1. 战场棋盘背景（600×600 棋盘区 + 1280×720 整屏；10×10 格，单格 60px；分层 底色/格纹）
  2. 战斗单位精灵 ×2（剑修玩家 + 焚天诀散修；PNG 透明底 256×256）
  3. UI 底框套件（解说栏 378×628 / 信息栏 850×170 / 按钮 96×36；四角装饰保留，9-slice 可拉伸）
  4. 操作图标 ×6（普攻/招式/切换/防御/丹药/结束；PNG 透明底 64×64）

流程：ComfyUI API 生成（每张约 10-20 秒）→ rembg(u2net) 去底 → PIL 排版/网格/精确尺寸。
归档（art/README.md）：原始 AI 输出 -> 各类别 ai_generated/（随图 .txt 记提示词）；
成品含 AI 成分 -> 类别根目录，文件名 `_ai` 后缀 + 同名 .txt。

用法: ""ComfyUI/.venv/Scripts/python.exe" art/_ai工作流/z_image_p0_assets_v1.py"
"""
import json
import os
import time

import requests
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # 游戏仓库根
COMFY_OUT = r"D:\GameCoding\ComfyUI\ComfyUI\output"  # ComfyUI 输出目录（绝对路径）
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
    ("board", "03_场景资产", 1344, 768, 4001,
     "Top-down aerial view of a 10x10 grid battlefield board for a Chinese ink-wash xianxia turn-based game, "
     "each cell a terrain tile: mountains, pine forest, river, rocks, bamboo and mist, faint subtle grid lines, "
     "muted ink brush strokes, aged rice paper texture, no text, no characters, orthographic top-down game asset"),
    ("sprite_player", "02_角色立绘", 1024, 1024, 4002,
     "Full-body character sprite of a young Chinese sword cultivator in white and blue hanfu robes, "
     "holding a longsword in one hand, upright standing pose, clean simple silhouette, traditional Chinese "
     "ink-wash painting style, game battle asset, isolated on plain solid white background, no text, full body, feet visible"),
    ("sprite_enemy", "02_角色立绘", 1024, 1024, 4003,
     "Full-body character sprite of a wild demonic cultivator in dark red robes with flame motifs, "
     "fierce grin, holding a broad dao blade wreathed in embers, standing pose, ink-wash xianxia style, "
     "game battle asset, isolated on plain solid white background, no text, full body, feet visible"),
    ("panel_dialogue", "04_UI界面", 1024, 1024, 4004,
     "Ancient Chinese scroll and bamboo-slip UI panel, empty ornate vertical frame, ink-wash style, "
     "decorative carved cloud ornaments in four corners, plain blank paper center for text, "
     "game UI element, isolated on plain solid white background, no text"),
    ("panel_info", "04_UI界面", 1152, 256, 4005,
     "Ancient Chinese scroll banner, long horizontal empty ornate frame, ink-wash style, scroll-roll ends, "
     "plain empty parchment center, decorative carved corners xianxia game UI element, "
     "isolated on plain solid white background, no text"),
    ("panel_button", "04_UI界面", 512, 192, 4006,
     "Ancient Chinese ornament button, small horizontal rectangular jade tablet with cloud-carved corners, "
     "parchment texture, empty center, ink-wash style, game UI element, "
     "isolated on plain solid white background, no text"),
    ("icon_attack", "04_UI界面", 1024, 1024, 4011,
     "Minimalist Chinese ink line icon of a sword slashing downward, simple bold brush strokes, "
     "game UI icon, centered, isolated on plain solid white background, no text, no shading"),
    ("icon_skill", "04_UI界面", 1024, 1024, 4012,
     "Minimalist Chinese ink line icon of a blooming lotus flower, simple bold brush strokes, "
     "game UI icon, centered, isolated on plain solid white background, no text, no shading"),
    ("icon_switch", "04_UI界面", 1024, 1024, 4013,
     "Minimalist Chinese ink line icon of two curved arrows forming a circular exchange, "
     "simple bold brush strokes, game UI icon, centered, isolated on plain solid white background, no text, no shading"),
    ("icon_guard", "04_UI界面", 1024, 1024, 4014,
     "Minimalist Chinese ink line icon of a round shield with a sword behind it, "
     "simple bold brush strokes, game UI icon, centered, isolated on plain solid white background, no text, no shading"),
    ("icon_pill", "04_UI界面", 1024, 1024, 4015,
     "Minimalist Chinese ink line icon of a small round medicine pill bottle, "
     "simple bold brush strokes, game UI icon, centered, isolated on plain solid white background, no text, no shading"),
    ("icon_end", "04_UI界面", 1024, 1024, 4016,
     "Minimalist Chinese ink line icon of a square stop symbol inside a circle, "
     "simple bold brush strokes, game UI icon, centered, isolated on plain solid white background, no text, no shading"),
]

# 成品基础名（最终文件名 = 基础名 + _v1_ai.png）
PANEL_BASE = {"panel_dialogue": "UI_解说栏底板", "panel_info": "UI_信息栏底板", "panel_button": "UI_按钮底板"}
ICON_CN = {"icon_attack": "普攻", "icon_skill": "招式", "icon_switch": "切换",
           "icon_guard": "防御", "icon_pill": "丹药", "icon_end": "结束"}
SPRITE_BASE = {"sprite_player": "玩家_剑修_战斗精灵", "sprite_enemy": "散修_焚天诀_战斗精灵"}


def out_dir(cat):
    return os.path.join(REPO, "art", cat)


def log(msg):
    print(msg, flush=True)


def prompt_of(job):
    return next(t for j, c, w, h, s, t in JOBS if j == job)


def build_prompt(name, w, h, seed, text):
    """扁平 API prompt（与官方 image_z_image_turbo 模板子图结构一致，已验证）"""
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
    r = requests.post(f"{API}/prompt", json={"prompt": flat, "client_id": "wzmg-p0"}, timeout=60)
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


def write_txt(path, prompt, post):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"提示词: {prompt}\n模型: {MODEL_NOTE}\n后处理: {post}\n")


def remove_bg(img, sess):
    from rembg import remove
    return remove(img, session=sess)


def fit_canvas(img_rgba, size):
    """等比缩放至 size×size 透明画布居中"""
    img_rgba.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(img_rgba, ((size - img_rgba.width) // 2, (size - img_rgba.height) // 2), img_rgba)
    return canvas


def alpha_bbox(img):
    return img.getchannel("A").getbbox()


def nine_slice(img, w, h, corner):
    """9-slice 拉伸到 w×h：四角等比缩放不拉伸，边与中心拉伸"""
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


def draw_grid(d, ox, oy, size, cell, fill=(38, 28, 16, 108), width=2):
    for i in range(size // cell + 1):
        d.line([(ox + i * cell, oy), (ox + i * cell, oy + size)], fill=fill, width=width)
        d.line([(ox, oy + i * cell), (ox + size, oy + i * cell)], fill=fill, width=width)


def main():
    from rembg import new_session
    sess = new_session("u2net")

    # ---------- 1) 生成（ComfyUI/output 已有同前缀产物则跳过，便于中途续跑） ----------
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

    finals = []  # (PIL图, 类别, 基础名, 后处理备注, 对应 job)

    # ---------- 2) 棋盘（底色层 / 600×600 合成 / 1280×720 整屏） ----------
    CELL = 60
    board_raw = Image.open(raws["board"]).convert("RGB")
    boardc = board_raw.crop((board_raw.width // 2 - 300, board_raw.height // 2 - 300,
                             board_raw.width // 2 + 300, board_raw.height // 2 + 300))
    g = Image.new("RGBA", (600, 600), (0, 0, 0, 0))
    draw_grid(ImageDraw.Draw(g), 0, 0, 600, CELL)
    board = Image.alpha_composite(boardc.convert("RGBA"), g).convert("RGB")
    full = board_raw.resize((1280, 720), Image.LANCZOS)
    bx, by = (1280 - 600) // 2, (720 - 600) // 2
    g2 = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    draw_grid(ImageDraw.Draw(g2), bx, by, 600, CELL)
    full_over = Image.alpha_composite(full.convert("RGBA"), g2).convert("RGB")
    finals.append((boardc, "03_场景资产", "战场棋盘_底色", "分层-底色（中心裁 600×600，无格纹）", "board"))
    finals.append((board, "03_场景资产", "战场棋盘_战斗背景", "叠加精确 10×10 格线（单格 60px）+色层装饰", "board"))
    finals.append((full_over, "03_场景资产", "战场棋盘_整屏背景", "1344×768→1280×720，棋盘区叠 10×10 格线", "board"))

    # ---------- 3) 精灵 ×2 + UI 底板 ×3：rembg + 排版 ----------
    # 大面板走 9-slice（四角装饰不拉伸）；按钮底板源 512×192 与 96×36 等比，直接缩不放样
    panel_spec = {"panel_dialogue": (378, 628, 84), "panel_info": (850, 170, 46), "panel_button": (96, 36, 22)}
    for job, src in raws.items():
        if not (job.startswith("sprite_") or job.startswith("panel_")):
            continue
        img = Image.open(src).convert("RGB")
        log(f"[{job}] rembg...")
        cut = remove_bg(img, sess)
        cut = cut.crop(alpha_bbox(cut))
        if job.startswith("sprite_"):
            finals.append((fit_canvas(cut, 256), "02_角色立绘", SPRITE_BASE[job],
                           "rembg 去底，等比缩放至 256×256 透明画布", job))
        elif job == "panel_button":
            finals.append((fit_canvas(cut, 96), "04_UI界面", PANEL_BASE[job],
                           "rembg 去底，等比缩放至 96×36 透明画布（源 8:3 与成品一致，无拉伸）", job))
        else:
            w, h, corner = panel_spec[job]
            finals.append((nine_slice(cut, w, h, corner), "04_UI界面", PANEL_BASE[job],
                           f"rembg 去底，9-slice 拉伸至 {w}×{h} 精确尺寸（四角装饰未变形）", job))

    # ---------- 4) 图标 ×6：rembg + 64×64 ----------
    for job, src in raws.items():
        if not job.startswith("icon_"):
            continue
        img = Image.open(src).convert("RGB")
        log(f"[{job}] rembg...")
        cut = remove_bg(img, sess)
        cut = cut.crop(alpha_bbox(cut))
        finals.append((fit_canvas(cut, 64), "04_UI界面", f"操作图标_{ICON_CN[job]}",
                       "rembg 去底，等比缩放至 64×64 透明画布", job))

    # ---------- 5) 归档 ----------
    log("\n===== 归档 =====")
    # 原始 AI 输出（ComfyUI 生成原图）-> 各类别 ai_generated/
    done_raw = set()
    for img, cat, base, post, job in finals:
        cat_dir = out_dir(cat)
        raw_dir = os.path.join(cat_dir, "ai_generated")
        os.makedirs(raw_dir, exist_ok=True)
        prompt = prompt_of(job)
        if job not in done_raw:
            raw_name = base + "_生成原始.png"
            import shutil
            shutil.copy2(raws[job], os.path.join(raw_dir, raw_name))
            write_txt(os.path.join(raw_dir, raw_name + ".txt"), prompt, "无（原始生成原图）")
            done_raw.add(job)
            log(f"  raw: {cat}/ai_generated/{raw_name}")
        # 成品（_ai 后缀）
        final_name = base + "_v1_ai.png"
        img.save(os.path.join(cat_dir, final_name))
        write_txt(os.path.join(cat_dir, final_name + ".txt"), prompt, post)
        log(f"  {cat}/{final_name}  {img.size[0]}×{img.size[1]}  {img.mode}")

    # 工作流 JSON 留档
    wf = {job: build_prompt(job, w, h, seed, text) for job, cat, w, h, seed, text in JOBS}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "z_image_p0_assets_v1_workflow.json"),
              "w", encoding="utf-8") as f:
        json.dump(wf, f, ensure_ascii=False, indent=2)

    log("\n全部完成")


if __name__ == "__main__":
    main()
