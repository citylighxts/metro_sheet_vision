#!/usr/bin/env python3
"""
Convert a pre-trained OMR model → MetroSheetOMR.mlmodelc
ready to drop into the Xcode Runner target.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHY TWO EXPORT PATHS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

coremltools' PyTorch→MIL frontend fails on Python 3.14 + numpy 2.x
("only 0-dimensional arrays can be converted to Python scalars").

This script tries the direct CoreML export first, and if that fails
it falls back to:  .pt → ONNX → CoreML
The ONNX→MIL frontend avoids the broken ops.py code path.

The ONNX-sourced model has NO NMS baked in; NMS is applied in Swift
(OMRProcessor.swift handles both the NMS and pre-NMS output shapes).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AVAILABLE MODELS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  --model nota     NotA v3.0  — noteheads + accidentals  (5 classes, ~5 MB)
  --model notax    NotAX v2.0 — same 5 classes, YOLOv11x, highest accuracy (114 MB)
  --model layout   OLA v2.0   — staff layout regions     (5 classes, ~40 MB)
  --weights FILE   Any local YOLOv8/YOLO11 .pt file

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  python -m venv .venv && source .venv/bin/activate
  pip install -r scripts/requirements.txt

  python scripts/convert_omr_model.py --model nota

  → Drag  build/MetroSheetOMR.mlmodelc  into Xcode Runner group
  → "Add to target: Runner" ✓
  → flutter run --release

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import argparse
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

OUTPUT_NAME = "MetroSheetOMR"
BUILD_DIR   = Path(__file__).parent.parent / "build"
IMG_SIZE    = 640
CONF        = 0.25
IOU         = 0.45

MODELS = {
    "nota": {
        "url": (
            "https://github.com/v-dvorak/omr-layout-analysis/releases/download"
            "/nota-v3.0/nota-notehead-analysis-3.0-2025-02-27.pt"
        ),
        "filename": "nota-notehead-analysis-3.0-2025-02-27.pt",
        "labels": [
            "noteheadFull", "noteheadHalf",
            "accidentalFlat", "accidentalNatural", "accidentalSharp",
        ],
        "description": "NotA v3.0 — noteheads + accidentals (YOLO11n, ~5 MB)",
    },
    "notax": {
        "url": (
            "https://github.com/v-dvorak/omr-layout-analysis/releases/download"
            "/notax-v2.0/notax-notehead-analysis-2.0-2025-02-09.pt"
        ),
        "filename": "notax-notehead-analysis-2.0-2025-02-09.pt",
        "labels": [
            "noteheadFull", "noteheadHalf",
            "accidentalFlat", "accidentalNatural", "accidentalSharp",
        ],
        "description": "NotAX v2.0 — noteheads + accidentals (YOLO11x, 114 MB)",
    },
    "layout": {
        "url": (
            "https://github.com/v-dvorak/omr-layout-analysis/releases/download"
            "/ola-v2.0/ola-layout-analysis-2.0-2025-03-09.pt"
        ),
        "filename": "ola-layout-analysis-2.0-2025-03-09.pt",
        "labels": [
            "staff", "staff_measure", "grand_staff", "system", "system_measure",
        ],
        "description": "OLA v2.0 — staff layout regions (YOLOv8, ~40 MB)",
    },
}


def download_model(key: str, dest_dir: Path) -> tuple[Path, list[str]]:
    entry  = MODELS[key]
    dest   = dest_dir / entry["filename"]
    labels = entry["labels"]

    if dest.exists():
        size_mb = dest.stat().st_size / 1_048_576
        print(f"   already cached: {dest.name}  ({size_mb:.1f} MB)")
        return dest, labels

    print(f"⬇  {entry['description']}")
    print(f"   {entry['url']}")

    def _progress(block_count, block_size, total_size):
        downloaded = block_count * block_size
        if total_size > 0:
            pct = min(100, downloaded * 100 // total_size)
            mb  = downloaded / 1_048_576
            print(f"\r   {mb:.1f} MB  ({pct}%)", end="", flush=True)

    urllib.request.urlretrieve(entry["url"], dest, reporthook=_progress)
    print()
    print(f"   saved → {dest}")
    return dest, labels


def export_direct_coreml(pt_path: Path) -> Path:
    """
    ultralytics' built-in CoreML export (nms=True bakes NMS into the pipeline).
    Works on Python ≤3.12 with numpy 1.x.
    Fails on Python 3.14 + numpy 2.x due to coremltools PyTorch frontend bug.
    """
    from ultralytics import YOLO

    print("  Trying direct CoreML export (nms=True)...")
    model       = YOLO(str(pt_path))
    export_path = model.export(
        format="coreml",
        imgsz=IMG_SIZE,
        nms=True,
        iou=IOU,
        conf=CONF,
        half=False,
    )
    return Path(export_path)


def export_via_onnx(pt_path: Path, build_dir: Path) -> Path:
    """
    Two-stage: .pt → ONNX (ultralytics) → CoreML (coremltools ONNX frontend).

    The ONNX→MIL frontend does NOT hit the int-cast numpy 2.x bug.
    NMS is intentionally omitted — Swift applies it instead.
    Output tensor shape will be (1, 4+num_classes, 8400).
    """
    from ultralytics import YOLO
    import coremltools as ct

    print("  Stage 1/2 — exporting to ONNX (no NMS; will be applied in Swift) …")
    yolo      = YOLO(str(pt_path))
    onnx_path = Path(yolo.export(
        format="onnx",
        imgsz=IMG_SIZE,
        simplify=True,
        nms=False,
        half=False,
    ))
    print(f"  ONNX → {onnx_path}")

    print("  Stage 2/2 — converting ONNX → CoreML via coremltools ONNX frontend …")
    ct_model = ct.converters.convert(
        str(onnx_path),
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,
    )

    out_path = build_dir / f"{OUTPUT_NAME}_onnx.mlpackage"
    ct_model.save(str(out_path))
    print(f"  CoreML (ONNX path) → {out_path}")
    return out_path


def export_to_coreml(pt_path: Path, build_dir: Path) -> Path:
    print(f"\n[1/3] Exporting  {pt_path.name}  →  CoreML …")
    try:
        path = export_direct_coreml(pt_path)
        print(f"  Direct CoreML export succeeded → {path}")
        return path
    except Exception as exc:
        print(f"  Direct export failed ({type(exc).__name__}: {exc})")
        print("  Falling back to ONNX → CoreML path …")
        return export_via_onnx(pt_path, build_dir)


def annotate_for_vision(mlpackage_path: Path, labels: list[str]) -> Path:
    print(f"\n[2/3] Annotating for Apple Vision Framework …")

    annotated_path = mlpackage_path.parent / f"{OUTPUT_NAME}_annotated.mlpackage"
    if annotated_path.exists():
        shutil.rmtree(annotated_path)

    shutil.copytree(mlpackage_path, annotated_path)

    spec_candidates = list(annotated_path.rglob("model.mlmodel")) + \
                      list(annotated_path.rglob("Model.mlmodel"))
    if not spec_candidates:
        print("  (no spec file found — skipping metadata annotation)")
        return annotated_path

    spec_file = spec_candidates[0]

    import coremltools as ct
    from coremltools.proto import Model_pb2

    spec = Model_pb2.Model()
    spec.ParseFromString(spec_file.read_bytes())

    spec.description.metadata.shortDescription = (
        "Optical Music Recognition — detects noteheads and accidentals."
    )
    spec.description.metadata.author        = "metro_sheet_vision / v-dvorak/omr-layout-analysis"
    spec.description.metadata.versionString = "1.0"
    spec.description.metadata.userDefined["classes"] = json.dumps(labels)

    spec_file.write_bytes(spec.SerializeToString())
    print(f"  annotated → {annotated_path}")
    return annotated_path


def compile_mlmodelc(source: Path, build_dir: Path) -> Path:
    print(f"\n[3/3] Compiling  {source.name}  →  {OUTPUT_NAME}.mlmodelc …")

    build_dir.mkdir(parents=True, exist_ok=True)

    try:
        run(["xcrun", "coremlc", "compile", str(source), str(build_dir)])
    except FileNotFoundError:
        sys.exit("❌  xcrun not found — install Xcode from the App Store.")
    except subprocess.CalledProcessError:
        sys.exit("❌  coremlc compile failed — check the error above.")

    candidates = list(build_dir.glob("*.mlmodelc"))
    if not candidates:
        sys.exit("❌  xcrun coremlc produced no .mlmodelc output.")

    compiled = candidates[0]
    final    = build_dir / f"{OUTPUT_NAME}.mlmodelc"
    if compiled != final:
        if final.exists():
            shutil.rmtree(final)
        compiled.rename(final)

    print(f"  compiled  → {final}")
    return final


def run(cmd: list[str]) -> None:
    print(f"  $ {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def write_labels(labels: list[str], build_dir: Path) -> None:
    out = build_dir / "omr_labels.json"
    out.write_text(json.dumps(labels, indent=2))
    print(f"  labels    → {out}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert an OMR model to MetroSheetOMR.mlmodelc"
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--model",
        choices=list(MODELS.keys()),
        metavar="nota|notax|layout",
        help="Download and convert a pre-trained model",
    )
    source.add_argument(
        "--weights",
        metavar="PATH",
        help="Path to a local YOLOv8/YOLO11 .pt file",
    )
    parser.add_argument(
        "--labels",
        metavar="PATH",
        help="JSON array of class strings (required with --weights)",
    )
    args = parser.parse_args()

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    if args.model:
        pt_path, labels = download_model(args.model, BUILD_DIR)
    else:
        pt_path = Path(args.weights).expanduser().resolve()
        if not pt_path.exists():
            sys.exit(f"❌  File not found: {pt_path}")
        if not args.labels:
            sys.exit("❌  --labels is required when using --weights")
        labels = json.loads(Path(args.labels).expanduser().read_text())

    mlpackage_path = export_to_coreml(pt_path, BUILD_DIR)
    annotated_path = annotate_for_vision(mlpackage_path, labels)
    compile_mlmodelc(annotated_path, BUILD_DIR)
    write_labels(labels, BUILD_DIR)

    print(f"""
╔══════════════════════════════════════════════════════════════════╗
║  ✓ Done!                                                         ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  1. Xcode → Runner group → right-click                           ║
║     "Add Files to Runner…"                                       ║
║     Select  build/MetroSheetOMR.mlmodelc                         ║
║     ✓ "Add to target: Runner"                                    ║
║                                                                  ║
║  2.  flutter run --release                                       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
""")


if __name__ == "__main__":
    main()
