---
title: Fetch with filter
story: Fetches all people, who play guitar in their freetime.
---

```json
{
  "method": "fetch",
  "params": {
    "id": "f76",
    "matches": ["^persons/.*"],
    "equals": {
      "hobby": "guitar"
    }
  }
}```
