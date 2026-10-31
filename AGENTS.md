# NeXTsound

Preserve the exact spelling `NeXTsound` in the product name, repository name, and local project directory.

## Planning

The [product baseline](https://git.layered.work/phranck/NeXTsound/issues/1) records the product and architecture decisions. Work is tracked in the repository's issues on git.layered.work and on its [project board](https://git.layered.work/phranck/NeXTsound/projects/13), which `~/.agents/tools/gitea/board.py` keeps current. An issue's column is its status, and its exclusive label `priority/P0`, `priority/P1` or `priority/P2` is its priority. Read an issue and its comments before starting its work.

## Issues

When listing or referencing issues in replies, always link them, e.g. [#38](https://git.layered.work/phranck/NeXTsound/issues/38).

## Documentation

`Papers` contains the living German documentation and stays outside version control. Repository documentation and interface copy are English. Use the `PAP-NXS` paper prefix and maintain the local papers overview and the global projects overview together.

## Hardware

The target is the Waveshare RP2350-Zero-M with the photographed MAX98357A breakout. Prommer and the SoundBox KiCad projects are separate projects. Do not change them as part of NeXTsound work.

A successful build or host test does not establish board compatibility, audio timing, amplifier behavior, or speaker safety. Physical flashing and hardware changes require explicit agreement. Keep the operating clock within the RP2350 manufacturer's specification.
