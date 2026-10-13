"""Tạo bộ ảnh thương hiệu IPing từ ảnh icon gốc.

Cách chạy (cần Pillow):
    python3 scripts/make_branding.py <ảnh-gốc> assets/branding

Đầu ra:
    icon_master_1024.png     icon vuông tràn viền, không trong suốt (iOS, App Store, launcher)
    logo_rounded_1024.png    logo bo góc có góc trong suốt, giữ viền kính (splash, trong app)
    logo_rounded_512.png     bản nhỏ dùng trong app
    adaptive_background.png  lớp nền adaptive icon Android (108dp, nội dung nằm trong vùng an toàn)
    adaptive_foreground.png  lớp trước adaptive icon (trong suốt)
    splash_logo.png          logo cho splash (Android < 12, iOS)
    splash_android12.png     logo cho splash Android 12+ (nằm gọn trong vòng tròn 2/3)
    play_store_512.png       icon Google Play
    feature_graphic_1024x500.png  ảnh banner Google Play
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Vị trí khối icon bo góc trong ảnh gốc 1254x1254 (đo bằng cách quét pixel trắng).
SRC_BOX = (124, 118, 1129, 1123)
SRC_RADIUS = 273
# Bỏ viền kính dày ~28px để icon tràn viền.
RIM = 28


def rounded_mask(size, radius, scale=4):
    """Mặt nạ bo góc khử răng cưa (vẽ to rồi thu nhỏ)."""
    w, h = size
    big = Image.new('L', (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def fill_corners(img, radius):
    """Tô bốn góc ngoài vùng bo bằng bản làm mờ của chính ảnh để không lộ nền trắng."""
    blurred = img.resize((64, 64), Image.LANCZOS).resize(img.size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(24))
    out = blurred.copy()
    out.paste(img, (0, 0), rounded_mask(img.size, radius))
    return out


def main(src_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    src = Image.open(src_path).convert('RGB')
    x0, y0, x1, y1 = SRC_BOX

    # 1. Logo bo góc, góc trong suốt, giữ viền kính.
    block = src.crop(SRC_BOX)
    logo = block.convert('RGBA')
    logo.putalpha(rounded_mask(block.size, SRC_RADIUS))
    logo_1024 = logo.resize((1024, 1024), Image.LANCZOS)
    logo_1024.save(os.path.join(out_dir, 'logo_rounded_1024.png'))
    logo_1024.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, 'logo_rounded_512.png'))

    # 2. Icon tràn viền, không trong suốt.
    inner = src.crop((x0 + RIM, y0 + RIM, x1 - RIM, y1 - RIM))
    inner = fill_corners(inner, SRC_RADIUS - RIM)
    master = inner.resize((1024, 1024), Image.LANCZOS)
    master.save(os.path.join(out_dir, 'icon_master_1024.png'))
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, 'play_store_512.png'))

    # 3. Adaptive icon Android: launcher chỉ hiện ~72/108 ở giữa, nên thu nội dung
    #    còn ~64% (vừa vùng hiển thị) và lấp phần ngoài bằng bản làm mờ.
    bg = master.resize((64, 64), Image.LANCZOS).resize((1024, 1024), Image.LANCZOS).filter(ImageFilter.GaussianBlur(30))
    content = int(1024 * 0.64)
    off = (1024 - content) // 2
    bg.paste(master.resize((content, content), Image.LANCZOS), (off, off),
             rounded_mask((content, content), int(content * 0.18)).filter(ImageFilter.GaussianBlur(6)))
    bg.save(os.path.join(out_dir, 'adaptive_background.png'))
    Image.new('RGBA', (1024, 1024), (0, 0, 0, 0)).save(os.path.join(out_dir, 'adaptive_foreground.png'))

    # 4. Splash.
    splash = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    splash.paste(logo_1024.resize((900, 900), Image.LANCZOS), (62, 62))
    splash.save(os.path.join(out_dir, 'splash_logo.png'))
    # Android 12+: biểu tượng bị cắt theo hình tròn đường kính 2/3 khung, logo phải nằm gọn trong đó.
    a12 = Image.new('RGBA', (1152, 1152), (0, 0, 0, 0))
    a12.paste(logo_1024.resize((640, 640), Image.LANCZOS), (256, 256))
    a12.save(os.path.join(out_dir, 'splash_android12.png'))

    # 5. Ảnh banner Google Play 1024x500.
    fg = Image.new('RGB', (1024, 500))
    draw = ImageDraw.Draw(fg)
    for y in range(500):
        t = y / 499
        draw.line([(0, y), (1024, y)], fill=(int(91 + (46 - 91) * t), int(124 + (63 - 124) * t), int(255 + (209 - 255) * t)))
    fg.paste(logo_1024.resize((340, 340), Image.LANCZOS), (70, 80), logo_1024.resize((340, 340), Image.LANCZOS))
    bold = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 104)
    regular = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 33)
    draw.text((450, 150), 'IPing', font=bold, fill='white')
    draw.text((454, 280), 'Luôn biết người thân đang ở đâu', font=regular, fill=(235, 240, 255))
    fg.save(os.path.join(out_dir, 'feature_graphic_1024x500.png'))
    print('Đã tạo ảnh trong', out_dir)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
