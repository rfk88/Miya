//
//  EditProfileView.swift
//  Miya Health
//
//  Profile editor for fields the user can update post-onboarding.
//  WHO risk factors (blood pressure, diabetes, prior events, family history)
//  are set during onboarding and are not editable here — they feed into an
//  automated risk recalculation that runs on every save.
//
//  Email and password changes are handled in dedicated sheets:
//  ChangeEmailView and ChangePasswordView.
//

import SwiftUI
import Combine
import PhotosUI
import Supabase

@MainActor
final class EditProfileViewModel: ObservableObject {
    /// Display placeholder when no DOB from server; never use Date() so we don't default to "today" (BUG-032).
    static let dobPlaceholder: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    enum SaveState {
        case idle
        case loading
        case success(String)
        case failure(String)
    }

    // MARK: - Profile fields (user_profiles)
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var gender: String = ""
    @Published var dateOfBirth: Date = EditProfileViewModel.dobPlaceholder
    @Published var hasDateOfBirth: Bool = false
    @Published var ethnicity: String = ""
    @Published var smokingStatus: String = ""
    @Published var heightCm: String = ""
    @Published var weightKg: String = ""
    @Published var nutritionQuality: Int = 3

    // Notifications (user_profiles)
    @Published var notifyInApp: Bool = true
    @Published var notifyPush: Bool = false
    @Published var notifyEmail: Bool = false

    @Published var avatarURL: String? = nil

    // MARK: - UI state
    @Published var isLoading: Bool = false
    @Published var isUploadingAvatar: Bool = false
    @Published var avatarErrorMessage: String? = nil
    @Published var saveState: SaveState = .idle
    @Published var hasUnsavedChanges: Bool = false

    private var initialSnapshot: Snapshot? = nil

    private struct Snapshot: Equatable {
        let firstName: String
        let lastName: String
        let gender: String
        let hasDob: Bool
        let dob: Date
        let ethnicity: String
        let smoking: String
        let heightCm: String
        let weightKg: String
        let nutritionQuality: Int
        let notifyInApp: Bool
        let notifyPush: Bool
        let notifyEmail: Bool
    }

    private func computeSnapshot() -> Snapshot {
        Snapshot(
            firstName: firstName,
            lastName: lastName,
            gender: gender,
            hasDob: hasDateOfBirth,
            dob: dateOfBirth,
            ethnicity: ethnicity,
            smoking: smokingStatus,
            heightCm: heightCm,
            weightKg: weightKg,
            nutritionQuality: nutritionQuality,
            notifyInApp: notifyInApp,
            notifyPush: notifyPush,
            notifyEmail: notifyEmail
        )
    }

    private func updateDirtyState() {
        guard let initialSnapshot else {
            hasUnsavedChanges = false
            return
        }
        hasUnsavedChanges = computeSnapshot() != initialSnapshot
    }

    func bindDirtyTracking() {
        initialSnapshot = computeSnapshot()
        updateDirtyState()
    }

    func fieldDidChange() {
        updateDirtyState()
        if case .success = saveState { saveState = .idle }
        if case .failure = saveState { saveState = .idle }
    }
}

