import Foundation
import Supabase

struct FoodGroupRepository {
    let client = SupabaseService.shared.client
    private let foodRepository = FoodRepository()

    private struct NewGroup: Encodable {
        let user_id: UUID
        let name: String
    }

    private struct NewMember: Encodable {
        let group_id: UUID
        let food_id: UUID
        let user_id: UUID
    }

    private struct RenameUpdate: Encodable {
        let name: String
    }

    private struct GroupRef: Encodable {
        let group_id: UUID
    }

    func fetchGroups() async throws -> [FoodGroup] {
        try await client
            .from("food_groups")
            .select()
            .order("name")
            .execute()
            .value
    }

    func fetchMembers() async throws -> [FoodGroupMember] {
        try await client
            .from("food_group_members")
            .select()
            .execute()
            .value
    }

    /// Every group with its foods resolved, alphabetical - the Brand
    /// Compare list. One round trip each for groups, memberships and foods
    /// rather than one per group.
    func fetchSummaries() async throws -> [FoodGroupSummary] {
        async let groupsResult = fetchGroups()
        async let membersResult = fetchMembers()
        let (groups, members) = try await (groupsResult, membersResult)
        let foods = try await foodRepository.fetchByIds(Array(Set(members.map(\.foodId))))
        let foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        return groups.map { group in
            let groupFoods = members
                .filter { $0.groupId == group.id }
                .compactMap { foodsById[$0.foodId] }
                .sorted { $0.displayName < $1.displayName }
            return FoodGroupSummary(group: group, foods: groupFoods)
        }
    }

    /// Which group each of these foods is in (foods in no group are absent) -
    /// lets a prep's ingredient rows show a "brands" affordance without a
    /// query per row.
    func groupIds(forFoodIds foodIds: [UUID]) async throws -> [UUID: UUID] {
        guard !foodIds.isEmpty else { return [:] }
        let members: [FoodGroupMember] = try await client
            .from("food_group_members")
            .select()
            .in("food_id", values: foodIds)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: members.map { ($0.foodId, $0.groupId) })
    }

    /// The other brands this user has linked to `food`, if any.
    func linkedFoods(for food: Food) async throws -> [Food] {
        guard let groupId = try await groupIds(forFoodIds: [food.id])[food.id] else { return [] }
        let members: [FoodGroupMember] = try await client
            .from("food_group_members")
            .select()
            .eq("group_id", value: groupId)
            .execute()
            .value
        let otherIds = members.map(\.foodId).filter { $0 != food.id }
        return try await foodRepository.fetchByIds(otherIds)
    }

    @discardableResult
    func createGroup(name: String) async throws -> FoodGroup {
        let userId = try await client.auth.session.user.id
        let groups: [FoodGroup] = try await client
            .from("food_groups")
            .insert(NewGroup(user_id: userId, name: name))
            .select()
            .execute()
            .value
        guard let group = groups.first else { throw RepositoryError.insertFailed }
        return group
    }

    func rename(id: UUID, name: String) async throws {
        try await client
            .from("food_groups")
            .update(RenameUpdate(name: name))
            .eq("id", value: id)
            .execute()
    }

    func deleteGroup(id: UUID) async throws {
        try await client
            .from("food_groups")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func addMember(groupId: UUID, foodId: UUID) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("food_group_members")
            .upsert(NewMember(group_id: groupId, food_id: foodId, user_id: userId), onConflict: "group_id,food_id")
            .execute()
    }

    func removeMember(groupId: UUID, foodId: UUID) async throws {
        try await client
            .from("food_group_members")
            .delete()
            .eq("group_id", value: groupId)
            .eq("food_id", value: foodId)
            .execute()
    }

    /// "These two are the same product." Whichever of the two is already in
    /// a group pulls the other in; two foods in different groups merge
    /// into the first's group (and the emptied one is deleted); two
    /// ungrouped foods start a new group named after `first`'s plain name
    /// (no brand - the group is the product, not one of its brands).
    /// Idempotent when they're already together.
    @discardableResult
    func link(_ first: Food, _ second: Food) async throws -> FoodGroup? {
        guard first.id != second.id else { return nil }
        let existing = try await groupIds(forFoodIds: [first.id, second.id])
        let groups = try await fetchGroups()

        switch (existing[first.id], existing[second.id]) {
        case let (firstGroup?, secondGroup?) where firstGroup == secondGroup:
            return groups.first { $0.id == firstGroup }
        case let (firstGroup?, secondGroup?):
            try await merge(secondGroup, into: firstGroup)
            return groups.first { $0.id == firstGroup }
        case let (firstGroup?, nil):
            try await addMember(groupId: firstGroup, foodId: second.id)
            return groups.first { $0.id == firstGroup }
        case let (nil, secondGroup?):
            try await addMember(groupId: secondGroup, foodId: first.id)
            return groups.first { $0.id == secondGroup }
        case (nil, nil):
            let group = try await createGroup(name: first.name)
            try await addMember(groupId: group.id, foodId: first.id)
            try await addMember(groupId: group.id, foodId: second.id)
            return group
        }
    }

    private func merge(_ source: UUID, into target: UUID) async throws {
        try await client
            .from("food_group_members")
            .update(GroupRef(group_id: target))
            .eq("group_id", value: source)
            .execute()
        try await deleteGroup(id: source)
    }
}
