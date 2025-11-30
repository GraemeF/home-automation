---
'@home-automation/deep-heating-home-assistant': patch
'@home-automation/deep-heating-rx': patch
---

Add Effect Stream-based entity polling with automatic retry

- Export `getEntityUpdatesStream` that uses Effect Stream with `Schedule.fixed` for polling and `Schedule.exponential` for retry on failures
- Update DeepHeating to consume the Effect Stream via adapter at the composition root
