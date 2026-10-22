import SwiftUI

struct MeetingProfileSettingsView: View {
    @Environment(MeetingProfileSettings.self) private var meetingProfileSettings
    @State private var selectedProfileID: String?
    @State private var showingNewProfile = false
    @State private var newName = ""
    @State private var newGuidance = ""
    @State private var newInsightPace: ListeningCadence = .thirtySeconds
    @State private var newTechnicalVocabulary = ""
    @State private var addError: String?

    var body: some View {
        HStack(spacing: 0) {
            profileList

            Divider()

            VStack(spacing: 0) {
                if showingNewProfile || selectedProfile == nil {
                    newProfileForm
                } else if let selectedProfile {
                    MeetingProfileEditorRow(profile: selectedProfile)
                        .id(selectedProfile.id)
                }
            }
        }
        .onAppear {
            selectInitialProfile()
        }
        .onChange(of: selectedProfileID) { _, newValue in
            if newValue != nil {
                showingNewProfile = false
            }
        }
        .onChange(of: meetingProfileSettings.profiles) { _, profiles in
            guard let selectedProfileID else {
                showingNewProfile = profiles.isEmpty
                return
            }
            if selectedProfileID == MeetingProfile.fallback.id {
                return
            }
            guard profiles.contains(where: { $0.id == selectedProfileID }) else {
                self.selectedProfileID = profiles.first?.id
                showingNewProfile = profiles.isEmpty
                return
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 500, idealHeight: 560)
    }

    private var selectedProfile: MeetingProfile? {
        guard let selectedProfileID else { return nil }
        if selectedProfileID == MeetingProfile.fallback.id {
            return meetingProfileSettings.defaultProfile
        }
        return meetingProfileSettings.profiles.first(where: { $0.id == selectedProfileID })
    }

    private var profileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meeting profiles")
                    .font(.headline)
                Spacer()
                Button {
                    selectedProfileID = nil
                    showingNewProfile = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Create a custom meeting profile")
                .accessibilityLabel("New profile")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List(selection: $selectedProfileID) {
                Section("Default") {
                    Label(meetingProfileSettings.defaultProfile.name, systemImage: "checkmark.circle")
                        .tag(MeetingProfile.fallback.id)
                }

                Section("Custom") {
                    if meetingProfileSettings.profiles.isEmpty {
                        Text("No custom profiles yet")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(meetingProfileSettings.profiles) { profile in
                            Label(profile.name, systemImage: "person.crop.circle")
                                .tag(profile.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 250)
    }

    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A profile is saved on this Mac and applied to the next listening session.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ProfileField(title: "Name") {
                TextField("e.g. Customer support", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }

            ProfileField(title: "Meeting guidance") {
                ProfileTextEditor(
                    text: $newGuidance,
                    placeholder: "Describe what Rio should prioritize in this meeting.",
                    accessibilityLabel: "New profile guidance"
                )
            }

            ProfileField(title: "Insight pace") {
                ListeningCadencePicker(selection: $newInsightPace)
            }

            ProfileField(title: "Technical vocabulary (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    ProfileTextEditor(
                        text: $newTechnicalVocabulary,
                        placeholder: "e.g. SwiftUI, AVAudioEngine, CFErrorDomain",
                        accessibilityLabel: "New profile technical vocabulary"
                    )
                    HStack {
                        Text("Separate terms with commas or new lines. Terms only, not meeting notes.")
                        Spacer()
                        Text("\(newTechnicalVocabulary.count)/\(TranscriptionVocabularyConfiguration.maximumPromptLength)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let addError {
                    Text(addError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Add Profile") { addProfile() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        MeetingProfile.custom(
                            name: newName,
                            guidance: newGuidance,
                            insightPace: newInsightPace,
                            technicalVocabulary: newTechnicalVocabulary
                        ) == nil
                    )
            }
        }
        .padding(20)
    }

    private func selectInitialProfile() {
        guard selectedProfileID == nil else { return }
        selectedProfileID = MeetingProfile.fallback.id
    }

    private func addProfile() {
        guard let profile = meetingProfileSettings.addCustomProfile(
            name: newName,
            guidance: newGuidance,
            insightPace: newInsightPace,
            technicalVocabulary: newTechnicalVocabulary
        ) else {
            addError = "Use a nonempty name and guidance within the field limits."
            return
        }

        newName = ""
        newGuidance = ""
        newInsightPace = .thirtySeconds
        newTechnicalVocabulary = ""
        addError = nil
        selectedProfileID = profile.id
        showingNewProfile = false
    }
}

private struct MeetingProfileEditorRow: View {
    let profile: MeetingProfile

    @Environment(MeetingProfileSettings.self) private var meetingProfileSettings
    @State private var name: String
    @State private var guidance: String
    @State private var insightPace: ListeningCadence
    @State private var technicalVocabulary: String
    @State private var saveError: String?
    @State private var isConfirmingDeletion = false

    init(profile: MeetingProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _guidance = State(initialValue: profile.guidance)
        _insightPace = State(initialValue: profile.insightPace)
        _technicalVocabulary = State(initialValue: profile.technicalVocabulary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileField(title: "Name") {
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            ProfileField(title: "Meeting guidance") {
                ProfileTextEditor(
                    text: $guidance,
                    placeholder: "Describe what Rio should prioritize in this meeting.",
                    accessibilityLabel: "Profile guidance"
                )
            }

            ProfileField(title: "Insight pace") {
                ListeningCadencePicker(selection: $insightPace)
            }

            ProfileField(title: "Technical vocabulary (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    ProfileTextEditor(
                        text: $technicalVocabulary,
                        placeholder: "Product names, acronyms, versions, or error-code prefixes",
                        accessibilityLabel: "Profile technical vocabulary"
                    )
                    HStack {
                        Text("Use terms only, not meeting notes.")
                        Spacer()
                        Text("\(technicalVocabulary.count)/\(TranscriptionVocabularyConfiguration.maximumPromptLength)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let saveError {
                    Text(saveError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
                if !profile.isFallback {
                    Button("Delete", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                    .confirmationDialog(
                        "Delete “\(profile.name)”?",
                        isPresented: $isConfirmingDeletion,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Profile", role: .destructive) {
                            meetingProfileSettings.deleteCustomProfile(id: profile.id)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes the profile from this Mac and can’t be undone.")
                    }
                }
                Button("Save Changes", action: saveProfile)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || MeetingProfile.custom(
                        name: name,
                        guidance: guidance,
                        insightPace: insightPace,
                        technicalVocabulary: technicalVocabulary
                    ) == nil)
            }
        }
        .padding(20)
    }

    private func saveProfile() {
        let didSave = if profile.isFallback {
            meetingProfileSettings.updateDefaultProfile(
                name: name,
                guidance: guidance,
                insightPace: insightPace,
                technicalVocabulary: technicalVocabulary
            )
        } else {
            meetingProfileSettings.updateCustomProfile(
                id: profile.id,
                name: name,
                guidance: guidance,
                insightPace: insightPace,
                technicalVocabulary: technicalVocabulary
            )
        }

        guard didSave else {
            saveError = "Use a nonempty name and guidance within the field limits."
            return
        }
        saveError = nil
    }

    private var hasChanges: Bool {
        name != profile.name
            || guidance != profile.guidance
            || insightPace != profile.insightPace
            || technicalVocabulary != profile.technicalVocabulary
    }

}

private struct ProfileField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
            content
        }
    }
}

private struct ListeningCadencePicker: View {
    @Binding var selection: ListeningCadence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Update insights every", selection: $selection) {
                ForEach(ListeningCadence.allCases) { cadence in
                    Text(cadence.shortTitle)
                        .tag(cadence)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Update insights every")
            .accessibilityValue(selection.title)

            Text(selection.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...3)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(accessibilityLabel)
    }
}
