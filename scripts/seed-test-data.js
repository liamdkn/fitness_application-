#!/usr/bin/env node
/*
 * Floods the TEST account (test@test.com) with months of past data and a
 * couple of months of future plans, so every screen has something to show:
 * weigh-ins, daily + weekly check-ins, meals, drinks and caffeine, water, steps, sleep, workouts
 * with progressive overload, incline walks, GPS-routed runs, a running plan,
 * meal prep batches (fridge + freezer), planned treats, TDEE estimates.
 *
 *   cd scripts && npm install && node seed-test-data.js
 *
 * Options:
 *   --past=150          days of history (default 150)
 *   --future=70         days of future plans (default 70)
 *   --health-logs      also write nutrition_logs (fake Apple Health daily totals)
 *
 * Safety: refuses to touch any account but test@test.com, and runs in one
 * transaction. It RESETS that account's transactional data first (meals,
 * weigh-ins, check-ins, workouts, cardio, steps, sleep, water, plans...) so
 * running it twice gives the same result, not duplicates. Routines, goals,
 * foods, gyms, settings and saved meals are left alone.
 *
 * Calories come from the logged meals - Weekly Insights, TDEE, the dashboard
 * and the check-ins all read the meal log first (NutritionRepository.
 * fetchDailyTotals), falling back to Apple Health only for days with none.
 * --health-logs is only for testing that fallback: the Nutrition tab adds
 * Health totals on top of the meal log, so a day with both shows double.
 */
const path = require('path');
const crypto = require('crypto');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const TEST_EMAIL = 'test@test.com';
const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? Number(hit.split('=')[1]) : fallback;
};
const PAST = arg('past', 150);
const FUTURE = arg('future', 70);
const HEALTH_LOGS = process.argv.includes('--health-logs');

// ---------- deterministic randomness, so reruns match ----------
let seed = 20261003;
const rnd = () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const between = (a, b) => a + rnd() * (b - a);
const intBetween = (a, b) => Math.floor(between(a, b + 1));
const pick = (list) => list[Math.floor(rnd() * list.length)];
const chance = (p) => rnd() < p;
const gauss = (sd) => (rnd() + rnd() + rnd() - 1.5) * (sd / 0.5);
const round = (v, dp = 1) => Math.round(v * 10 ** dp) / 10 ** dp;
const uuid = () => crypto.randomUUID();

// ---------- dates ----------
const today = new Date(); today.setHours(0, 0, 0, 0);
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const at = (d, h, m = 0) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m).toISOString();
const swiftWeekday = (d) => d.getDay() + 1; // 1 = Sunday, like Calendar.Component.weekday
const mondayOf = (d) => addDays(d, -((d.getDay() + 6) % 7));
const daysBetween = (a, b) => Math.round((b - a) / 86400000);

async function insertMany(db, table, columns, rows, chunk = 400) {
  for (let i = 0; i < rows.length; i += chunk) {
    const part = rows.slice(i, i + chunk);
    const params = [];
    const tuples = part.map((row) => `(${row.map((v) => { params.push(v); return `$${params.length}`; }).join(',')})`);
    await db.query(`insert into ${table} (${columns.join(',')}) values ${tuples.join(',')}`, params);
  }
  return rows.length;
}

// Meal templates: [food name, relative amount (g, or a count for eggs)]
const MEALS = {
  Preworkout: [
    [['Banana', 120], ['Peanut Butter', 15]],
    [['Whey Protein Powder', 30], ['Banana', 120]],
    [['Apple', 180], ['Almonds', 20]],
  ],
  Breakfast: [
    [['Oats (Dry)', 60], ['Greek Yogurt (0%)', 150], ['Blueberries', 60], ['Whey Protein Powder', 25]],
    [['Egg', 3], ['Wholemeal Bread', 70], ['Avocado', 60]],
    [['Greek Yogurt (0%)', 250], ['Oats (Dry)', 40], ['Banana', 100], ['Peanut Butter', 15]],
  ],
  Lunch: [
    [['Chicken Breast', 150], ['White Rice (Cooked)', 220], ['Broccoli', 100]],
    [['Tuna (Canned in Water)', 120], ['Pasta (Cooked)', 200], ['Bell Pepper', 80]],
    [['Turkey Breast', 130], ['Tortilla Wrap', 64], ['Spinach', 40], ['Tomato', 80]],
  ],
  Dinner: [
    [['Salmon Fillet', 150], ['Sweet Potato (Baked)', 220], ['Green Beans', 100]],
    [['Beef Mince (5% Fat)', 160], ['Pasta (Cooked)', 220], ['Onion', 60], ['Tomato', 100]],
    [['Chicken Thigh', 170], ['Basmati Rice (Cooked)', 220], ['Spinach', 60]],
  ],
  Snacks: [
    [['Apple', 180], ['Almonds', 25]],
    [['Dark Chocolate (70%)', 20], ['Greek Yogurt (0%)', 150]],
    [['Cottage Cheese', 150], ['Pineapple', 100]],
  ],
};
const SLOT_SHARE = { Preworkout: 0.08, Breakfast: 0.25, Lunch: 0.28, Dinner: 0.32, Snacks: 0.07 };
const SLOT_HOUR = { Preworkout: 7, Breakfast: 9, Lunch: 13, Dinner: 19, Snacks: 16 };

