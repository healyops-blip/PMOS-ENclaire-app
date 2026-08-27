from PIL import Image
import numpy as np

# Check one image - look at top-right area pixel colors
img = Image.open('d:\\hackathon_26\\sample_input\\影像文字报告.jpg').convert('RGB')
arr = np.array(img)
h, w = arr.shape[:2]

print(f"Image size: {w}x{h}")

# Look at top-right area (x: 700-1200, y: 20-200)
area = arr[20:200, 700:1200]
print(f"Area shape: {area.shape}")
print(f"Mean color: {np.mean(area, axis=(0,1))}")
print(f"Min color: {np.min(area, axis=(0,1))}")
print(f"Max color: {np.max(area, axis=(0,1))}")

# Check for blue pixels (B > R+30 and B > G+20)
blue_mask = (area[:,:,2] > area[:,:,0] + 30) & (area[:,:,2] > area[:,:,1] + 20)
blue_pixels = np.where(blue_mask)
if len(blue_pixels[0]) > 0:
    print(f"Blue pixels: {len(blue_pixels[0])}")
    print(f"Blue region: x=[{700+blue_pixels[1].min()},{700+blue_pixels[1].max()}], y=[{20+blue_pixels[0].min()},{20+blue_pixels[0].max()}]")
else:
    print("No blue pixels found in this region")

# Also check the full top-right quadrant
area2 = arr[0:300, 600:1260]
blue_mask2 = (area2[:,:,2] > area2[:,:,0] + 30) & (area2[:,:,2] > area2[:,:,1] + 20)
blue_pixels2 = np.where(blue_mask2)
if len(blue_pixels2[0]) > 0:
    print(f"\nFull top-right blue pixels: {len(blue_pixels2[0])}")
    print(f"Blue region: x=[{600+blue_pixels2[1].min()},{600+blue_pixels2[1].max()}], y=[{blue_pixels2[0].min()},{blue_pixels2[0].max()}]")
else:
    print("\nNo blue pixels found in full top-right")