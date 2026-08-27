from PIL import Image
import os

input_dir = 'd:\\hackathon_26\\sample_input'
for f in sorted(os.listdir(input_dir)):
    if f.endswith('.jpg'):
        img = Image.open(os.path.join(input_dir, f))
        print(f"{f}: {img.size}")