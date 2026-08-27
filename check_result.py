from PIL import Image
import os

# Check result subdirectories
result_dir = 'd:\\hackathon_26\\result'
for sub in sorted(os.listdir(result_dir)):
    sub_path = os.path.join(result_dir, sub)
    if os.path.isdir(sub_path):
        files = [f for f in os.listdir(sub_path) if f.endswith('.jpg') or f.endswith('.png')]
        if files:
            print(f'{sub}: {len(files)} files')
            for f in files[:3]:
                img = Image.open(os.path.join(sub_path, f))
                print(f'  {f}: {img.size}')