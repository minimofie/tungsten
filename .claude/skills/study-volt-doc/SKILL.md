---
name: study-volt-doc
description: Use before starting any coding activity on Tungsten — read the Volt executor docs for every Volt function the change uses.
---

Study the Volt documentation at https://docs.voltbz.net/docs before coding.

For every Volt (executor) function the change uses, open its page (`https://docs.voltbz.net/docs/<library>/<name>`, e.g. `/docs/debug/getproto`, `/docs/closures/getfunctionhash`, `/docs/scripts/getscriptclosure`, `/docs/environment/filtergc`) and check its signature, accepted argument types, return values and cautions. Target only Volt's documented API (no fallbacks for other executors). Record anything new in `docs/volt-api-notes.md`, add the function to `Tungsten/base/integrity.luau` and give `tests/harness.luau` a stand-in.
