from PIL import Image
import os

input_dir = 'd:\\hackathon_26\\sample_input'
output_dir = 'd:\\hackathon_26\\logo_check'
os.makedirs(output_dir, exist_ok=True)

for f in sorted(os.listdir(input_dir)):
    if f.endswith('.jpg'):
        img = Image.open(os.path.join(input_dir, f))
        w, h = img.size
        # Crop top-right area (right 40%, top 25%)
        crop = img.crop((int(w*0.5), 0, w, int(h*0.25)))
        crop.save(os.path.join(output_dir, f.replace('.jpg', '_topright.png')))
        print(f"{f}: size={img.size}, crop saved")

print("Done!")