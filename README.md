# OsmoReframe for Final Cut Pro

An experimental Final Cut Pro effect for reframing stitched DJI Osmo 360 footage.

> **Product decision:** a production reframe plugin is not necessary for the current workflow.
> DJI Panorama Exporter removes the one-file-at-a-time Studio export step, and Final Cut already
> provides the required 360 orientation, keyframing and color controls. The code here remains a
> research prototype. See [docs/DECISION.md](docs/DECISION.md).

## What works in this first milestone

- Equirectangular 360 input exported from DJI Studio.
- Experimental side-by-side Osmo dual-fisheye input, stitched and blended inside the effect.
- GPU reframing in Final Cut Pro with keyframeable Pan, Tilt, Roll and Field of View.
- Rectilinear, fisheye and tiny-planet projections.
- Fast exposure, contrast, saturation, temperature, tint, highlight and shadow controls.
- FxPlug 4 out-of-process service wrapped in a Motion Effect template.
- Verified in Final Cut Pro 12.3 with a real equirectangular clip generated from the supplied OSV.

Final Cut already has good native 360 controls. This effect exists as a focused test bed for
the missing DJI workflow, custom projections and a future direct-OSV ingestion path.

## Current limitation

DJI `.OSV` files are not stitched panoramas. Each sample contains two synchronized 3840 x
3840 HEVC Main 10 streams plus proprietary DJI calibration/telemetry tracks. FxPlug receives
frames that Final Cut has already imported; it cannot act as a media importer. Direct `.OSV`
support therefore requires a separate Apple Media Extension plus a validated DJI-compatible
stitching and stabilization implementation.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/SAMPLE_ANALYSIS.md](docs/SAMPLE_ANALYSIS.md).

## Requirements

- macOS 13 or newer
- Apple silicon
- Final Cut Pro 12.3 (the current test host)
- Xcode 26 and the FxPlug SDK
- `xcodegen`

## Build

```sh
./scripts/bootstrap.sh
./scripts/build.sh
```

## Install locally

```sh
./scripts/install-local.sh
```

## Experimental direct-OSV proof

The samples contain two synchronized 3840x3840 HEVC lens tracks. These scripts
pack them as dual fisheye and make a generic equirectangular result without DJI
Studio:

```bash
./scripts/prototype-stitch-frame.sh "Sample Footage Osmo 360/input.OSV"
./scripts/prototype-stitch-clip.sh "Sample Footage Osmo 360/input.OSV"
./scripts/prototype-pack-lenses.sh "Sample Footage Osmo 360/input.OSV"
```

The proof uses a provisional 190-degree fisheye model. This proves that both lenses can be decoded and geometrically projected, but it
is not yet a production replacement for DJI Studio: DJI's private camera
calibration, seam blending and stabilization still have to be decoded or
reimplemented.

`prototype-pack-lenses.sh` is the more flexible intermediate path: it keeps both
fisheye projections intact. In Final Cut, choose **Input Format → Osmo Dual
Fisheye** and tune **Lens FOV** and **Seam Blend** without regenerating the file.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the MIT stitching
reference used by the Metal implementation.

The installer places `OsmoReframe.app` in `~/Applications` and the Motion Effect in
`~/Movies/Motion Templates.localized/Effects.localized/360/OsmoReframe`.

Restart Final Cut Pro and find **OsmoReframe** in the **360** effects category.

## Input workflow

1. In DJI Studio export the full stitched equirectangular panorama, not a pre-framed flat video.
2. Import that panorama into Final Cut Pro.
3. In the clip inspector, set the projection to equirectangular if Final Cut did not detect it.
4. Put it in a normal rectilinear project and apply OsmoReframe.
5. Animate Pan, Tilt, Roll and Field of View in the inspector.

For D-Log M, apply DJI's official Osmo 360 D-Log M to Rec.709 LUT using Final Cut's Camera LUT
or Custom LUT effect. This plugin intentionally does not invent an undocumented D-Log M curve.
