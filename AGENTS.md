# NeXTsound

Preserve the exact spelling `NeXTsound` in the product name, repository name, and local project directory.

## Planning

The [product baseline](https://github.com/phranck/NeXTsound/issues/1) records the product and architecture decisions. Work is tracked in repository issues and the [NeXTsound project board](https://github.com/users/phranck/projects/16). Read an issue and its comments before starting its work.

Project ID: `PVT_kwHODzNVpM4BnjJG`. Status field: `PVTSSF_lAHODzNVpM4BnjJGzhmHPZg`. Status options are Backlog `1456fec7`, Ready `ec9d8b53`, In progress `1e9a5476`, In review `e5b6a05b`, and Done `9a4ba4ac`. Priority field: `PVTSSF_lAHODzNVpM4BnjJGzhmHPmk`. Priority options are P0 `7e4123f2`, P1 `9dbf8d89`, and P2 `a7fcd9ae`.

## Documentation

`Papers` contains the living German documentation and stays outside version control. Repository documentation and interface copy are English. Use the `PAP-NXS` paper prefix and maintain the local papers overview and the global projects overview together.

## Hardware

The target is the Waveshare RP2350-Zero-M with the photographed MAX98357A breakout. Prommer and the SoundBox KiCad projects are separate projects. Do not change them as part of NeXTsound work.

A successful build or host test does not establish board compatibility, audio timing, amplifier behavior, or speaker safety. Physical flashing and hardware changes require explicit agreement. Keep the operating clock within the RP2350 manufacturer's specification.