private struct ImageForCropEdit: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct EditProfileView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = EditProfileViewModel()

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var imageForCrop: ImageForCropEdit? = nil
    @State private var isPhotoPickerPresented: Bool = false

    private let genders = ["Male", "Female"]
    private let ethnicities = ["White", "Black", "Asian", "Hispanic", "Other"]
    private let smokingStatuses = ["Never", "Former", "Current"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.miyaBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerCard
                        nameCard
                        aboutYouCard
                        bodyCard
                        lifestyleCard
                        notificationsCard
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .disabled(vm.isLoading)

                // Blocks interaction and signals unavailability while the
                // background network refresh is in progress.
                if vm.isLoading {
                    Color.black.opacity(0.04)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isLoading ? "Saving…" : "Save") {
                        Task { await saveAll() }
                    }
                    .disabled(vm.isLoading || !vm.hasUnsavedChanges)
                }
            }
            .task { await load() }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .sheet(item: $imageForCrop) { item in
                AvatarCropView(image: item.image, onCancel: {
                    imageForCrop = nil
                }, onSave: { data in
                    imageForCrop = nil
                    Task { await uploadAvatar(data: data) }
                })
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    guard let item = newItem else { return }
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            await MainActor.run {
                                isPhotoPickerPresented = false
                                imageForCrop = ImageForCropEdit(image: img)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            vm.avatarErrorMessage = "Couldn't load that photo. Please try another."
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        Card {
            HStack(spacing: 16) {
                // Tappable avatar with upload overlay
                Button {
                    isPhotoPickerPresented = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(
                            imageURL: vm.avatarURL,
                            initials: initials(from: "\(vm.firstName) \(vm.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)),
                            diameter: 64,
                            backgroundColor: Color.miyaEmerald.opacity(0.12),
                            foregroundColor: .miyaEmerald,
                            font: .system(size: 22, weight: .bold)
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            vm.isUploadingAvatar
                                ? Circle().fill(Color.black.opacity(0.4)).frame(width: 64, height: 64)
                                : nil
                        )

                        if vm.isUploadingAvatar {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Circle()
                                .fill(Color.miyaEmerald)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.isUploadingAvatar)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Button {
                        isPhotoPickerPresented = true
                    } label: {
                        Text(vm.avatarURL == nil ? "Add profile photo" : "Change photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.miyaEmerald)
                    }
                    .disabled(vm.isUploadingAvatar)
                }

                Spacer()
                if vm.isLoading {
                    ProgressView().progressViewStyle(.circular)
                }
            }

            if let errorMessage = vm.avatarErrorMessage {
                InlineBanner(kind: .error, text: errorMessage)
            }
            if case .success(let message) = vm.saveState {
                InlineBanner(kind: .success, text: message)
            }
            if case .failure(let message) = vm.saveState {
                InlineBanner(kind: .error, text: message)
            }
        }
    }

    private var nameCard: some View {
        Card(title: "Name") {
            VStack(spacing: 10) {
                LabeledField(label: "First name") {
                    TextField("First name", text: $vm.firstName)
                        .onChange(of: vm.firstName) { _ in vm.fieldDidChange() }
                }
                LabeledField(label: "Last name") {
                    TextField("Last name", text: $vm.lastName)
                        .onChange(of: vm.lastName) { _ in vm.fieldDidChange() }
                }
            }
        }
    }

    private var aboutYouCard: some View {
        Card(title: "About you") {
            VStack(spacing: 10) {
                LabeledPicker(label: "Gender", selection: $vm.gender, options: genders)
                    .onChange(of: vm.gender) { _ in vm.fieldDidChange() }

                // DOB is mandatory (BUG-032); always show picker, no toggle to skip
                DatePicker("Date of birth", selection: $vm.dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: vm.dateOfBirth) { _ in vm.fieldDidChange() }

                LabeledPicker(label: "Ethnicity", selection: $vm.ethnicity, options: ethnicities)
                    .onChange(of: vm.ethnicity) { _ in vm.fieldDidChange() }
            }
        }
    }

    private var bodyCard: some View {
        Card(title: "Body") {
            VStack(spacing: 10) {
                LabeledField(label: "Height (cm)") {
                    TextField("e.g. 175", text: $vm.heightCm)
                        .keyboardType(.decimalPad)
                        .onChange(of: vm.heightCm) { _ in vm.fieldDidChange() }
                }
                LabeledField(label: "Weight (kg)") {
                    TextField("e.g. 70", text: $vm.weightKg)
                        .keyboardType(.decimalPad)
                        .onChange(of: vm.weightKg) { _ in vm.fieldDidChange() }
                }
            }
        }
    }

    private var lifestyleCard: some View {
        Card(title: "Lifestyle") {
            VStack(spacing: 10) {
                LabeledPicker(label: "Smoking", selection: $vm.smokingStatus, options: smokingStatuses)
                    .onChange(of: vm.smokingStatus) { _ in vm.fieldDidChange() }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nutrition quality")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                    Picker("Nutrition quality", selection: $vm.nutritionQuality) {
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.nutritionQuality) { _ in vm.fieldDidChange() }
                }
            }
        }
    }

    private var notificationsCard: some View {
        Card(title: "Notifications") {
            VStack(spacing: 10) {
                Toggle("In-app notifications", isOn: $vm.notifyInApp)
                    .onChange(of: vm.notifyInApp) { _ in vm.fieldDidChange() }
                Toggle("Push notifications", isOn: $vm.notifyPush)
                    .onChange(of: vm.notifyPush) { _ in vm.fieldDidChange() }
                Toggle("Email notifications", isOn: $vm.notifyEmail)
                    .onChange(of: vm.notifyEmail) { _ in vm.fieldDidChange() }

                Text("Notification logic coming soon.")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Derived

    private var displayName: String {
        let candidate = "\(vm.firstName) \(vm.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "Your profile" : candidate
    }

    // MARK: - Load

    private func load() async {
        if vm.isLoading { return }

        // Step 1: Pre-populate from OnboardingManager cache instantly (0ms, no network).
        // This means fields are filled and ready before the view even finishes appearing.
        vm.firstName = onboardingManager.firstName
        vm.lastName = onboardingManager.lastName
        vm.gender = onboardingManager.gender
        vm.ethnicity = onboardingManager.ethnicity
        vm.smokingStatus = onboardingManager.smokingStatus
        vm.heightCm = onboardingManager.heightCm > 0 ? String(onboardingManager.heightCm) : ""
        vm.weightKg = onboardingManager.weightKg > 0 ? String(onboardingManager.weightKg) : ""
        vm.nutritionQuality = onboardingManager.nutritionQuality
        vm.notifyInApp = onboardingManager.notifyInApp
        vm.notifyPush = onboardingManager.notifyPush
        vm.notifyEmail = onboardingManager.notifyEmail
        vm.avatarURL = onboardingManager.avatarURL
        if let dob = onboardingManager.dateOfBirth {
            vm.dateOfBirth = dob
            vm.hasDateOfBirth = true
        }

        // Step 2: Background network refresh to ensure server data is authoritative.
        // Fields are only overwritten if the user hasn't started editing yet.
        vm.isLoading = true
        defer { vm.isLoading = false }

        do {
            let profile = try await dataManager.loadUserProfile()
            // Don't overwrite if the user started typing while we were fetching.
            guard !vm.hasUnsavedChanges, let p = profile else {
                vm.bindDirtyTracking()
                return
            }

            vm.avatarURL = p.avatar_url
            onboardingManager.avatarURL = p.avatar_url
            vm.firstName = p.first_name ?? onboardingManager.firstName
            vm.lastName = p.last_name ?? onboardingManager.lastName
            vm.gender = p.gender ?? onboardingManager.gender
            vm.ethnicity = p.ethnicity ?? onboardingManager.ethnicity
            vm.smokingStatus = p.smoking_status ?? onboardingManager.smokingStatus

            if let h = p.height_cm { vm.heightCm = String(h) }
            if let w = p.weight_kg { vm.weightKg = String(w) }
            vm.nutritionQuality = p.nutrition_quality ?? onboardingManager.nutritionQuality

            vm.notifyInApp = p.notify_inapp ?? onboardingManager.notifyInApp
            vm.notifyPush = p.notify_push ?? onboardingManager.notifyPush
            vm.notifyEmail = p.notify_email ?? onboardingManager.notifyEmail

            if let dobString = p.date_of_birth, let dob = parseYmd(dobString) {
                vm.dateOfBirth = dob
                vm.hasDateOfBirth = true
            } else {
                vm.dateOfBirth = EditProfileViewModel.dobPlaceholder
                vm.hasDateOfBirth = false
            }

            vm.bindDirtyTracking()
        } catch {
            // Cache data is already displayed — just surface the error non-destructively.
            vm.saveState = .failure(error.localizedDescription)
            vm.bindDirtyTracking()
        }
    }

    // MARK: - Save

    private func saveAll() async {
        let trimmedFirst = vm.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFirst.isEmpty {
            vm.saveState = .failure("First name can't be empty.")
            return
        }

        // DOB is mandatory (BUG-032); must be in the past
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if vm.dateOfBirth >= startOfToday {
            vm.saveState = .failure("Date of birth must be in the past.")
            return
        }

        if vm.isLoading { return }
        vm.isLoading = true
        defer { vm.isLoading = false }

        do {
            let height = Double(vm.heightCm.trimmingCharacters(in: .whitespacesAndNewlines))
            let weight = Double(vm.weightKg.trimmingCharacters(in: .whitespacesAndNewlines))

            // 1) Save editable profile fields
            try await dataManager.saveUserProfile(
                firstName: trimmedFirst,
                lastName: vm.lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                gender: vm.gender.isEmpty ? nil : vm.gender,
                dateOfBirth: vm.dateOfBirth,
                ethnicity: vm.ethnicity.isEmpty ? nil : vm.ethnicity,
                smokingStatus: vm.smokingStatus.isEmpty ? nil : vm.smokingStatus,
                heightCm: height,
                weightKg: weight,
                nutritionQuality: vm.nutritionQuality,
                bloodPressureStatus: nil,
                diabetesStatus: nil,
                hasPriorHeartAttack: nil,
                hasPriorStroke: nil,
                familyHeartDiseaseEarly: nil,
                familyStrokeEarly: nil,
                familyType2Diabetes: nil,
                onboardingStep: nil
            )

            // Keep family_members.first_name in sync
            try await dataManager.updateMyMemberName(firstName: trimmedFirst)

            // 2) Notification preferences
            let notificationPayload: [String: AnyJSON] = [
                "notify_in_app": .bool(vm.notifyInApp),
                "notify_push": .bool(vm.notifyPush),
                "notify_email": .bool(vm.notifyEmail)
            ]
            try await dataManager.updateUserProfile(notificationPayload)

            // 3) Recalculate WHO risk using updated profile fields + fixed health_conditions
            let conditions = (try? await dataManager.fetchMyHealthConditions()) ?? []
            let bpStatus = conditions.contains("bp_elevated_untreated") ? "elevated_untreated"
                         : conditions.contains("bp_elevated_treated")   ? "elevated_treated"
                         : conditions.contains("bp_normal")             ? "normal"
                         : "unknown"
            let diabStatus = conditions.contains("diabetes_type_1")     ? "type_1"
                           : conditions.contains("diabetes_type_2")     ? "type_2"
                           : conditions.contains("diabetes_pre_diabetic") ? "pre_diabetic"
                           : conditions.contains("diabetes_none")       ? "none"
                           : "unknown"
            let risk = RiskCalculator.calculateRisk(
                dateOfBirth: vm.hasDateOfBirth ? vm.dateOfBirth : nil,
                smokingStatus: vm.smokingStatus,
                bloodPressureStatus: bpStatus,
                diabetesStatus: diabStatus,
                hasPriorHeartAttack: conditions.contains("prior_heart_attack"),
                hasPriorStroke: conditions.contains("prior_stroke"),
                familyHeartDiseaseEarly: conditions.contains("family_history_heart_early"),
                familyStrokeEarly: conditions.contains("family_history_stroke_early"),
                familyType2Diabetes: conditions.contains("family_history_type2_diabetes"),
                heightCm: height ?? 0,
                weightKg: weight ?? 0
            )
            try await dataManager.saveRiskAssessment(
                riskBand: risk.band.rawValue,
                riskPoints: risk.points,
                optimalTarget: risk.optimalTarget
            )

            // 4) Sync onboardingManager with saved values
            onboardingManager.firstName = trimmedFirst
            onboardingManager.lastName = vm.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            onboardingManager.gender = vm.gender
            onboardingManager.ethnicity = vm.ethnicity
            onboardingManager.smokingStatus = vm.smokingStatus
            onboardingManager.dateOfBirth = vm.dateOfBirth
            if let height { onboardingManager.heightCm = height }
            if let weight { onboardingManager.weightKg = weight }
            onboardingManager.nutritionQuality = vm.nutritionQuality
            onboardingManager.notifyInApp = vm.notifyInApp
            onboardingManager.notifyPush = vm.notifyPush
            onboardingManager.notifyEmail = vm.notifyEmail

            vm.saveState = .success("Profile saved.")
            vm.bindDirtyTracking()

            NotificationCenter.default.post(name: .profileDidUpdate, object: nil)
        } catch {
            vm.saveState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Avatar

    @MainActor
    private func uploadAvatar(data: Data) async {
        vm.isUploadingAvatar = true
        vm.avatarErrorMessage = nil
        defer { vm.isUploadingAvatar = false }
        do {
            let urlString = try await dataManager.uploadAvatarImage(data: data, mimeType: "image/jpeg")
            try await dataManager.updateAvatarURL(urlString)
            vm.avatarURL = urlString
            onboardingManager.avatarURL = urlString
        } catch {
            vm.avatarErrorMessage = "Couldn't upload your photo. Check your connection and try again."
        }
    }

    // MARK: - Helpers

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let value = (first + second).uppercased()
        return value.isEmpty ? "ME" : value
    }

    private func parseYmd(_ value: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: value)
    }
}

// MARK: - UI building blocks

private struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
            field
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.miyaBackground)
                .cornerRadius(12)
        }
    }
}

private struct LabeledPicker: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
            Picker(label, selection: $selection) {
                Text("Select").tag("")
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.miyaBackground)
            .cornerRadius(12)
        }
    }
}

private struct InlineBanner: View {
    enum Kind { case success, error }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(kind == .success ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: kind == .success ? "checkmark" : "exclamationmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(kind == .success ? .green : .red)
                )
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.03))
        )
    }
}
