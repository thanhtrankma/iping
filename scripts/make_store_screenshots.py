"""Tạo ảnh chụp màn hình cho trang Google Play (1080x1920, 9:16) từ ảnh chụp app.

Cách chạy (cần Pillow):
    python3 scripts/make_store_screenshots.py screenshots store/screenshots

Mỗi ảnh gồm nền gradient thương hiệu, tiêu đề, dòng phụ và ảnh màn hình bo góc có bóng đổ.
Danh sách ảnh và chữ nằm trong SHOTS bên dưới; `blur` là các vùng cần làm mờ (toạ độ theo ảnh gốc).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
REGULAR = '/System/Library/Fonts/Supplemental/Arial.ttf'

SHOTS = [
    {
        'file': '5-kinh-ios26.png',
        'title': 'Luôn biết người thân\nđang ở đâu',
        'sub': 'Vị trí, pin và trạng thái của cả nhóm',
    },
    {
        'file': '2-thanh-vien.png',
        'title': 'Lịch sử & chuyến đi',
        'sub': 'Xem lại hành trình 30 ngày qua',
    },
    {
        'file': '3-lai-xe.png',
        'title': 'Lái xe an toàn hơn',
        'sub': 'Điểm lái xe, tốc độ và phanh gấp',
    },
    {
        'file': '4-menu.png',
        'title': 'Mọi tính năng đều miễn phí',
        'sub': 'Không quảng cáo, không gói trả phí',
        'blur': [(90, 116, 330, 146)],  # email tài khoản
    },
]


def gradient(size, top=(91, 124, 255), bottom=(46, 63, 209)):
    img = Image.new('RGB', size)
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / (size[1] - 1)
        d.line([(0, y), (size[0], y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded(img, radius):
    mask = Image.new('L', (img.width * 3, img.height * 3), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, mask.width - 1, mask.height - 1), radius * 3, fill=255)
    return mask.resize(img.size, Image.LANCZOS)


def centered(draw, y, text, font, fill, spacing):
    for line in text.split('\n'):
        w = draw.textlength(line, font=font)
        draw.text(((W - w) / 2, y), line, font=font, fill=fill)
        y += font.size + spacing
    return y


def wrap(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ''
    for w in words:
        test = (cur + ' ' + w).strip()
        if draw.textlength(test, font=font) <= max_w:
            cur = test
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return '\n'.join(lines)


def make(src_dir, shot):
    canvas = gradient((W, H))
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(BOLD, 78)
    sub_font = ImageFont.truetype(REGULAR, 40)

    y = centered(draw, 120, shot['title'], title_font, 'white', 14)
    y = centered(draw, y + 18, wrap(draw, shot['sub'], sub_font, W - 160), sub_font, (228, 234, 255), 10)

    phone = Image.open(os.path.join(src_dir, shot['file'])).convert('RGB')
    for box in shot.get('blur', []):
        region = phone.crop(box).filter(ImageFilter.GaussianBlur(8))
        phone.paste(region, box)

    pw = 780
    ph = round(phone.height * pw / phone.width)
    phone = phone.resize((pw, ph), Image.LANCZOS)
    top = max(y + 50, 440)  # cùng vị trí ở mọi ảnh khi tiêu đề chỉ có một dòng
    left = (W - pw) // 2
    radius = 64

    # Viền máy mỏng màu trắng mờ + bóng đổ.
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((left - 10, top + 10, left + pw + 10, top + ph + 40), radius + 10, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste((20, 28, 110), (0, 0), shadow)
    ImageDraw.Draw(canvas).rounded_rectangle(
        (left - 12, top - 12, left + pw + 12, top + ph + 12), radius + 12, fill=(235, 240, 255))
    canvas.paste(phone, (left, top), rounded(phone, radius))
    return canvas


def main(src_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for i, shot in enumerate(SHOTS, 1):
        path = os.path.join(out_dir, f'{i}-{os.path.splitext(shot["file"])[0]}.png')
        make(src_dir, shot).save(path, optimize=True)
        print(path)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
