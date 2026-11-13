# DJI Osmo 360 sample analysis

Analysis date: 2026-08-12. The originals were inspected read-only.

## Summary

Both `.OSV` files are ISO Base Media / QuickTime containers with a DJI extension. They are not
stitched equirectangular videos. Each stores one square HEVC stream per lens, synchronized audio,
and proprietary DJI metadata/calibration tracks.

| Property | `CAM_20251017152734_0015_D.OSV` | `CAM_20251103211157_0001_D.OSV` |
|---|---:|---:|
| Size | 3,516,443,681 bytes | 1,045,270,407 bytes |
| Duration | 173.080 s | 50.960 s |
| Frames per lens | 4,327 | 1,274 |
| Frame rate | 25 fps | 25 fps |
| Total bitrate | 162.535 Mb/s | 164.093 Mb/s |
| Firmware | 10.00.14.28 | 10.00.21.20 |

## Streams in each file

1. HEVC `hvc1`, 3840 x 3840, Main 10, 10-bit 4:2:0, 25 fps (lens A).
2. HEVC `hvc1`, 3840 x 3840, Main 10, 10-bit 4:2:0, 25 fps (lens B).
3. AAC-LC stereo audio, 48 kHz, approximately 317 kb/s.
4. Two DJI `djmd` camera-metadata tracks.
5. Two DJI `dbgi` tracks, one per sensor.
6. A 688 x 344 MJPEG cover image. This cover is already a low-resolution stitched 2:1 panorama.

The HEVC streams are tagged limited-range BT.709. No standard HDR/log signalling is present in
these samples. That does not prove that every Osmo 360 mode is BT.709; it describes only these two
files.

## Proprietary structure

- No standard spherical boxes or tags (`sv3d`, `st3d`, `proj`, `projection_type`) were found.
- DJI stores a root `camd` box containing a second internal MOV with synchronized `djmd` tracks.
- DJI `udta` includes `dbpm`, `dbcm`, `btec`, `fsid`, `Xtra`, `covr`, `snal` and `tnal` data.
- Metadata identifies `dvtm_oq101.proto`, `dbginfo_oq101.proto`, camera model Osmo 360 and sensor
  model OV68A40.
- The primary metadata includes large binary calibration/optics payloads. Without DJI's protobuf
  definitions, it is not responsible to label unknown fields as gyro, GPS or lens matrices.

## Consequence for direct import

Renaming `.OSV` to `.MOV` or exposing only one HEVC track cannot produce a usable 360 clip. A
direct importer must keep both lens frames in lockstep, decode DJI calibration/telemetry, stitch
and blend the overlap, and apply the correct orientation/stabilization model.

The original `.OSV` must remain the source of truth. A prototype should never strip the unknown
DJI boxes from the only copy.

## Direct-stitch experiment

Both HEVC lens tracks were decoded together and passed to FFmpeg's dual-fisheye projection. With
an experimental 190-degree input field of view, the result is a coherent 2:1 panorama and is close
to the embedded DJI cover image after a horizontal yaw offset. This establishes that track order,
basic lens orientation and the overall projection model are understood.

The experiment still exposes the product boundary clearly: a generic projection does not use the
per-camera payloads, cannot reproduce DJI's overlap blend, and does not yet apply motion telemetry.
It is a useful Phase 2 fixture, not a claim of DJI Studio parity.

## Reproduce the inspection

```sh
./scripts/inspect-osv.sh "Sample Footage Osmo 360/CAM_20251103211157_0001_D.OSV"
./scripts/prototype-stitch-frame.sh "Sample Footage Osmo 360/CAM_20251103211157_0001_D.OSV"
```

For deeper local inspection:

```sh
ffprobe -v error -show_format -show_streams -of json clip.OSV
ffprobe -v trace -i clip.OSV 2>&1 | rg "type:'camd'|type:'dbpm'|type:'dbcm'|type:'Xtra'"
```
