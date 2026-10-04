import Foundation
import Supabase

struct ProgressPhotoRepository {
    let client = SupabaseService.shared.client
    private let bucket = "progress-photos"

    private struct NewProgressPhoto: Encodable {
        let user_id: UUID
        let taken_at: String
        let storage_path: String
        let goal_id: UUID?
        let weekly_checkin_id: UUID?
    }

    func fetchRecent(limit: Int = 60) async throws -> [ProgressPhoto] {
        try await client
            .from("progress_photos")
            .select()
            .order("taken_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Photos attached to a specific weekly check-in - used by the
    /// check-in history/detail screen under Settings.
    func fetchForWeeklyCheckin(_ weeklyCheckinId: UUID) async throws -> [ProgressPhoto] {
        try await client
            .from("progress_photos")
            .select()
            .eq("weekly_checkin_id", value: weeklyCheckinId)
            .order("taken_at", ascending: false)
            .execute()
            .value
    }

    /// Uploads to Storage first, then records the DB row - so a row never
    /// points at a missing object (the reverse failure mode, an orphaned
    /// object with no row, is low-stakes and not worth a compensating step).
    @discardableResult
    func upload(imageData: Data, takenAt: Date, goalId: UUID?, weeklyCheckinId: UUID? = nil) async throws -> ProgressPhoto {
        let userId = try await client.auth.session.user.id
        let path = "\(userId)/\(UUID().uuidString).jpg"

        try await client.storage.from(bucket).upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg")
        )

        let inserted: [ProgressPhoto] = try await client
            .from("progress_photos")
            .insert(NewProgressPhoto(
                user_id: userId,
                taken_at: DateFormatting.isoDate(takenAt),
                storage_path: path,
                goal_id: goalId,
                weekly_checkin_id: weeklyCheckinId
            ))
            .select()
            .execute()
            .value
        guard let photo = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return photo
    }

    /// Removes every photo file this user has uploaded - done before deleting
    /// the account, since stored files can't be removed from the database side.
    func deleteAllFiles() async throws {
        let photos = try await fetchRecent(limit: 5000)
        let paths = photos.map(\.storagePath)
        guard !paths.isEmpty else { return }
        // In batches, so one request never carries thousands of paths.
        for start in stride(from: 0, to: paths.count, by: 100) {
            _ = try await client.storage.from(bucket).remove(paths: Array(paths[start..<min(start + 100, paths.count)]))
        }
    }

    func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: expiresIn)
    }
}
