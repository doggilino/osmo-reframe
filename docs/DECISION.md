# Product decision: use batch ingest plus Final Cut's native 360 tools

Decision date: 12 August 2026.

## Result

Do not turn OsmoReframe into a production FxPlug. The useful workflow is:

1. Register/import a folder of Osmo 360 originals in DJI Studio when required by the exporter.
2. Export all selected `.OSV` files in a batch with DJI Panorama Exporter.
3. Import the resulting equirectangular MP4 files into Final Cut Pro.
4. Use Final Cut's native Orientation and color controls.

This removes the manual one-file-at-a-time export workflow without duplicating controls that Final
Cut already provides.

## Evidence

- Direct import of both supplied `.OSV` files in Final Cut Pro failed with: “The selected files
  were not imported because one or more required 3rd-party plug-ins are not installed.”
- The tested batch export produced a complete 6000 x 3000 HEVC Main 10 equirectangular file with
  audio and the source duration.
- Final Cut recognized that output as monoscopic equirectangular 360 media.
- In a normal project Final Cut exposed keyframeable Tilt, Pan, Roll, Field of View and Mapping,
  together with its native color tools.
- The custom OsmoReframe effect successfully duplicated those operations, but did not improve the
  ingest path or DJI stitching quality.

## Why the third-party exporter is not part of the plugin

DJI Panorama Exporter relies on private DJI Studio implementation details rather than a supported
DJI export API. It manipulates Studio project data and invokes a private export path. It works as a
personal batch utility on the tested machine, but it should not be bundled or presented as a stable,
distributable OsmoReframe backend.

## Status of the prototype

The FxPlug, shader, Motion template and direct-stitch experiments remain in this repository as
research. The locally installed OsmoReframe effect may be used for experiments, but it is not
required for the recommended editing workflow.

Reconsider a production plugin only if DJI publishes an OSV/stitching SDK, an official batch API,
or a supported Final Cut Media Extension. A direct OSV reader without DJI's calibrated stitching
and stabilization would be a quality regression.
