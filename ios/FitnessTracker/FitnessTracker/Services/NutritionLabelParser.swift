import Foundation

/// What OCR could pull off a nutrition facts panel - every field optional,
/// since a real scan can miss one (motion blur, a torn label, glare).
/// Values are read exactly as printed, which on an EU label (Tesco/Aldi
/// Ireland - see `docs/nutrition-label-scan-brief.md`) is almost always
/// per 100g/100ml, so the food this becomes is saved with a 100g/100ml
/// serving to match rather than silently converting to something else.
struct ParsedNutritionLabel {
    var caloriesKcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    /// Sodium in mg - read directly from a "Sodium 120 mg" line, or worked
    /// out from a "Salt 0.3 g" one (sodium = salt x 400 mg per g).
    var sodiumMg: Double?
    /// The label's own serving size, in `servingUnit` - e.g. 100 for a
    /// "per 100g" EU panel, or 32 for a "Serving Size 1 Scoop (32g)" US
    /// one. Only ever set to a size that actually matches what the macro
    /// values above were read from - see `NutritionLabelParser`'s two
    /// cases for how that's decided.
    var servingSize: Double?
    var servingUnit: String?

    /// Enough to bother showing a confirm screen for - calories or at
    /// least one macro, so a near-empty read doesn't masquerade as progress.
    var hasAnything: Bool {
        caloriesKcal != nil || proteinG != nil || carbsG != nil || fatG != nil || fiberG != nil
    }

    /// Live OCR runs across many frames - each new frame's read only fills
    /// in whatever this one hasn't already found, so a later, worse frame
    /// (bad angle, glare) can never overwrite an already-good value with a
    /// wrong one.
    mutating func merge(_ other: ParsedNutritionLabel) {
        caloriesKcal = caloriesKcal ?? other.caloriesKcal
        proteinG = proteinG ?? other.proteinG
        carbsG = carbsG ?? other.carbsG
        fatG = fatG ?? other.fatG
        fiberG = fiberG ?? other.fiberG
        sodiumMg = sodiumMg ?? other.sodiumMg
        servingSize = servingSize ?? other.servingSize
        servingUnit = servingUnit ?? other.servingUnit
    }
}

