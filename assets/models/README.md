# TFLite models for AI Risk Detection

This directory holds the TFLite models used by `RiskDetectionService`.

## Status

| File | Status | Shape | Notes |
|------|--------|-------|-------|
| `risk_classifier.tflite` | **Bundled** | `[1, 35] → [1, 1]` sigmoid | Trained via `tools/build_models_minimal.py` |
| `keyword_spotter.tflite` | **Bundled** | `[1, 16000, 1] → [1, 4]` softmax | Trained via `tools/build_models_minimal.py` |
| `yamnet.tflite`         | **Bundled** | `[15600] → [1, 521]` | Pre-trained, MediaPipe build |

## How the models were built

```bash
# Install Python deps
pip install -r tools/requirements.txt

# Train risk_classifier + keyword_spotter (~1-2 min on CPU)
python tools/build_models_minimal.py

# Download yamnet.tflite (~4 MB)
python tools/download_yamnet.py
```

The Flutter app loads these files via `tflite_flutter` at startup. When
the files are missing or fail to load, the engine falls back to a
hand-tuned **heuristic** (see `RiskModel._heuristic`) that produces
the same `RiskResult` shape — A/B logging in `RiskModel` records both
paths so we can compare them.

## Replacing with production-quality models

For higher-quality weights trained on real datasets, run:

```bash
python tools/train_risk_model.py \
    --output-dir assets/models \
    --quantize int8
```

Sources used in `tools/train_risk_model.py`:

- **WISDM Human Activity Recognition**: http://www.cis.fordham.edu/wisdm/dataset.php
- **UP-FALL Detection**: https://sites.google.com/up.edu.mx/har-up/
- **TensorFlow speech_commands**: https://www.tensorflow.org/datasets/catalog/speech_commands
- **YAMNet (pre-trained)**: https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1

All models are Apache-2.0 or MIT licensed.
