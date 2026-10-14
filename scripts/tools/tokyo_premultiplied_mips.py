"""已预乘RGBA的逐通道缩小；避免Pillow隐式二次预乘。"""
from PIL import Image


def halve(image):
    if image.mode != 'RGBA':
        raise ValueError('expected already-premultiplied RGBA')
    size = (max(1, image.width // 2), max(1, image.height // 2))
    return Image.merge('RGBA', tuple(band.resize(size, Image.Resampling.BOX) for band in image.split()))
