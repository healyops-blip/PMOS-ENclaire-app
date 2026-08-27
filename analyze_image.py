"""分析原始病例图片的字段布局"""
from PIL import Image
import numpy as np

img = Image.open('d:/hackathon_26/5cd45d3594647ad3647598fc647ae865.jpg')
arr = np.array(img.convert('L'))

print(f"图片尺寸: {img.size}")
print(f"数组形状: {arr.shape}")
print()

# 按行统计暗像素
row_dark = np.sum(arr < 128, axis=1)
text_rows = np.where(row_dark > 10)[0]

if len(text_rows) == 0:
    print("未检测到文字")
    exit()

# 分组连续的行
groups = []
start = text_rows[0]
prev = text_rows[0]
for r in text_rows[1:]:
    if r - prev > 8:
        groups.append((start, prev))
        start = r
    prev = r
groups.append((start, prev))

print(f"检测到 {len(groups)} 个文字区域:\n")

for i, (y1, y2) in enumerate(groups):
    region = arr[y1:y2, :]
    col_dark = np.sum(region < 128, axis=0)
    text_cols = np.where(col_dark > 2)[0]
    if len(text_cols) > 0:
        x1, x2 = text_cols[0], text_cols[-1]
        # 提取该区域的子图
        sub = arr[y1:y2, x1:x2]
        dark_ratio = np.sum(sub < 128) / sub.size
        print(f"区域 {i+1:2d}: y=[{y1:4d}, {y2:4d}] x=[{x1:4d}, {x2:4d}] "
              f"尺寸={x2-x1:4d}x{y2-y1:3d} 暗像素比例={dark_ratio:.3f}")

print("\n--- 检测到的字段 bbox (x1, y1, x2, y2) ---")
for i, (y1, y2) in enumerate(groups):
    region = arr[y1:y2, :]
    col_dark = np.sum(region < 128, axis=0)
    text_cols = np.where(col_dark > 2)[0]
    if len(text_cols) > 0:
        x1, x2 = text_cols[0], text_cols[-1]
        # 加一点边距
        margin = 5
        bbox = [max(0, x1-margin), max(0, y1-margin),
                min(arr.shape[1], x2+margin), min(arr.shape[0], y2+margin)]
        print(f'  {{"name": "field_{i+1}", "bbox": {bbox}, "template": "PLACEHOLDER"}},')