const RUN_LOOP = { lat: 53.653, lon: -6.681 };
function runRoute(km, jitter) {
  const R = (km * 1000) / (2 * Math.PI) * (1 + 0.15 * jitter);
  const lat0 = RUN_LOOP.lat + jitter * 0.01, lon0 = RUN_LOOP.lon + jitter * 0.012;
  const N = 220, pts = [], dist = [0];
  for (let i = 0; i <= N; i++) {
    const th = (i / N) * 2 * Math.PI;
    const r = R * (1 + 0.22 * Math.sin(th / 2) ** 2 * Math.cos(th + jitter));
    pts.push([
      Math.round((lat0 + (r * Math.sin(th)) / 111320) * 1e5) / 1e5,
      Math.round((lon0 + (r * Math.cos(th)) / (111320 * Math.cos((lat0 * Math.PI) / 180))) * 1e5) / 1e5,
      0,
    ]);
  }
  for (let i = 1; i < pts.length; i++) {
    const dy = (pts[i][0] - pts[i - 1][0]) * 111320;
    const dx = (pts[i][1] - pts[i - 1][1]) * 111320 * Math.cos((lat0 * Math.PI) / 180);
    dist.push(dist[i - 1] + Math.hypot(dx, dy));
  }
  const total = dist[dist.length - 1];
  const base = between(5.2, 6.1); // min/km
  let t = 0;
  for (let i = 1; i < pts.length; i++) {
    const f = dist[i] / total;
    const pace = base * (1 + 0.06 * Math.sin(f * 9) + (f > 0.85 ? -0.07 : 0) + (f < 0.1 ? 0.05 : 0));
    t += ((dist[i] - dist[i - 1]) / 1000) * pace * 60;
    pts[i][2] = Math.round(t);
  }
  return { pts, seconds: t, meters: total };
}

