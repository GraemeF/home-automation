---
'@home-automation/deep-heating-rx': patch
---

Improved error resilience in RxJS pipelines. Pipelines now gracefully handle mismatched data instead of terminating the entire stream, ensuring heating control continues even when encountering corrupted updates.
