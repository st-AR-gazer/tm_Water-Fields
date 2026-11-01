# WaterFields.Export dependencies

Hayo! This is a small helper DLL, its compression deps are required to be distributed under the GPL-3.0-or-later license (yukk). So... this helper uses that license xdd.

| Dependency | Version | Declared license | Source |
| --- | --- | --- | --- |
| GBX.NET | 2.4.3 | MIT | https://github.com/BigBang1112/gbx-net/tree/a83e1ef612e4ad3aa46dd566dfa82265df90442d |
| GBX.NET.LZO | 2.1.4 | GPL-3.0-or-later | https://www.nuget.org/packages/GBX.NET.LZO/2.1.4 |
| NativeSharpLzo | 0.3.5 | GPL-3.0-or-later | https://github.com/BigBang1112/NativeSharpLzo/tree/298767511961fec0ad9585d782b3bdb5a08f5e00 |
| TmEssentials | 2.7.0 | MIT | https://github.com/BigBang1112/tm-essentials/tree/9c3b0a0ce43f4e27fd9d367bff797f3dc3b2a2b5 |

The Native AOT DLL also includes Microsoft's .NET runtime code and the Microsoft libraries listed in `packages.lock.json`. Carry their MIT licenses and runtime third-party notices into the release bundle. GPL distribution also requires complete corresponding source; this build does not assemble a public source bundle.
GBX.NET, its LZO adapter, NativeSharpLzo and TmEssentials are copyright (c) 2026 Petr Pivoňka.

The rest of what I've made is in the public domain (The Unlicense)
