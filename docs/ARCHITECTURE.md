# Architecture and feasibility

## Product boundary

The project has two deliberately separate layers:

```text
Phase 1 (implemented)
DJI Studio equirectangular export -> Final Cut -> OsmoReframe FxPlug

Phase 2 (research)
Original .OSV -> Apple Media Extension + DJI-compatible stitch -> Final Cut
```

Keeping these layers separate prevents a container/parser problem from destabilizing a useful
reframe effect and makes image parity measurable.

## Runtime milestone reached

The Phase 1 effect has been built, locally installed and exercised in Final Cut Pro 12.3. Final
Cut discovered the Motion wrapper, loaded the out-of-process FxPlug service, rendered the Metal
projection, exposed all inspector controls, and responded to Pan, Field of View and Tiny Planet
changes on an equirectangular clip generated from the supplied OSV sample.

Separately, the Phase 2 proof decoded both original lens tracks and generated a moving 2048 x 1024
ProRes panorama without DJI Studio. It is geometrically usable for reframe testing, but it has not
passed the calibration, seam-quality or stabilization gates below.

An additional middle path now preserves the two fisheye frames side by side and lets the FxPlug
project and cross-fade both lenses at render time. This keeps Lens FOV and seam width editable in
Final Cut and avoids baking a generic stitch into the intermediate. Replacing that temporary packed
track with a Media Extension output is the shortest path toward true OSV-native ingest.

## Phase 1: OsmoReframe FxPlug

FxPlug is the correct API for image processing after Final Cut has decoded the source. The current
host mirrors the proven structure used by SpektraFilm:

- A tiny macOS host app makes an out-of-process PlugInKit service discoverable.
- The FxPlug service receives linear RGBA16F/RGBA32F IOSurfaces.
- A Metal compute shader maps a virtual camera ray into equirectangular longitude/latitude.
- A Motion Effect wrapper publishes the parameters in Final Cut's Effects browser.

Keyframeable view controls are Pan, Tilt, Roll, Field of View and projection. Color controls run
in Final Cut's linear working space. D-Log M conversion is intentionally left to DJI's official LUT
because DJI does not publish a transfer equation suitable for an independent implementation.

## Phase 2: direct OSV support

FxPlug and Motion templates cannot register a media container or decode camera originals. On
current macOS, the Apple-supported entry point is a macOS app containing a Media Extension.

A direct implementation would likely need:

1. `MEFormatReader` support for the `.OSV` ISO-BMFF structure, timestamps, two HEVC tracks, audio
   and DJI metadata.
2. A controlled way to present both synchronized lens samples to the image pipeline. A normal
   HEVC decoder only sees one elementary stream, so this may require a custom sample description
   and `MEVideoDecoder`, or stitching inside the reader/decoder layer.
3. Per-camera calibration parsing, fisheye projection, chromatic/vignette correction and seam
   selection/blending.
4. Gyro/orientation decoding and stabilization parity.
5. Regression fixtures across firmware, frame rates, D-Log M, low light, motion and near-seam
   subjects.

Media Extensions require Apple entitlements and provisioning. Before committing to a production
reader, the format and reverse-engineering/licensing position must be clarified with DJI and Apple.

## Decision gates for Phase 2

Direct import should move beyond research only after all gates pass:

- The two HEVC lens streams can be decoded with stable frame/PTS pairing.
- Calibration payloads can be identified across at least two firmware versions.
- A frame can be stitched within a small, documented error against DJI Studio.
- Motion stabilization can be matched on a moving shot.
- The Media Extension can expose a single renderable video track to Final Cut without an
  intermediate file.
- Performance is acceptable at proxy and full resolution.

If the calibration or stabilization gates fail, the supported product remains the Phase 1 plugin.
That path still removes DJI Studio from every creative reframing decision; Studio becomes a single
technical ingest/export step.

## Why not merely remux OSV?

Remuxing is lossless, but it does not combine the two lenses. Final Cut effects receive the frames
of one decoded image source, not two arbitrary video tracks plus DJI calibration. A two-track MOV
therefore does not give FxPlug the information it needs at render time.

## Performance choices inherited from SpektraFilm

- Out-of-process FxPlug service rather than a legacy in-process plugin.
- Full-buffer request only because every output pixel may sample anywhere on the panorama.
- Metal compute rather than CPU projection.
- Direct shared-buffer access to Final Cut's IOSurface memory; no per-frame image file conversion.
- Separate signed host app and Motion template installation.

The first runtime milestone should measure 4K and 8K playback before adding tracking, optical flow
or denoising.

## Primary documentation

- [Apple FxPlug](https://developer.apple.com/documentation/professional-video-applications/fxplug)
- [Apple MediaExtension](https://developer.apple.com/documentation/mediaextension)
- [Apple 360 video settings](https://support.apple.com/guide/final-cut-pro/ver79532309c/mac)
- [Apple: add 360 clips to standard projects](https://support.apple.com/guide/final-cut-pro/verf6c81c24e/mac)
- [DJI Osmo 360 specifications](https://www.dji.com/360/specs)
- [DJI Osmo 360 downloads](https://www.dji.com/360/downloads)