/// Regex-based read of a nutrition facts panel's recognized text lines -
/// tolerant of both EU labels (Energy in kJ *and* kcal, Fat, Carbohydrate,
/// Fibre, Protein) and US ones (Calories, Total Fat, Total Carbohydrate,
/// Dietary Fiber, Protein) through flexible keyword alternations rather
/// than two fully separate parsers - "Energy" vs "Calories" and "Fibre"
/// vs "Fiber" are the only real wording differences among the fields read
/// here, so one tolerant pass covers both formats. See the brief's own
/// Section 2 for the fuller format comparison this is built against.
enum NutritionLabelParser {
    static func parse(_ recognizedLines: [String]) -> ParsedNutritionLabel {
        var result = ParsedNutritionLabel()
        let wholeText = recognizedLines.joined(separator: "\n")

        // A number right before "kcal" is distinctive enough on its own -
        // nothing else on a food package pairs a number with that unit -
        // so this doesn't need to first find "Energy" and look nearby,
        // which would miss cases where OCR splits the label and number
        // onto different lines.
        result.caloriesKcal = firstMatch(#"(\d+(?:[.,]\d+)?)\s*k\s?cal"#, in: wholeText)
            // US labels print the bare number ("Calories 200", no unit) -
            // only reached when the EU-style kcal match above finds
            // nothing, and excludes the legacy "Calories from Fat 90"
            // sub-line some older US labels still have, which isn't the
            // total.
            ?? firstFieldValue(keyword: #"calories"#, excluding: #"from"#, unitPattern: #"(\d+(?:[.,]\d+)?)"#, in: recognizedLines)

        result.fatG = firstFieldValue(keyword: #"fat"#, excluding: #"satur"#, unitPattern: gramsPattern, in: recognizedLines)
        result.carbsG = firstFieldValue(keyword: #"carb"#, excluding: #"sugar"#, unitPattern: gramsPattern, in: recognizedLines)
        result.fiberG = firstFieldValue(keyword: #"fib(re|er)"#, excluding: nil, unitPattern: gramsPattern, in: recognizedLines)
        result.proteinG = firstFieldValue(keyword: #"protein"#, excluding: nil, unitPattern: gramsPattern, in: recognizedLines)
        result.sodiumMg = firstFieldValue(keyword: #"sodium"#, excluding: nil, unitPattern: #"(\d+(?:[.,]\d+)?)\s*mg\b"#, in: recognizedLines)
            ?? firstFieldValue(keyword: #"salt"#, excluding: nil, unitPattern: gramsPattern, in: recognizedLines).map { $0 * 400 }

        if let per100Unit = firstCapturedUnit(#"per\s*100\s*(g|ml)"#, in: wholeText) {
            // EU-style two-column label ("per 100g" *and* "per serving") -
            // every macro above was read as the *first* number on its
            // field's line, which on this style is the per-100g/ml
            // column, not the second "per serving" one - so 100 is the
            // size that actually matches those values, regardless of
            // what a per-serving column separately says.
            result.servingSize = 100
            result.servingUnit = per100Unit
        } else if let (size, unit) = firstServingSizeAndUnit(in: recognizedLines) {
            // No "per 100" marker found - a single-column US/supplement
            // label, where the macros read above correspond directly to
            // the one serving printed ("Serving Size 1 Scoop (32g)" or
            // "per serving (30g)").
            result.servingSize = size
            result.servingUnit = unit
        }

        return result
    }

    private static let gramsPattern = #"(\d+(?:[.,]\d+)?)\s*g\b"#

    private static func firstMatch(_ pattern: String, in text: String, from startIndex: String.Index? = nil) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let searchRange = NSRange((startIndex ?? text.startIndex)..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: searchRange),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Double(text[numberRange].replacingOccurrences(of: ",", with: "."))
    }

    /// Scans line by line for one containing `keyword` (and not
    /// `excluding`, when given - e.g. skipping "of which saturates" when
    /// looking for the top-level "Fat" line), pulling the first
    /// `unitPattern` value found *after* the keyword on that same line -
    /// not just anywhere on the line, so a line where an unrelated number
    /// happens to precede the keyword (e.g. a merged "Serving Size 32g
    /// Calories 130" row) can't grab the wrong one. Falls back to the very
    /// start of the next line if nothing follows the keyword on this one -
    /// the common case when OCR wraps the label and its number onto
    /// separate lines.
    private static func firstFieldValue(keyword: String, excluding: String?, unitPattern: String, in lines: [String]) -> Double? {
        guard let keywordRegex = try? NSRegularExpression(pattern: keyword, options: [.caseInsensitive]) else { return nil }
        let excludingRegex = excluding.flatMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

        for (index, line) in lines.enumerated() {
            let fullRange = NSRange(line.startIndex..., in: line)
            guard let keywordMatch = keywordRegex.firstMatch(in: line, options: [], range: fullRange) else { continue }
            if let excludingRegex, excludingRegex.firstMatch(in: line, options: [], range: fullRange) != nil { continue }

            if let matchRange = Range(keywordMatch.range, in: line),
               let value = firstMatch(unitPattern, in: line, from: matchRange.upperBound) {
                return value
            }
            if index + 1 < lines.count, let value = firstMatch(unitPattern, in: lines[index + 1]) {
                return value
            }
        }
        return nil
    }

    /// Just the captured unit (lowercased) from a pattern's first capture
    /// group, e.g. matching `per\s*100\s*(g|ml)` to tell a "per 100g"
    /// panel from a "per 100ml" one.
    private static func firstCapturedUnit(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let unitRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[unitRange].lowercased()
    }

    /// Finds a "Serving Size" or "per serving" line and reads the first
    /// number+unit *after* that keyword - same position-aware approach as
    /// `firstFieldValue`, so "Serving Size 1 Scoop (32g)" correctly skips
    /// past the "1" (not followed by g/ml) to land on "32g" rather than
    /// misreading the scoop count as the size.
    private static func firstServingSizeAndUnit(in lines: [String]) -> (Double, String)? {
        guard let keywordRegex = try? NSRegularExpression(pattern: #"serving\s*size|per\s*serving"#, options: [.caseInsensitive]) else { return nil }
        let valuePattern = #"(\d+(?:[.,]\d+)?)\s*(g|ml)"#

        for (index, line) in lines.enumerated() {
            let fullRange = NSRange(line.startIndex..., in: line)
            guard let keywordMatch = keywordRegex.firstMatch(in: line, options: [], range: fullRange) else { continue }

            if let matchRange = Range(keywordMatch.range, in: line),
               let result = firstValueAndUnit(valuePattern, in: line, from: matchRange.upperBound) {
                return result
            }
            if index + 1 < lines.count, let result = firstValueAndUnit(valuePattern, in: lines[index + 1]) {
                return result
            }
        }
        return nil
    }

    private static func firstValueAndUnit(_ pattern: String, in text: String, from startIndex: String.Index? = nil) -> (Double, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let searchRange = NSRange((startIndex ?? text.startIndex)..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: searchRange),
              match.numberOfRanges > 2,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return (value, text[unitRange].lowercased())
    }
}
