"""验证测试输出"""
from PIL import Image
import numpy as np

gen = Image.open('d:/hackathon_26/test_output/case_00001.jpg')
arr = np.array(gen.convert('L'))
print("测试输出图片尺寸:", gen.size)
print("文字区域 y=770-860 暗像素统计:")
for y in range(770, 860, 5):
    row = arr[y, 50:700]
    dark = np.sum(row < 128)
    if dark > 0:
        print(f"  y={y}: dark pixels={dark}")

# Crop and save
crop = gen.crop((0, 750, 800, 1050))
crop.save('d:/hackathon_26/test_crop.jpg')
print("\n已保存 test_crop.jpg")