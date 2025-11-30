---
'@home-automation/deep-heating-state': patch
---

Remove rxjs-multi-scan dependency and replace with native RxJS 7 operators

The rxjs-multi-scan package (unmaintained since 2018) required RxJS 6.x, causing type
incompatibilities in Nix Docker builds after the RxJS 7 upgrade. Replaced multiScan
calls with merge + scan pattern using native RxJS 7 operators.
