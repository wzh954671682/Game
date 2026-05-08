import os
from PIL import Image

# 目标目录
target_dir = r'F:\GAME-demo\game-demo-w\Assets\Monsters\monster_01'
output_dir = os.path.join(target_dir, 'resized')
target_width = 128

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

print(f"正在开始处理目录: {target_dir}")

for filename in os.listdir(target_dir):
    if filename.lower().endswith('.png'):
        img_path = os.path.join(target_dir, filename)
        with Image.open(img_path) as img:
            # 计算等比例缩放的高度
            w_percent = (target_width / float(img.size[0]))
            target_height = int((float(img.size[1]) * float(w_percent)))
            
            # 缩放并保存
            resized_img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
            resized_img.save(os.path.join(output_dir, filename))
            print(f"已处理: {filename} -> 128x{target_height}")

print(f"\n全部完成！处理后的文件保存在: {output_dir}")
