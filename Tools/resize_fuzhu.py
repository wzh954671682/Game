from PIL import Image
import os
os.chdir(os.path.dirname(__file__))
path = "../Assets/UI/effects/fuzhu_zhouwei.png"
img = Image.open(path)
print(f"Original: {img.size}")
target = 570
img = img.resize((target, target), Image.LANCZOS)
img.save(path)
print(f"Resized: {target}x{target}")
