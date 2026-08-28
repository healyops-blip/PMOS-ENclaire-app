# OCR quality dataset

This directory contains 40 generated, synthetic single-page PNG materials: ten
for each supported material type. `dataset.json` records the SHA-256, field-level
ground truth, P0/P1/P2 priority, accepted normalizations, critical-field flag,
and an error note for every scored field. No sample represents a real person.

Regenerate the byte-identical logical dataset (PNG bytes can vary when Pillow is
upgraded), then review and commit the resulting hash manifest:

```powershell
$env:PYTHONPATH = (Resolve-Path backend/src).Path
python backend/scripts/generate_ocr_quality_dataset.py
```

`offline-perfect-predictions.json` is an automated scoring test double. It proves
the scorer and gates, not Qwen3-VL accuracy or latency. A real release evaluation
must use `--run-qwen`, keep the API key only in `POMI_OCR_API_KEY`, and archive the
generated report outside source control after privacy review.

```powershell
python backend/scripts/run_ocr_quality_evaluation.py `
  --dataset backend/evaluation/ocr_quality/dataset.json `
  --run-qwen `
  --output runtime/ocr-quality-qwen.json `
  --records-output runtime/ocr-quality-qwen-records.json `
  --enforce
```

Fallback records are discarded before every accuracy, success, and latency
denominator. `--enforce` also requires all 40 samples, so a small successful
subset cannot pass the gate.
