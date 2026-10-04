import SwiftUI
import Supabase

/// Take a copy of everything the account holds, or delete the account.
struct AccountDataView: View {
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share the Export", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        Task { await export() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Label("Export My Data", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isExporting)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("A JSON file with all of your logs, plans and settings. Progress photos aren't in it - they stay in the app until you save them.")
            }
            .listRowBackground(AppRowBackground())

            Section {
                Button("Delete My Account", role: .destructive) { showingDelete = true }
            } header: {
                Text("Delete")
            } footer: {
                Text("Removes your account and everything in it from the server - logs, plans, photos and settings. It can't be undone. Export first if you want a copy.")
            }
            .listRowBackground(AppRowBackground())

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDelete) {
            DeleteAccountSheet()
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            // Anything not sent yet goes first, so the export is complete.
            await LocalData.flushAll()
            let response = try await SupabaseService.shared.client.rpc("export_my_data").execute()
            let name = "FitnessTracker-export-\(DateFormatting.isoDate(Date())).json"
            let url = FileManager.default.temporaryDirectory.appending(path: name)
            try response.data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Deleting needs the word typed, so it can't happen by a stray tap.
private struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your account and all of its data. There's no way to get it back.")
                    TextField("Type DELETE to confirm", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .listRowBackground(AppRowBackground())
                Section {
                    Button("Delete Everything", role: .destructive) { Task { await delete() } }
                        .disabled(typed != "DELETE" || isDeleting)
                }
                .listRowBackground(AppRowBackground())
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                        .listRowBackground(Color.clear)
                }
            }
            .appScreen()
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.appToolbarTint()
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isDeleting)
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await ProgressPhotoRepository().deleteAllFiles()
            try await SupabaseService.shared.client.rpc("delete_my_account").execute()
            // The login no longer exists; clear this phone and go back to sign-in.
            try? await SupabaseService.shared.signOut()
            LocalData.wipe()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
