import subprocess
import shutil
from pathlib import Path

root = Path(__file__).resolve().parent
subprocess.run(
    [
        "dotnet",
        "publish",
        str(root / "helper/WaterFields.Export.csproj"),
        "--configuration",
        "Release",
        "--output",
        str(root / "dev/helper/publish"),
        "--nologo",
        "-p:RestoreLockedMode=true",
    ],
    cwd=root,
    check=True,
)
assets = root / "src/assets"
assets.mkdir(exist_ok=True)
for name in (
    "WaterFields.Export.dll",
    "liblzo2.dll",
    "GPL-3.0.txt",
    "third_party_notices.md",
):
    shutil.copy2(root / "dev/helper/publish" / name, assets / name)