async function main() {
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  const who = (await db.query('select id, email from auth.users where email = $1', [TEST_EMAIL])).rows[0];
  if (!who) throw new Error(`No account with email ${TEST_EMAIL} - refusing to run.`);
  const U = who.id;
  console.log(`Seeding ${who.email} (${PAST} days back, ${FUTURE} ahead)${HEALTH_LOGS ? ', with fake Health nutrition logs' : ''}`);

  const pastDays = Array.from({ length: PAST }, (_, i) => addDays(today, -(PAST - i)));          // oldest .. yesterday
  const futureDays = Array.from({ length: FUTURE }, (_, i) => addDays(today, i + 1));            // tomorrow ..

  // ---------- things we read, never reset ----------
  const goal = (await db.query('select * from user_goals where user_id=$1 order by effective_from desc, created_at desc limit 1', [U])).rows[0];
  const target = {
    kcal: Number(goal?.daily_calorie_target ?? 2100),
    protein: Number(goal?.protein_g_target ?? 170),
    steps: Number(goal?.step_target ?? 10000),
    id: goal?.id ?? null,
  };
  const prefs = (await db.query('select * from user_preferences where user_id=$1', [U])).rows[0];
  const checkinWeekday = prefs?.weekly_checkin_weekday ?? 1; // Swift numbering
  const slots = (await db.query('select id, name from meal_slots where user_id=$1 order by sort_order', [U])).rows;
  if (!slots.length) throw new Error('Test account has no meal slots - open the app once first.');
  const slotId = Object.fromEntries(slots.map((s) => [s.name, s.id]));
  const foodRows = (await db.query("select * from foods where source='seed' or created_by=$1", [U])).rows;
  const food = Object.fromEntries(foodRows.map((f) => [f.name, f]));
  const schedule = (await db.query('select ws.*, rd.label from weekly_schedule ws left join routine_days rd on rd.id=ws.routine_day_id where ws.user_id=$1 and ws.routine_id=(select id from routines where user_id=$1 and is_active)', [U])).rows;
  const dayExercises = (await db.query(`select rde.*, e.name as exercise_name from routine_day_exercises rde join exercises e on e.id=rde.exercise_id
    where rde.routine_day_id in (select id from routine_days where routine_id=(select id from routines where user_id=$1 and is_active)) order by rde.routine_day_id, rde.position`, [U])).rows;
  let containers = (await db.query('select * from water_containers where user_id=$1', [U])).rows;

  await db.query('begin');
  try {
    // ---------- reset the account's transactional data ----------
    for (const sql of [
      'delete from meal_entries where user_id=$1',
      'delete from water_logs where user_id=$1',
      'delete from body_measurements where user_id=$1',
      'delete from body_weight_logs where user_id=$1',
      'delete from daily_checkins where user_id=$1',
      'delete from weekly_checkins where user_id=$1',
      'delete from workouts where user_id=$1',
      'delete from cardio_tracking_sessions where user_id=$1',
      'delete from cardio_step_sessions where user_id=$1',
      'delete from step_logs where user_id=$1',
      'delete from sleep_logs where user_id=$1',
      'delete from nutrition_logs where user_id=$1',
      'delete from tdee_estimates where user_id=$1',
      'delete from planned_treats where user_id=$1',
      'delete from running_plans where user_id=$1',
      'delete from recipes where user_id=$1 and is_meal_prep',
    ]) await db.query(sql, [U]);

    // ---------- drinks: a "Drinks" slot, a brew pot and a pod coffee ----------
    let drinksSlot = slots.find((x) => x.name === 'Drinks');
    if (!drinksSlot) {
      const order = (await db.query('select coalesce(max(sort_order), -1) + 1 as n from meal_slots where user_id=$1', [U])).rows[0].n;
      drinksSlot = (await db.query("insert into meal_slots (user_id, name, sort_order) values ($1,'Drinks',$2) returning id, name", [U, order])).rows[0];
    }
    slotId.Drinks = drinksSlot.id;
    for (const [name, size, mg] of [['Brew pot coffee', 100, 18.75], ['Pod coffee', 150, 80]]) {
      let row = (await db.query('select * from foods where created_by=$1 and name=$2', [U, name])).rows[0];
      if (!row) {
        row = (await db.query(`insert into foods (name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, caffeine_mg, source, is_custom, created_by, is_verified)
          values ($1,$2,'ml',1,0,0,0,$3,'user',true,$4,true) returning *`, [name, size, mg, U])).rows[0];
      }
      food[name] = row;
    }

    if (!containers.length) {
      for (const [name, ml] of [['Bottle', 750], ['Glass', 250]]) {
        containers.push((await db.query('insert into water_containers (user_id, name, volume_ml) values ($1,$2,$3) returning *', [U, name, ml])).rows[0]);
      }
    }

    // ---------- body weight + daily check-ins ----------
    const startKg = 74.2, endKg = 71.4;
    const offPlan = new Map();      // ymd -> true (day was off plan)
    pastDays.forEach((d) => offPlan.set(ymd(d), chance(0.11)));
    const weightOn = new Map();
    pastDays.forEach((d, i) => {
      const trend = startKg + ((endKg - startKg) * i) / (PAST - 1);
      const prevOff = offPlan.get(ymd(addDays(d, -1))) ? 0.6 : 0;
      weightOn.set(ymd(d), round(trend + prevOff + gauss(0.35), 1));
    });
    const workoutDayFor = new Map(schedule.filter((s) => s.day_type === 'workout').map((s) => [s.weekday, s]));
    const restWalkFor = new Map(schedule.filter((s) => s.day_type === 'active_rest').map((s) => [s.weekday, s]));

    const weightRows = [], checkinRows = [];
    pastDays.forEach((d) => {
      const key = ymd(d), kg = weightOn.get(key);
      if (chance(0.93)) weightRows.push([U, at(d, 7, intBetween(0, 40)), kg, 'manual']);
      if (chance(0.88)) {
        const sched = workoutDayFor.get(swiftWeekday(d));
        checkinRows.push([
          U, key, kg, sched?.routine_day_id ?? null, sched?.label ?? null, !sched,
          intBetween(2, 5), intBetween(1, 4), intBetween(2200, 4200), !!offPlan.get(ymd(addDays(d, -1))),
          offPlan.get(ymd(addDays(d, -1))) ? pick(['Pizza night', 'Birthday dinner', 'Pints with friends', 'Takeaway']) : null,
        ]);
      }
    });
    await insertMany(db, 'body_weight_logs', ['user_id', 'logged_at', 'weight_kg', 'source'], weightRows);
    await insertMany(db, 'daily_checkins', ['user_id', 'checkin_date', 'weight_kg', 'routine_day_id', 'workout_choice_label', 'is_rest_day', 'energy_level', 'soreness_level', 'yesterday_water_ml', 'yesterday_off_plan', 'yesterday_off_plan_notes'], checkinRows);

    // ---------- meal prep batches (so some meals come from recipes) ----------
    const prepSpecs = [
      { name: 'Overnight Oats', ago: 2, portions: 4, within: 4, location: 'fridge', items: [['Oats (Dry)', 240], ['Greek Yogurt (0%)', 600], ['Blueberries', 200], ['Whey Protein Powder', 100]] },
      { name: 'Chicken Curry', ago: 12, portions: 6, within: 3, location: 'freezer', items: [['Chicken Thigh', 900], ['Basmati Rice (Cooked)', 900], ['Onion', 200], ['Tomato', 300]] },
      { name: 'Protein Balls', ago: 0, portions: 12, within: 7, location: 'fridge', items: [['Oats (Dry)', 200], ['Peanut Butter', 150], ['Whey Protein Powder', 120], ['Honey', 60]] },
      { name: 'Overnight Oats', ago: 16, portions: 4, within: 4, location: 'fridge', finished: true, items: [['Oats (Dry)', 240], ['Greek Yogurt (0%)', 600], ['Banana', 300], ['Whey Protein Powder', 100]] },
      { name: 'Beef Chilli', ago: 30, portions: 5, within: 4, location: 'fridge', finished: true, items: [['Beef Mince (5% Fat)', 800], ['Kidney Beans (Cooked)', 400], ['Tomato', 400], ['Onion', 150]] },
      { name: 'Chicken Curry', ago: 45, portions: 6, within: 3, location: 'fridge', finished: true, items: [['Chicken Thigh', 900], ['White Rice (Cooked)', 900], ['Onion', 200]] },
    ];
    const prepPortionOn = new Map(); // ymd -> { recipeId, kcal }
    const prepEntries = [];
    for (const spec of prepSpecs) {
      const ingredients = spec.items.filter(([n]) => food[n]).map(([n, g]) => {
        const f = food[n]; const unit = String(f.serving_unit).toLowerCase();
        return { food: f, quantity: /^(g|ml)/.test(unit) ? g / Number(f.serving_size) : g };
      });
      const sum = (k) => ingredients.reduce((a, i) => a + Number(i.food[k]) * i.quantity, 0);
      const per = (k) => round(sum(k) / spec.portions, 2);
      const recipeId = uuid();
      await db.query(`insert into recipes (id, user_id, name, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g, is_meal_prep)
        values ($1,$2,$3,1,'portion',$4,$5,$6,$7,$8,true)`, [recipeId, U, spec.name, per('calories'), per('protein_g'), per('carbs_g'), per('fat_g'), round(sum('fiber_g') / spec.portions, 2) || 0]);
      await insertMany(db, 'recipe_ingredients', ['recipe_id', 'food_id', 'quantity'], ingredients.map((i) => [recipeId, i.food.id, round(i.quantity, 4)]));
      const prepped = addDays(today, -spec.ago);
      const frozen = spec.location === 'freezer';
      await db.query(`insert into meal_preps (user_id, name, recipe_id, prepped_on, portions, eat_within_days, location, frozen_on, finished_at)
        values ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [U, spec.name, recipeId, ymd(prepped), spec.portions, spec.within, spec.location,
        frozen ? ymd(addDays(prepped, 1)) : null, spec.finished ? at(addDays(prepped, spec.within), 20) : null]);
      // portions eaten (as lunch/breakfast), one per day after cooking
      const eaten = spec.finished ? spec.portions : frozen ? 2 : spec.ago === 0 ? 0 : Math.min(spec.portions - 1, spec.ago);
      for (let k = 0; k < eaten; k++) {
        const d = addDays(prepped, k + (spec.ago === 0 ? 0 : 1));
        if (d >= today || prepPortionOn.has(ymd(d))) continue;
        prepPortionOn.set(ymd(d), { kcal: per('calories') });
        prepEntries.push({ date: d, recipeId });
      }
    }

    // ---------- meals, water, steps, sleep, nutrition logs ----------
    const mealRows = [], waterRows = [], stepRows = [], sleepRows = [], nutritionRows = [];
    const dayKcal = new Map();
    const kcalOf = (name, amount) => {
      const f = food[name]; const unit = String(f.serving_unit).toLowerCase();
      const q = /^(g|ml)/.test(unit) ? amount / Number(f.serving_size) : amount;
      return { f, q, kcal: Number(f.calories) * q };
    };
    for (const d of pastDays) {
      const key = ymd(d);
      if (!chance(0.94)) continue;          // a day with nothing logged
      const goalKcal = target.kcal * between(0.9, 1.08) * (offPlan.get(key) ? between(1.35, 1.7) : 1);
      const day = { kcal: 0, protein: 0, carbs: 0, fat: 0 };
      const prepToday = prepPortionOn.get(key);
      for (const slot of Object.keys(MEALS)) {
        if (!slotId[slot]) continue;
        if (slot === 'Lunch' && prepToday) continue;                  // lunch comes from the prep below
        const template = pick(MEALS[slot]).filter(([n]) => food[n]);
        const slotKcal = goalKcal * SLOT_SHARE[slot] - (slot === 'Lunch' ? 0 : 0);
        const base = template.reduce((a, [n, amt]) => a + kcalOf(n, amt).kcal, 0);
        const scale = slotKcal / base;
        for (const [n, amt] of template) {
          let amount = amt * scale;
          const unit = String(food[n].serving_unit).toLowerCase();
          amount = /^(g|ml)/.test(unit) ? Math.max(5, Math.round(amount / 5) * 5) : Math.max(1, Math.round(amount));
          const { f, q, kcal } = kcalOf(n, amount);
          mealRows.push([U, key, slotId[slot], f.id, null, round(q, 4), at(d, SLOT_HOUR[slot], intBetween(0, 45))]);
          day.kcal += kcal; day.protein += Number(f.protein_g) * q; day.carbs += Number(f.carbs_g) * q; day.fat += Number(f.fat_g) * q;
        }
      }
      // drinks: a morning pot (2-3 cups), sometimes a pod after lunch, now and then a Monster or Pepsi
      const cups = intBetween(2, 3);
      for (let c = 0; c < cups; c++) {
        mealRows.push([U, key, slotId.Drinks, food['Brew pot coffee'].id, null, round(between(2.2, 2.8), 2), at(d, 7 + c, intBetween(0, 50))]);
      }
      if (chance(0.45)) mealRows.push([U, key, slotId.Drinks, food['Pod coffee'].id, null, 1, at(d, 13 + intBetween(0, 2), intBetween(0, 50))]);
      if (food['Monster Energy'] && chance(0.1)) mealRows.push([U, key, slotId.Drinks, food['Monster Energy'].id, null, 5, at(d, 15 + intBetween(0, 3), intBetween(0, 50))]);
      if (food['Pepsi'] && chance(0.2)) mealRows.push([U, key, slotId.Drinks, food['Pepsi'].id, null, 3.3, at(d, 18 + intBetween(0, 2), intBetween(0, 50))]);
      dayKcal.set(key, day.kcal);
      if (HEALTH_LOGS) nutritionRows.push([U, key, round(day.kcal, 0), round(day.protein, 0), round(day.carbs, 0), round(day.fat, 0), 'healthkit']);
    }
    // prep portions as lunch entries, plus their macros in the day's log
    const recipeRows = (await db.query('select id, calories, protein_g, carbs_g, fat_g from recipes where user_id=$1 and is_meal_prep', [U])).rows;
    const recipeById = Object.fromEntries(recipeRows.map((r) => [r.id, r]));
    for (const { date, recipeId } of prepEntries) {
      const key = ymd(date);
      if (!dayKcal.has(key)) continue;
      mealRows.push([U, key, slotId.Lunch, null, recipeId, 1, at(date, 13, 10)]);
      const r = recipeById[recipeId];
      dayKcal.set(key, dayKcal.get(key) + Number(r.calories));
      const log = nutritionRows.find((n) => n[1] === key);
      if (log) { log[2] += Math.round(r.calories); log[3] += Math.round(r.protein_g); log[4] += Math.round(r.carbs_g); log[5] += Math.round(r.fat_g); }
    }
    // the unmatched half of the lunch rule: a prep day with no logged day gets no entry (above)
    const cardioDay = (d) => restWalkFor.has(swiftWeekday(d));
    for (const d of pastDays) {
      const key = ymd(d);
      // water
      const goalMl = between(2800, 4000);
      let total = 0;
      while (total < goalMl) {
        const c = pick(containers);
        waterRows.push([U, key, c.volume_ml, c.id, at(d, intBetween(8, 21), intBetween(0, 59))]);
        total += c.volume_ml;
      }
      // steps + sleep
      if (chance(0.96)) {
        const steps = Math.max(2500, Math.round(target.steps * between(0.6, 1.3) + (cardioDay(d) ? 2500 : 0)));
        stepRows.push([U, key, steps, 'healthkit']);
      }
      if (chance(0.94)) {
        const asleep = Math.round(between(360, 515));
        sleepRows.push([U, key, asleep, asleep + intBetween(15, 45), 'healthkit']);
      }
    }
    await insertMany(db, 'meal_entries', ['user_id', 'date', 'meal_slot_id', 'food_id', 'recipe_id', 'quantity', 'logged_at'], mealRows);
    await insertMany(db, 'water_logs', ['user_id', 'date', 'amount_ml', 'container_id', 'logged_at'], waterRows);
    await insertMany(db, 'step_logs', ['user_id', 'date', 'step_count', 'source'], stepRows);
    await insertMany(db, 'sleep_logs', ['user_id', 'date', 'total_sleep_minutes', 'in_bed_minutes', 'source'], sleepRows);
    if (nutritionRows.length) await insertMany(db, 'nutrition_logs', ['user_id', 'date', 'calories', 'protein_g', 'carbs_g', 'fat_g', 'source'], nutritionRows);

    // ---------- workouts with progressive overload ----------
    const exercisesByDay = new Map();
    dayExercises.forEach((e) => { if (!exercisesByDay.has(e.routine_day_id)) exercisesByDay.set(e.routine_day_id, []); exercisesByDay.get(e.routine_day_id).push(e); });
    const baseWeight = new Map();
    const startDate = pastDays[0];
    const workoutRows = [], setRows = [], weRows = [], noteRows = [];
    let workoutCount = 0;
    for (const d of pastDays) {
      const sched = workoutDayFor.get(swiftWeekday(d));
      if (!sched || !chance(0.9)) continue;
      const wid = uuid(), startedHour = pick([6, 7, 12, 17, 18]);
      const started = new Date(d.getFullYear(), d.getMonth(), d.getDate(), startedHour, intBetween(0, 40));
      const ended = new Date(started.getTime() + intBetween(52, 78) * 60000);
      workoutRows.push([wid, U, started.toISOString(), started.toISOString(), ended.toISOString(), sched.routine_day_id, intBetween(3, 5), intBetween(112, 138)]);
      workoutCount++;
      const block = Math.floor(daysBetween(startDate, d) / 21), deload = Math.floor(daysBetween(startDate, d) / 7) % 5 === 4;
      (exercisesByDay.get(sched.routine_day_id) ?? []).forEach((ex, pos) => {
        if (!baseWeight.has(ex.exercise_id)) baseWeight.set(ex.exercise_id, pick([20, 25, 30, 35, 40, 45, 50, 60, 70, 80]));
        const inc = Number(ex.weight_increment_kg) || 2.5;
        const weight = round(Math.max(inc, baseWeight.get(ex.exercise_id) + block * inc - (deload ? 2 * inc : 0)) / 0.25, 0) * 0.25;
        weRows.push([U, wid, ex.exercise_id, pos]);
        for (let s = 1; s <= ex.target_sets; s++) {
          const high = ex.rep_range_high, low = ex.rep_range_low;
          const reps = Math.max(low - 1, Math.min(high, Math.round(high - (s - 1) * between(0.6, 1.6) - between(0, 2))));
          setRows.push([wid, U, ex.exercise_id, s, reps, weight, false, false]);
        }
        if (chance(0.04)) noteRows.push([U, wid, ex.exercise_id, pick(['Felt strong', 'Shoulder a bit tight', 'Slow tempo today', 'Could have gone heavier'])]);
      });
    }
    await insertMany(db, 'workouts', ['id', 'user_id', 'performed_at', 'started_at', 'ended_at', 'routine_day_id', 'rating', 'avg_heart_rate'], workoutRows);
    await insertMany(db, 'workout_exercises', ['user_id', 'workout_id', 'exercise_id', 'position'], weRows);
    await insertMany(db, 'workout_sets', ['workout_id', 'user_id', 'exercise_id', 'set_index', 'reps', 'weight_kg', 'is_warmup', 'is_drop_set'], setRows);
    if (noteRows.length) await insertMany(db, 'exercise_notes', ['user_id', 'workout_id', 'exercise_id', 'note'], noteRows);

    // ---------- cardio: incline walks on active-rest days + GPS runs ----------
    const cardioRows = [];
    for (const d of pastDays) {
      const sched = restWalkFor.get(swiftWeekday(d));
      if (!sched || !chance(0.85)) continue;
      const type = sched.cardio_type ?? 'incline_treadmill';
      if (type === 'outdoor_run') continue; // runs come from the plan below
      const start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 11, intBetween(0, 50));
      const mins = intBetween(22, 42);
      const before = intBetween(1000, 4000);
      cardioRows.push([uuid(), U, type, start.toISOString(), new Date(start.getTime() + mins * 60000).toISOString(), 0, before, before + mins * intBetween(95, 120), intBetween(112, 138), 'app', null]);
    }
    await insertMany(db, 'cardio_tracking_sessions', ['id', 'user_id', 'cardio_type', 'started_at', 'ended_at', 'paused_seconds', 'steps_before', 'steps_after', 'avg_heart_rate', 'source', 'healthkit_uuid'], cardioRows);

    // ---------- running plan: Wed + Sat, joined at week 1 eight weeks ago, 16 weeks total ----------
    const planStart = mondayOf(addDays(today, -56));
    const planId = uuid();
    await db.query(`insert into running_plans (id, user_id, name, start_date, first_week_number, notes) values ($1,$2,'Base to Half Marathon',$3,1,$4)`,
      [planId, U, ymd(planStart), 'Seeded test plan. Easy, conversational effort.']);
    const plannedRows = [], runCardio = [], routeRows = [];
    for (let w = 0; w < 16; w++) {
      const monday = addDays(planStart, w * 7);
      const light = (w + 1) % 4 === 0;
      const longKm = Math.round((5 + w * 0.75) * (light ? 0.7 : 1));
      const easyKm = Math.round((5 + w * 0.2) * (light ? 0.8 : 1));
      const quality = w >= 6 && w % 2 === 0;
      for (const [offset, type, km, notes] of [
        [2, quality ? 'tempo' : 'easy', quality ? Math.round(easyKm * 0.9) : easyKm, quality ? '10 min easy, tempo, 5 min easy' : 'Easy, conversational effort'],
        [5, 'long', longKm, light ? 'Light week' : 'Long, easy run'],
      ]) {
        const day = addDays(monday, offset);
        plannedRows.push([planId, U, ymd(day), type, km, null, notes]);
        if (day < today && chance(0.88)) {        // Watch-recorded run for that day
          const actualKm = km * between(0.88, 1.12);
          const route = runRoute(actualKm, between(-1, 1));
          const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12 + intBetween(0, 5), intBetween(0, 50));
          const id = uuid();
          runCardio.push([id, U, 'outdoor_run', start.toISOString(), new Date(start.getTime() + route.seconds * 1000).toISOString(), 0, intBetween(142, 164),
            round(route.seconds / 60 * 11, 0), round(route.seconds / 60 * 12.5, 0), round(route.meters, 1), round(between(15, 70), 1), intBetween(190, 235), intBetween(164, 178), true, 'healthkit', `SEED-RUN-${runCardio.length + 1}`]);
          routeRows.push([id, U, JSON.stringify(route.pts)]);
        }
      }
    }
    await insertMany(db, 'planned_runs', ['running_plan_id', 'user_id', 'date', 'run_type', 'target_distance_km', 'target_duration_min', 'notes'], plannedRows);
    await insertMany(db, 'cardio_tracking_sessions', ['id', 'user_id', 'cardio_type', 'started_at', 'ended_at', 'paused_seconds', 'avg_heart_rate', 'active_calories', 'total_calories', 'distance_meters', 'elevation_gain_m', 'avg_power_w', 'avg_cadence_spm', 'has_route', 'source', 'healthkit_uuid'], runCardio);
    await insertMany(db, 'run_routes', ['session_id', 'user_id', 'points'], routeRows);

    // ---------- weekly check-ins, measurements, TDEE estimates ----------
    const weekly = [], measures = [], tdee = [];
    let weekNo = 0;
    for (const d of pastDays) {
      if (swiftWeekday(d) !== checkinWeekday) continue;
      weekNo++;
      const kg = weightOn.get(ymd(d)) ?? 72;
      const adherence = intBetween(3, 5);
      weekly.push([U, target.id, ymd(d), weekNo, intBetween(3, 5), kg, intBetween(2, 5), intBetween(1, 4), intBetween(1, 4), pick(['Work', 'Travel', 'Family', 'Sleep']),
        pick(['Hit every session', 'Stayed on plan at the weekend', 'Hit a deadload PR', 'Kept steps up']), pick(['Good week', 'A bit flat', 'Motivated']),
        adherence, adherence, intBetween(3, 5), intBetween(3, 5), pick(['A busy weekend', 'Nothing planned', 'A night out']),
        intBetween(3, 5), pick(['Mostly on plan', 'Over on Saturday']), intBetween(3, 5), pick(['Strong sessions', 'Missed one workout'])]);
      measures.push([U, ymd(d), round(between(80, 84), 1), round(between(33, 35), 1), round(between(33, 35), 1), 'weekly_checkin']);
      const logged = pastDays.filter((x) => x <= d && x > addDays(d, -14) && dayKcal.has(ymd(x)));
      if (logged.length >= 6) {
        const avg = logged.reduce((a, x) => a + dayKcal.get(ymd(x)), 0) / logged.length;
        const rate = round(between(-0.55, -0.1), 2);
        const est = Math.round(avg - (rate * 7700) / 7);
        tdee.push([U, ymd(d), 14, logged.length, Math.round(avg), rate, est, Math.round(target.kcal), Math.round(est - 450), 'accepted']);
      }
    }
    await insertMany(db, 'weekly_checkins', ['user_id', 'goal_id', 'checkin_date', 'week_number', 'overall_rating_7d', 'weight_kg', 'energy_level', 'soreness_level', 'stress_level', 'stress_reason', 'biggest_win', 'mood_notes',
      'overall_adherence', 'training_adherence', 'nutrition_adherence', 'discipline_level', 'upcoming_distractions', 'nutrition_rating', 'nutrition_notes', 'training_rating', 'training_notes'], weekly);
    await insertMany(db, 'body_measurements', ['user_id', 'measured_at', 'waist_cm', 'left_bicep_cm', 'right_bicep_cm', 'source'], measures);
    if (tdee.length) {
      tdee[tdee.length - 1][9] = 'pending';
      await insertMany(db, 'tdee_estimates', ['user_id', 'estimated_at', 'window_days', 'logged_days_in_window', 'avg_daily_calories', 'trend_weight_change_kg_per_week', 'estimated_tdee', 'current_calorie_target', 'recommended_calorie_target', 'status'], tdee);
    }

    // ---------- planned treats: a few past, one most weeks ahead ----------
    const treats = [];
    const treatNames = [['Birthday cake', 900], ['Pizza night', 1100], ['Ice cream', 500], ['Burger and fries', 1000], ['Takeaway curry', 950], ['Chocolate bar', 350]];
    for (const d of [...pastDays.filter((_, i) => i % 23 === 7), ...futureDays.filter((x) => swiftWeekday(x) === 7)]) {
      const [label, kcal] = pick(treatNames);
      const protein = Math.round(kcal * 0.04 / 4 * 4) ; // ~16% of energy as protein
      const rest = MacroRest(kcal, protein);
      treats.push([U, ymd(d), slotId.Dinner ?? null, label, kcal, protein, rest.carbs, rest.fat]);
    }
    await insertMany(db, 'planned_treats', ['user_id', 'date', 'meal_slot_id', 'label', 'extra_calories', 'extra_protein_g', 'extra_carbs_g', 'extra_fat_g'], treats);

    await db.query('commit');
    console.log([
      `meals ${mealRows.length}`, `water ${waterRows.length}`, `weigh-ins ${weightRows.length}`, `daily check-ins ${checkinRows.length}`,
      `weekly check-ins ${weekly.length}`, `workouts ${workoutCount} (${setRows.length} sets)`, `walks ${cardioRows.length}`, `runs ${runCardio.length}`,
      `planned runs ${plannedRows.length}`, `steps ${stepRows.length}`, `sleep ${sleepRows.length}`, `tdee ${tdee.length}`, `treats ${treats.length}`, `meal-prep batches ${prepSpecs.length}`,
    ].join(' | '));
  } catch (e) {
    await db.query('rollback');
    throw e;
  } finally {
    await db.end();
  }
}

// Carbs/fat that cover what protein doesn't, 60/40 by energy - the same split
// the app's MacroEnergy.fillRemainder uses, so seeded treats pass its check.
function MacroRest(kcal, protein) {
  const left = Math.max(0, kcal - protein * 4);
  return { carbs: Math.round((left * 0.6) / 4), fat: Math.round((left * 0.4) / 9) };
}

main().catch((e) => { console.error('Seed failed:', e.message); process.exit(1); });
