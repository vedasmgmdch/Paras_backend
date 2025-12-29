# Instruction Logs Posting Guidance

To keep doctor and patient views consistent:

1. Each calendar day for an active treatment, post the *entire* set of instructions (general + specific) once, marking each with followed true/false.  
2. Subsequent toggles that day can re-post only changed items or the whole set; backend endpoint deletes prior rows for (date, group) on each payload to keep state authoritative.
3. Avoid sending blank `instruction_text`. The client now filters these out; if all items are blank nothing is posted.
4. If additional instruction categories are introduced (e.g., dietary), treat them as a new `group` value; doctor UI automatically groups by distinct groups.
5. For retroactive data fixes, use `forceResyncInstructionLogs()` in `AppState` to bulk push historical local logs.

Recommended Future Enhancement:
- Add an automatic daily full push when patient opens an instruction screen for the first time each day so unfollowed items appear as "Not" in doctor analytics.
