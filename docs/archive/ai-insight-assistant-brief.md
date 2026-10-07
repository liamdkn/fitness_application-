# "Insight" — in-app AI assistant (glowing orb, drops into any screen)

## The ask

A visual AI-assistant element - a breathing, pink-glowing ring/orb,
consistent design wherever it appears - that drops into a screen
(e.g. Nutrition) and gives optimization advice, like an in-app PT.
Two follow-up requirements: the advice has to be genuinely useful,
not generic filler, and it should be able to **act** in the app, not
just talk.

This is new ground for the app - first LLM integration, first time
calling an external AI API, first Edge Function (checked: `supabase/`
has no `functions/` directory yet, this would be the first). Worth
knowing going in: unlike everything built so far (Supabase, HealthKit,
Open Food Facts), this one has a real ongoing per-call cost, not a
flat free tier. Scoped below to keep that cost bounded and the advice
actually grounded in real data rather than a chatbot guessing at your
numbers.

## 1. Why this can't just call an AI API from the iOS app directly

Any API key bundled into the app binary can be extracted - fine for a
no-cost service like Open Food Facts, not fine for a metered API key
that costs real money per call and would be sitting in plaintext in
anyone's hands who decompiles the app (irrelevant today at 1 user, but
this app is explicitly being built with a friend eventually using it
too). Standard fix: a Supabase Edge Function (Deno, same project,
no new infra provider) holds the API key server-side as a secret, the
app calls *that* function, the function calls the AI API. The app
never sees the key.

## 2. Grounded, not improvised - the single most important design call

The assistant should **never do its own math**. Nutrition/TDEE/
training numbers come from the app's existing, already-tested
engines - `AdaptiveTDEEEngine`, `NutritionDebtSummary`/`MacroDebt`,
`StepsDebt`, `OffPlanWeightAdvisor`, the running plan's planned-vs-
actual comparison. The Edge Function call passes those **already-
computed** structured numbers as context and asks the model to turn
them into coaching language and a recommendation - not "what's my
TDEE," but "here's the computed TDEE, the week's logging completeness,
and the last 3 days' intake, write one practical, specific suggestion
from that." This is the difference between genuinely useful advice
and a chatbot hallucinating a number that contradicts what the rest
of the app is showing - worth treating as non-negotiable, not a nice-
to-have, given your own stated preference for data-backed answers
over confident-sounding guesses.

Per-screen context payloads (what gets sent, built client-side from
data already in each screen's view model, no new queries needed):
- **Nutrition**: today's/this-week's macro debt, calorie banking
  status (once built per `pt-program-integration-brief.md`),
  recent off-plan flags, current goal phase targets.
- **Train**: this week's routine adherence (sessions done vs.
  scheduled), recent set/rep progression trend, any flagged pain
  notes if that gets built.
- **Weekly Insights / Dashboard**: the adherence score, weight trend,
  TDEE estimate and confidence, running plan progress.

## 3. "Can it interact with the app" - yes, via a small, explicit tool set

Not free-form database access - a short, named list of actions the
model can propose, each mapped to a repository method that already
exists:
- `proposeCalorieAdjustment` → a goal-phase target tweak, via
  `GoalsRepository`
- `proposeMealSuggestion` → surfaces a saved meal/menu option that
  fits remaining macros (ties into `meal-plan-options-brief.md`'s
  scoring logic rather than reinventing it)
- `flagOffPlanDay` → `DailyCheckinRepository`/off-plan flag, same as
  the manual toggle
- `proposeRunReschedule` → moves a `planned_runs` row's date

Every one of these is a **propose, not apply** - the model's response
includes the suggested action as structured data, the app shows it as
a normal confirm card (same shape as the Watch-workout import cards
`WatchActivityViewModel` already uses - propose, show, confirm, then
and only then call the repository), and nothing is written until
Liam taps confirm. This isn't extra caution for its own sake - an LLM
occasionally gets a suggestion wrong even when well-grounded, and
irreversible silent writes to goal targets or logged data are exactly
the kind of thing this app's whole design has avoided everywhere
else (every Watch import, every destructive change this session has
gone through a confirm step first). No reason to break that pattern
here.

## 4. Medical-constraint handling - read-only, same rule as before

Given the shoulder/hernia content now in the app (per
`pt-program-integration-brief.md`'s routine notes), the
assistant can **read and respect** those constraints (e.g. won't
suggest an overhead press as a progression swap) but must never
generate a *new* exercise modification or medical judgment call of
its own - same boundary already established for the rest of the app:
reference text and existing structured data only, nothing invented.

## 5. Trigger model - on tap, not on every screen load

Calling the Edge Function on every screen appearance burns API calls
for no reason (most visits won't have anything new worth saying).
Two-tier approach: a cheap, local, rule-based check (no API call) runs
on screen load - e.g. "3+ days since last Insight visit and nutrition
debt has moved more than X" - and shows a small notification dot on
the orb if true; the actual LLM call only fires when Liam taps it.
Keeps cost proportional to actual use, not screen-open frequency.

## 6. One shared assistant, not one-per-screen

Liam's instinct on this (right call, matching how the rest of the app
already centralizes shared state - e.g. `CheckinAvailabilityService
.shared`, a single `@MainActor` observable singleton read from
wherever it's needed, rather than each screen keeping its own copy):
**one** `InsightAssistantManager` (`ObservableObject`, injected once
via `.environmentObject` at the app root, same pattern as
`CheckinAvailabilityService`), holding `@Published var activeContext:
InsightContext?` (`.nutrition`, `.train`, `.dashboard`, or `nil` for
"not currently relevant here"). Only one context is ever true at a
time - each screen sets it on `.onAppear` (`insightManager
.setContext(.nutrition)`) and clears it on `.onDisappear`, so moving
between tabs just flips which context is current rather than juggling
several independently-animating orb instances that could theoretically
disagree with each other.

The orb itself is mounted **once**, as an overlay at the root level
(above the `TabView`, same layer a global toast/banner would live at),
not re-created per screen. It reads `insightManager.activeContext`:
`nil` means don't render at all (e.g. mid-workout logging screens,
where surfacing it would just be noise), otherwise render it, keyed
to whichever context is current so tapping it opens a sheet pre-loaded
with that screen's data. This also directly solves "where it's true
it shows in that moment" - the manager's `activeContext` **is** that
truth value, and every screen just asks it rather than tracking its
own visibility flag.

`InsightOrbView` itself (the rendered component, built once, reused
by that single overlay): a `Circle` with a `RadialGradient` pink glow,
blurred and layered (2-3 offset circles at different opacities/blur
radii reads as a glow, cheaper than a real shader), animated via
`.scaleEffect`/`.opacity` on a `.repeatForever(autoreverses: true)`
animation for the breathing effect, plus a thin rotating gradient
stroke for the "lightning ring" look (an `AngularGradient` stroke
works well and is GPU-cheap, no need for a custom Metal shader here).

## 7. Model/cost choice

Worth picking a smaller/cheaper model tier for this rather than the
most capable one available - the task per call is narrow (narrate
already-computed numbers, pick from a small tool list), not open-
ended reasoning, so a lighter model is both cheaper and likely just
as good here. Exact model choice is a Claude Code / implementation
call once an API account exists, not something to lock in now.

## 8. Sequencing

Genuinely bigger than anything else in the backlog right now (new
infra, new account/API key, new cost line) - reasonable to sequence
after the nearer-term work already queued (running plan, PT program
integration, nutrition revamp) rather than ahead of it, unless this
has become the priority.
