![Signed](https://img.shields.io/badge/Signed-No-FF3333)
![Trackmania2020](https://img.shields.io/badge/Game-Trackmania-blue)

# Water Fields

An Openplanet plugin for creating and managing custom water fields in Trackmania maps. 

## Layout

Production code lives in `src/`. Local development controls and checks live in ignored `/dev/` and are excluded from `.op` builds.

The original block, wrapper and prefab GBX files live in `assets/templates/` and are included in the `.op` build. WaterFields reads fresh copies from these files when generating a water field.

Phase 2 supports generating and placing one native water volume from explicit bounds in the development panel. Authoring uses exposed block APIs, with no executable hash restriction or raw game-memory access in production. Generated files use `Blocks/WaterFields/`; reservations prevent identity reuse, and generation records report placement and rollback outcomes separately.

Saved-map portability is still pending Phase 3. A successful editor placement does not establish that water survives an ordinary map save.

Water stays within the active map's X/Z borders by default, using its grid size at 32 metres per cell. General settings can allow water outside those borders; its supporting ghost block must still occupy a valid, empty map cell.

## Build

```powershell
python _build.py
```

## Credits

ar
