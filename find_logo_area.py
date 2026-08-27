"""分析样本图片右上角区域，找到logo/医院名称的精确位置"""
from PIL import Image
import numpy as np
import os

input_dir = 'd:\\hackathon_26\\sample_input'

for f in sorted(os.listdir(input_dir)):
    if not f.endswith('.jpg'):
        continue
    img = Image.open(os.path.join(input_dir, f)).convert('RGB')
    arr = np.array(img)
    h, w = arr.shape[:2]
    
    print(f"\n=== {f} ({w}x{h}) ===")
    
    # 分析右上角区域 (右半部分，上15%)
    top_right = arr[0:int(h*0.15), int(w*0.35):w]
    
    # 转换为灰度
    gray = np.mean(top_right, axis=2)
    
    # 找暗区域 (文字/Logo) - 使用固定阈值
    dark_mask = gray < 100
    
    # 找连通区域
    from scipy import ndimage
    labeled, num_features = ndimage.label(dark_mask)
    
    print(f"  检测到 {num_features} 个暗色区域:")
    
    # 找最大的几个区域
    sizes = ndimage.sum(dark_mask, labeled, range(1, num_features + 1))
    large_regions = np.where(sizes > 50)[0] + 1
    
    regions = []
    for region_id in large_regions:
        region_pixels = np.where(labeled == region_id)
        min_y, max_y = region_pixels[0].min(), region_pixels[0].max()
        min_x, max_x = region_pixels[1].min(), region_pixels[1].max()
        global_min_x = int(w*0.35) + min_x
        global_max_x = int(w*0.35) + max_x
        global_min_y = min_y
        global_max_y = max_y
        size = sizes[region_id - 1]
        regions.append((size, global_min_x, global_max_x, global_min_y, global_max_y))
    
    # 按大小排序
    regions.sort(reverse=True, key=lambda x: x[0])
    
    for i, (size, x1, x2, y1, y2) in enumerate(regions[:5]):
        print(f"  区域{i+1}: size={size}, x=[{x1},{x2}], y=[{y1},{y2}]")
    
    # 保存右上角区域供查看
    crop = img.crop((int(w*0.35), 0, w, int(h*0.15)))
    crop.save(f'd:\\hackathon_26\\logo_check\\{f.replace(".jpg", "_tr.png")}')
    
print("\n完成！裁剪图保存在 logo_check 目录")