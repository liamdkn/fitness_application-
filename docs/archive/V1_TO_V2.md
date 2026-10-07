# V1 to V2 roadmap

## V1: stable personal release

V1 is the dependable foundation: private and correct personal records, clear provenance, robust backup and migration practices, predictable offline behavior, and an understandable release process. Finish the P0/P1 items in [the release review](SECURITY_AND_RELEASE_READINESS.md), validate a clean device build, document limitations, and tag the release. Avoid widening the product surface until the core records can be safely exported, corrected, and deleted.

### V1 completion gates

- The setup and migration process works from a clean checkout and a blank Supabase project.
- RLS and Storage ownership tests demonstrate isolation across two users.
- Users can recover their account and request/export/delete their data.
- Core calculations, date boundaries, edits, deletes, and offline retry behavior are verified.
- Privacy, health-data use, retention, and known limitations are written down.

## V2: carefully scoped LLM assistance

The first LLM feature should help the user understand their own logged data, not autonomously prescribe a diet, diagnose a condition, or alter records. A sensible initial experiment is an **opt-in weekly training/nutrition reflection** that summarizes user-selected, date-bounded records, cites the underlying dates/metrics, states when data is missing, and suggests questions the user can consider. Start with a read-only generated draft; never write meals, goals, workouts, or health records automatically.

### Architecture and privacy guardrails

- Keep provider credentials and model calls on a server-side endpoint (for example, a Supabase Edge Function). Never embed an LLM API key in the iOS app.
- Authenticate each request and enforce ownership at the server boundary. Fetch only the minimum rows needed for the requested interval; do not pass full history by default.
- Make the feature explicitly opt-in, explain which fields leave the device/Supabase boundary, and provide a no-LLM path with no penalty.
- Exclude direct identifiers and precise route coordinates by default. Minimize or aggregate sensitive fields, and avoid photos/HealthKit raw samples unless a later feature has a clear need and separate consent.
- Treat user text and external catalog data as untrusted input. Use structured prompts/output schemas, strict size limits, rate limits, timeout/cost budgets, and safe rendering. Do not allow generated output to invoke tools or mutate records.
- Label output as AI-generated, provide source date ranges and traceable supporting metrics, distinguish recorded fact from interpretation, and allow feedback/reporting.
- Define provider retention/training settings, regional processing, deletion behavior, and incident handling before launch. Log request IDs and cost/latency metadata, not raw health prompts or responses by default.
- Evaluate hallucination, missing-data behavior, unsafe advice, bias, prompt injection, and reproducibility with a fixed test set before inviting users.

### Delivery sequence

1. Decide exact user problem and opt-in consent language; assess whether a deterministic insight solves it better.
2. Build an internal prototype against synthetic data only; define a strict structured response and evidence links.
3. Add an authenticated server endpoint with least-privilege data access, budgets, and no writes.
4. Evaluate quality and privacy with representative, de-identified/synthetic cases; add user-visible uncertainty and feedback.
5. Release to a small opt-in cohort, monitor costs/errors, and provide a kill switch and deletion path.
6. Consider broader coaching only after the read-only reflection is demonstrably useful and safe.

## Reduce complexity without losing domain clarity

A smaller source tree is a goal, but fewer files or models alone is not a quality metric. Before V2, map each model/repository/service to its owning feature and actual call sites. Consolidate genuinely duplicated transport, validation, date conversion, and persistence mechanics; keep distinct concepts separate when their lifecycle or rules differ. Remove dead code only with compiler/reference evidence. Split large views by user journey and move business calculations into small pure functions. Preserve migration history and database model boundaries; do not combine unrelated database entities to chase a lower model count. Require behavior-preserving tests before each structural refactor.
