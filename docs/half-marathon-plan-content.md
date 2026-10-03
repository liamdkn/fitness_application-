# Liam's running plan content — base building to half marathon, 2 days/week

This is the actual plan content to seed into `running_plans`/`planned_runs`
once the schema from `docs/running-plan-brief.md` is built - not an
engineering brief, the real week-by-week data. Designed around: 2 runs/week
only, gym Mon/Tue/Thu/Fri (new schedule), ~6 weeks of running experience
so far (per prior conversation, no target race date, not in a hurry),
goal is eventually a marathon but half marathon first.

**One assumption flagged up front, please correct it if wrong:** I don't
have your actual current run duration/distance on file, so Week 1 below
assumes you can currently comfortably run 20-25 minutes continuously
(typical for ~6 weeks of consistent beginner running). If that's off in
either direction, the whole progression shifts - tell me your actual
current easy-run length and I'll re-scale it before this gets seeded in.

## Why 2 days/week is workable, but with a real caveat

Researched this rather than guessing: running-twice-a-week plans for a
**half marathon** are a documented, legitimate approach - the structure
is one midweek quality run plus one weekend long run, with the other
days' strength/cross-training work (your 4x/week gym already covers
this) doing real work to protect against the injury risk that comes
with low running frequency. The honest caveat: that same research is
specifically about half marathon distance. The established "run fewer,
higher-quality days" marathon methods (e.g. the FIRST/"Run Less Run
Faster" program) use **3** running days/week minimum for full marathon
distance, not 2 - 26.2 miles asks more of connective tissue than 13.1
does, and the lower-frequency literature doesn't really support staying
at 2 days once you're marathon training specifically. Flagging this now
so it's not a surprise later: this plan gets you to a half marathon on
2 days/week confidently; stepping up to a full marathon afterward is
the point where adding a third easy run/week becomes a real
recommendation, not just a nice-to-have. Bridge that when you get there,
not now.

## Day placement

Given Mon/Tue/Thu/Fri gym: **Wednesday** (midweek run, sits between
Tuesday and Thursday gym days) and **Saturday** (weekend long run, right
after Friday's gym day). **Sunday stays fully off** - this matches his
actual PT-confirmed weekly schedule exactly (Mon Upper A, Tue Lower A,
Wed run, Thu Upper B, Fri Lower B, Sat run, Sun off), so these day
assignments are no longer just a suggested default.

## Phase 1 — Base Building (weeks 1-6)

Goal: get to comfortably running 45-50 minutes continuously, twice a
week, before any pace-specific work starts. Both runs **easy/
conversational pace** - you should be able to hold a conversation the
whole way. Time-based targets, not distance (avoids the common beginner
mistake of chasing pace too early) - ~10% increase per week, a lighter
week every 4th week to let things settle before the next push.

| Week | Wed (easy) | Sat (easy, longer) |
|---|---|---|
| 1 | 20 min | 25 min |
| 2 | 22 min | 28 min |
| 3 | 24 min | 31 min |
| 4 (light) | 20 min | 25 min |
| 5 | 28 min | 36 min |
| 6 | 30 min | 40 min |

## Phase 2 — Half Marathon Build (weeks 7-16)

Wednesday becomes the "quality" day - alternating **tempo** (sustained,
comfortably-hard, not flat-out) and easy-with-strides weeks rather than
true interval/track work. Two days/week is tight for intervals + tempo
+ long all at once, and tempo work carries more direct half-marathon
benefit per session for a first-timer than short speed intervals do -
intervals are a reasonable thing to add once a 3rd day exists (post-
half-marathon, if a 4-day marathon buildup happens later). Saturday long
run progresses toward race distance but peaks under it (~10-11 miles,
not the full 13.1) before a taper - standard practice, the taper itself
is the final hard adaptation, not a missed training opportunity.

| Week | Wed | Sat (long run) |
|---|---|---|
| 7 | 30 min easy | 7 km |
| 8 | 25 min tempo (10 min easy + 15 tempo + 5 easy) | 8 km |
| 9 | 35 min easy | 9 km |
| 10 | 30 min tempo (10 easy + 20 tempo) | 10 km |
| 11 (light) | 25 min easy | 8 km |
| 12 | 35 min tempo | 12 km |
| 13 | 30 min easy w/ strides | 14 km |
| 14 | 35 min tempo | 16 km |
| 15 (peak) | 30 min easy | 17 km |
| 16 (taper) | 20 min easy | 10 km |
| 17 (taper) | 15 min easy | 6 km |
| 18 | Race week - short shakeout run or rest | **Half marathon (21.1 km)** |

## Notes for seeding into `planned_runs`

- `run_type`: Phase 1 rows are all `'easy'`. Phase 2 Wednesdays alternate
  `'easy'` and `'tempo'`; Saturdays are `'long'`; race week is `'race_pace'`
  or just the race itself, worth a dedicated row either way.
- `notes` column carries the tempo-segment breakdown (e.g. "10 min easy
  + 15 min tempo + 5 min easy") since that's structure a single
  `target_distance_km` can't express.
- `target_distance_km` is left approximate/null for Phase 1 (time-based,
  distance doesn't matter yet) and filled in from Phase 2 onward.
- Actual start date and exact week-7 transition point should flex based
  on how Phase 1 actually goes, not be locked to a calendar date now -
  the adjustability from `docs/running-plan-brief.md` (editable rows,
  no rigid schedule) is what makes that possible.
