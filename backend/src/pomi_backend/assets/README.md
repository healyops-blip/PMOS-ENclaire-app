# POMI watermark assets

`PomiWatermarkV2.png` is the transparent, tightly cropped raster template used
by the backend watermark renderer. It was generated from the repository's
canonical `assets/brand/POMI-logo.svg` with the open-source resvg renderer.

Runtime processing only needs Pillow. The deployment server does not need
Node.js, resvg, Cairo, ImageMagick, or a separate image service.
