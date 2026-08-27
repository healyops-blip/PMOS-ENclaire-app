from PIL import Image
import numpy as np

# Check one result image - look at top-left and top-right areas
img = Image.open('d:\\hackathon_26\\result\\影像文字报告\\case_00001.jpg').convert('RGB')
arr = np.array(img)
h, w = arr.shape[:2]
print(f'Image size: {w}x{h}')

# Top-left area (where current logo is placed)
tl = arr[0:150, 0:250]
tl_gray = np.mean(tl, axis=2)
tl_dark = np.where(tl_gray < 100)
if len(tl_dark[0]) > 0:
    print(f'Top-left dark pixels: {len(tl_dark[0])}')
    print(f'Top-left region: x=[{tl_dark[1].min()},{tl_dark[1].max()}], y=[{tl_dark[0].min()},{tl_dark[0].max()}]')

# Top-right area (where logo should be)
tr = arr[0:150, 800:1260]
tr_gray = np.mean(tr, axis=2)
tr_dark = np.where(tr_gray < 100)
if len(tr_dark[0]) > 0:
    print(f'Top-right dark pixels: {len(tr_dark[0])}')
    print(f'Top-right region: x=[{800+tr_dark[1].min()},{800+tr_dark[1].max()}], y=[{tr_dark[0].min()},{tr_dark[0].max()}]')
else:
    print('No dark pixels in top-right')