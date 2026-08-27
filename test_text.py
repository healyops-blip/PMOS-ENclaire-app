"""测试文字渲染"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np

# 打开原始图片
img = Image.open('d:/hackathon_26/5cd45d3594647ad3647598fc647ae865.jpg').convert('RGB')
draw = ImageDraw.Draw(img)

# 加载字体
font_path = 'C:\\Windows\\Fonts\\simkai.ttf'
font = ImageFont.truetype(font_path, 24)

# 在卵巢区域画文字
text = "右卵巢:多囊样改变,大小:29*26*34mm,基础卵泡:27个"
x, y = 60, 780

# 先画白色背景
draw.rectangle([55, 770, 770, 860], fill=(255, 255, 255))

# 画黑色文字
draw.text((x, y), text, font=font, fill=(0, 0, 0))

# 保存
img.save('d:/hackathon_26/test_text_output.jpg', quality=95)

# 验证
arr = np.array(img.convert('L'))
print("测试图片尺寸:", img.size)
print("文字区域 y=780-860 暗像素统计:")
for y in range(775, 865, 5):
    row = arr[y, 50:700]
    dark = np.sum(row < 128)
    if dark > 0:
        print(f"  y={y}: dark pixels={dark}")

print("\n测试完成，已保存 test_text_output.jpg")