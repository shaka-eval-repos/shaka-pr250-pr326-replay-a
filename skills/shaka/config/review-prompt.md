Report on:
- Correctness: name the input or state that makes it wrong, not a general worry.
- Contract drift: does a document, comment, or config restate a rule that the code now implements differently?
- Security and trust: does it weaken a gate, widen permissions, or trust candidate content?
- Tests: is there a test that fails if this change is reverted? Name what is untested.
- Simplicity: what could be deleted without losing behavior?

How to report:
- Anchor each finding to file:line. A finding you cannot make concrete is an observation; label it as one.
- If you find nothing, say "no findings". Do not invent findings to seem useful.
