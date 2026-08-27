from PIL import Image
import numpy as np

# Check all images - look at top-right area pixel colors
for fname in ['影像文字报告.jpg', '化验_检测报告.jpg', '医嘱_处方.jpg', '门诊病历_就诊记录.jpg']:
    img = Image.open(f'd:\\hackathon_26\\sample_input\\{fname}').convert('RGB')
    arr = np.array(img)
    h, w = arr.shape[:2]
    
    # Look at top-right area (x: 600-1260, y: 0-300)
    area = arr[0:300, 600:min(w, 1260)]
    
    # Check for blue pixels (B > R+30 and B > G+20)
    blue_mask = (area[:,:,2] > area[:,:,0] + 30) & (area[:,:,2] > area[:,:,1] + 20)
    blue_pixels = np.where(blue_mask)
    
    if len(blue_pixels[0]) > 0:
        x1 = 600 + blue_pixels[1].min()
        x2 = 600 + blue_pixels[1].max()
        y1 = blue_pixels[0].min()
        y2 = blue_pixels[0].max()
        print(f'{fname}: Blue region x=[{x1},{x2}] y=[{y1},{y2}]')
    else:
        print(f'{fname}: No blue pixels')