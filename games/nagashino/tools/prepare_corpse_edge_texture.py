"""Create a color-bleed companion texture for shallow fallen-body side walls."""
from pathlib import Path
import cv2

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "games" / "nagashino" / "assets" / "images" / "fallen_casualties_sheet.png"
TARGET = ROOT / "games" / "nagashino" / "assets" / "images" / "fallen_casualties_edge.png"

image = cv2.imread(str(SOURCE), cv2.IMREAD_UNCHANGED)
if image is None or image.shape[2] < 4:
    raise RuntimeError("Expected an RGBA fallen-casualty atlas")

opaque = image[:, :, 3] >= 96
rgb = cv2.inpaint(image[:, :, :3], (~opaque).astype("uint8") * 255, 10, cv2.INPAINT_TELEA)
cv2.imwrite(str(TARGET), rgb)
