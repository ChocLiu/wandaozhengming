# -*- coding: utf-8 -*-
"""女剑修精灵透明背景修复（裙子被 u2net 误删 + 发丝残留）。

原理：原图是纯白背景上生成的——用颜色先验精确定位背景：
  1. 近白像素 (<250) 作为候选背景，scipy.ndimage.label 找连通分量
  2. 与图像四角相连的分量 = 真背景（裙内白色织物被前景包围，不属于背景分量）
  3. final_alpha = max(u2net_soft, 255 * ~bg) —— u2net 负责发丝细节，颜色分量补齐裙摆
     （取 max 是安全的：两路都可能的残渣只有 u2net 在真背景里的噪声 + 颜色分量把影子
       当背景；本图纯白底无影子，噪声用中值滤波清理）
  4. 再与 u2net mask 求并、中值滤波，缩放到 256 覆盖成品

用法: ""ComfyUI/.venv/Scripts/python.exe" art/_ai工作流/z_fix_female_sprite_alpha.py"
"""
import os
import time

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMFY_OUT = r"D:\GameCoding\ComfyUI\ComfyUI\output"
RAW = next(os.path.join(COMFY_OUT, f) for f in os.listdir(COMFY_OUT) if f.startswith("p0_sprite_female_"))
FINAL = os.path.join(REPO, "art", "02_角色立绘", "玩家_女剑修_战斗精灵_v1_ai.png")


def remove_bg_mask(img, sess):
    from rembg import remove
    return remove(img, session=sess)


def main():
    from rembg import new_session
    sess = new_session("u2net")
    img = Image.open(RAW).convert("RGB")
    t0 = time.time()
    cut = remove_bg_mask(img, sess)          # RGBA, u2net 软 alpha
    u2_alpha = np.array(cut.getchannel("A")).astype(np.float32)
    rgb = np.array(img)

    # 1) 颜色先验背景：近白 -> 连通分量 -> 四角分量
    near_white = (rgb.min(axis=2) > 245).astype(np.uint8)
    # 排除真白但属于前景的情况由连通性保证：裙内白像素与外部背景在图像域不相连（被深色衣纹隔开）
    # 为保险起见先闭运算一次（衣纹若极淡会留缝），再找分量
    # border_value=1：腐蚀阶段否则会把图像外缘整圈当背景，四角全被误判
    near_white_closed = ndimage.binary_closing(near_white, structure=np.ones((5, 5)), border_value=1).astype(np.uint8)
    labels, n = ndimage.label(near_white_closed)
    corner_labels = {labels[0, 0], labels[0, -1], labels[-1, 0], labels[-1, -1]}
    corner_labels.discard(0)
    bg = np.isin(labels, list(corner_labels)) if corner_labels else np.zeros_like(near_white, dtype=bool)

    # 2) 两路 alpha 合成：max(u2net_soft, 255*~bg)
    # 注意：不做 median_filter——5x5 滤波在 1024 图上会把发丝细线的 soft alpha 抹掉
    #（覆盖率反而低于 u2net 原版，做过实测，已剔除该步骤）
    fg_color = ~bg
    alpha = np.maximum(u2_alpha, np.where(fg_color, 255.0, 0.0)).astype(np.uint8)

    out = np.dstack([rgb, alpha])
    out_img = Image.fromarray(out, "RGBA")
    # 4) 等比 256 画布
    out_img.thumbnail((256, 256), Image.LANCZOS)
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.paste(out_img, ((256 - out_img.width) // 2, (256 - out_img.height) // 2), out_img)
    canvas.save(FINAL)
    print(f"fixed: {FINAL} {canvas.size} {canvas.mode} {time.time() - t0:.0f}s")
    # 存档诊断图
    Image.fromarray(alpha).save(os.path.join(REPO, "art", "_ai工作流", "_debug_female_alpha_fixed.png"))
    print("debug: art/_ai工作流/_debug_female_alpha_fixed.png")


if __name__ == "__main__":
    main()
