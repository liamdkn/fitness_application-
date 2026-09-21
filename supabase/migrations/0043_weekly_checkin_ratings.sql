-- New weekly check-in recap page asks two quick questions - a 1-5 rating
-- plus a free-text improvement note for Nutrition and for Activity/
-- Training. Deliberately new columns rather than reusing the existing
-- nutrition_adherence/training_adherence (also 1-5, from the old
-- subjective survey) - those still drive WeeklyCheckin.hasSurveyContent,
-- which hides the old WeeklyCheckinSummary card specifically because the
-- current flow "no longer collects any of this" (see that type's own doc
-- comment); reusing them would silently resurrect that deprecated card
-- for every new check-in.
alter table weekly_checkins
  add column nutrition_rating int check (nutrition_rating between 1 and 5),
  add column nutrition_notes text,
  add column training_rating int check (training_rating between 1 and 5),
  add column training_notes text;
