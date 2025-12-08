---
'@home-automation/deep-heating-rx': patch
---

Fix TRV control state updates being suppressed when device returns from unavailable

When a TRV goes unavailable and comes back online, the device may report a stale
target temperature that differs from what the system last commanded. Previously,
if the device reported the same mode and temperature as our cached synthesised
command, the device update would be suppressed and no corrective action would be
generated.

Now, device updates are always emitted if the source differs from the cached
value (Device vs Synthesised), ensuring the action pipeline can re-evaluate and
push the correct temperature to the TRV.
