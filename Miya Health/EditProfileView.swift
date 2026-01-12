//
//  EditProfileView.swift
//  Miya Health
//
//  Canonical profile editor:
//  - Profile fields live in public.user_profiles (first_name/last_name + onboarding answers)
//  - Auth credentials live in Supabase Auth (email/password)
//

import SwiftUI
import Combine
import Supabase

@MainActor
final class EditProfileViewModel: ObservableObject {
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
    @Published var dateOfBirth: Date = Date()
    @Published var hasDateOfBirth: Bool = false
    @Published var ethnicity: String = ""
    @Published var smokingStatus: String = ""
    @Published var heightCm: String = ""
    @Published var weightKg: String = ""
    @Published var nutritionQuality: Int = 3

    // WHO risk fields (in user_profiles)
    @Published var bloodPressureStatus: String = "unknown"
    @Published var diabetesStatus: String = "none"
    @Published var hasPriorHeartAttack: Bool = false
    @Published var hasPriorStroke: Bool = false
    @Published var familyHeartDiseaseEarly: Bool = false
    @Published var familyStrokeEarly: Bool = false
    @Published var familyType2Diabetes: Bool = false

    // health_conditions (separate table)
    @Published var hasChronicKidneyDisease: Bool = false
    @Published var hasAtrialFibrillation: Bool = false
    @Published var hasHighCholesterol: Bool = false

    // Champion + notifications (in user_profiles)
    @Published var championEnabled: Bool = false
    @Published var championName: String = ""
    @Published var championEmail: String = ""
    @Published var championPhone: String = ""

    @Published var notifyInApp: Bool = true
    @Published var notifyPush: Bool = false
    @Published var notifyEmail: Bool = false
    @Published var championNotifyEmail: Bool = true
    @Published var championNotifySms: Bool = false

    @Published var quietHoursStart: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @Published var quietHoursEnd: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @Published var quietHoursApplyCritical: Bool = false

    // MARK: - Auth fields (Supabase Auth)
    @Published var currentEmail: String = ""
    @Published var newEmail: String = ""
    @Published var currentPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmNewPassword: String = ""

    // MARK: - UI state
    @Published var isLoading: Bool = false
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

        let bp: String
        let diabetes: String
        let heartAttack: Bool
        let stroke: Bool
        let famHeart: Bool
        let famStroke: Bool
        let famDiabetes: Bool

        let ckd: Bool
        let afib: Bool
        let cholesterol: Bool

        let championEnabled: Bool
        let championName: String
        let championEmail: String
        let championPhone: String

        let notifyInApp: Bool
        let notifyPush: Bool
        let notifyEmail: Bool
        let championNotifyEmail: Bool
        let championNotifySms: Bool
        let quietStart: Date
        let quietEnd: Date
        let quietApplyCritical: Bool
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
            bp: bloodPressureStatus,
            diabetes: diabetesStatus,
            heartAttack: hasPriorHeartAttack,
            stroke: hasPriorStroke,
            famHeart: familyHeartDiseaseEarly,
            famStroke: familyStrokeEarly,
            famDiabetes: familyType2Diabetes,
            ckd: hasChronicKidneyDisease,
            afib: hasAtrialFibrillation,
            cholesterol: hasHighCholesterol,
            championEnabled: championEnabled,
            championName: championName,
            championEmail: championEmail,
            championPhone: championPhone,
            notifyInApp: notifyInApp,
            notifyPush: notifyPush,
            notifyEmail: notifyEmail,
            championNotifyEmail: championNotifyEmail,
            championNotifySms: championNotifySms,
            quietStart: quietHoursStart,
            quietEnd: quietHoursEnd,
            quietApplyCritical: quietHoursApplyCritical
        )
    }

    private func updateDirtyState() {
        guard let initialSnapshot else {
            hasUnsavedChanges = false
            return
        }
        let profileDirty = (computeSnapshot() != initialSnapshot)
        let emailDirty = !newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && newEmail.lowercased() != currentEmail.lowercased()
        let passwordDirty = !newPassword.isEmpty || !confirmNewPassword.isEmpty
        hasUnsavedChanges = profileDirty || emailDirty || passwordDirty
    }

    func bindDirtyTracking() {
        // A light-weight way to track changes without heavy Combine graphs.
        // Call this after initial load.
        initialSnapshot = computeSnapshot()
        updateDirtyState()
    }

    func fieldDidChange() {
        updateDirtyState()
        if case .success = saveState { saveState = .idle }
        if case .failure = saveState { saveState = .idle }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = EditProfileViewModel()

    private let genders = ["Male", "Female"]
    private let ethnicities = ["White", "Black", "Asian", "Hispanic", "Other"]
    private let smokingStatuses = ["Never", "Former", "Current"]
    private let bloodPressureStatuses = ["normal", "elevated_untreated", "elevated_treated", "unknown"]
    private let diabetesStatuses = ["none", "pre_diabetic", "type_1", "type_2", "unknown"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.miyaBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerCard
                        accountCard
                        nameCard
                        aboutYouCard
                        bodyCard
                        lifestyleCard
                        whoRiskCard
                        conditionsCard
                        championCard
                        notificationsCard
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
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
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        Card {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.miyaEmerald.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(initials(from: "\(vm.firstName) \(vm.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.miyaEmerald)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Text(vm.currentEmail.isEmpty ? " " : vm.currentEmail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                }
                Spacer()
                if vm.isLoading {
                    ProgressView().progressViewStyle(.circular)
                }
            }

            if case .success(let message) = vm.saveState {
                InlineBanner(kind: .success, text: message)
            }
            if case .failure(let message) = vm.saveState {
                InlineBanner(kind: .error, text: message)
            }
        }
    }

    private var accountCard: some View {
        Card(title: "Account") {
            VStack(spacing: 10) {
                LabeledField(label: "Email") {
                    TextField("Email", text: $vm.newEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .onChange(of: vm.newEmail) { _ in vm.fieldDidChange() }
                }

                LabeledField(label: "Current password (required)") {
                    SecureField("Current password", text: $vm.currentPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Divider().opacity(0.4)

                VStack(spacing: 10) {
                    LabeledField(label: "New password") {
                        SecureField("New password", text: $vm.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        .onChange(of: vm.newPassword) { _ in vm.fieldDidChange() }
                    }
                    LabeledField(label: "Confirm new password") {
                        SecureField("Confirm new password", text: $vm.confirmNewPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        .onChange(of: vm.confirmNewPassword) { _ in vm.fieldDidChange() }
                    }
                }

                Text("Changing email/password may require confirming via email. For security, we’ll re-authenticate using your current password.")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                Toggle(isOn: $vm.hasDateOfBirth) {
                    Text("Include date of birth")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                }
                .onChange(of: vm.hasDateOfBirth) { _ in vm.fieldDidChange() }

                if vm.hasDateOfBirth {
                    DatePicker("Date of birth", selection: $vm.dateOfBirth, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .onChange(of: vm.dateOfBirth) { _ in vm.fieldDidChange() }
                }

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

    private var whoRiskCard: some View {
        Card(title: "Heart health (WHO Risk)") {
            VStack(spacing: 10) {
                LabeledPicker(label: "Blood pressure", selection: $vm.bloodPressureStatus, options: bloodPressureStatuses)
                    .onChange(of: vm.bloodPressureStatus) { _ in vm.fieldDidChange() }
                LabeledPicker(label: "Diabetes", selection: $vm.diabetesStatus, options: diabetesStatuses)
                    .onChange(of: vm.diabetesStatus) { _ in vm.fieldDidChange() }

                Toggle("Prior heart attack", isOn: $vm.hasPriorHeartAttack)
                    .onChange(of: vm.hasPriorHeartAttack) { _ in vm.fieldDidChange() }
                Toggle("Prior stroke", isOn: $vm.hasPriorStroke)
                    .onChange(of: vm.hasPriorStroke) { _ in vm.fieldDidChange() }

                Divider().opacity(0.4)

                Toggle("Family heart disease before 60", isOn: $vm.familyHeartDiseaseEarly)
                    .onChange(of: vm.familyHeartDiseaseEarly) { _ in vm.fieldDidChange() }
                Toggle("Family stroke before 60", isOn: $vm.familyStrokeEarly)
                    .onChange(of: vm.familyStrokeEarly) { _ in vm.fieldDidChange() }
                Toggle("Family Type 2 diabetes", isOn: $vm.familyType2Diabetes)
                    .onChange(of: vm.familyType2Diabetes) { _ in vm.fieldDidChange() }
            }
        }
    }

    private var conditionsCard: some View {
        Card(title: "Conditions") {
            VStack(spacing: 10) {
                Toggle("Chronic kidney disease", isOn: $vm.hasChronicKidneyDisease)
                    .onChange(of: vm.hasChronicKidneyDisease) { _ in vm.fieldDidChange() }
                Toggle("Atrial fibrillation", isOn: $vm.hasAtrialFibrillation)
                    .onChange(of: vm.hasAtrialFibrillation) { _ in vm.fieldDidChange() }
                Toggle("High cholesterol", isOn: $vm.hasHighCholesterol)
                    .onChange(of: vm.hasHighCholesterol) { _ in vm.fieldDidChange() }
            }
        }
    }

    private var championCard: some View {
        Card(title: "Champion") {
            VStack(spacing: 10) {
                Toggle("Enable champion", isOn: $vm.championEnabled)
                    .onChange(of: vm.championEnabled) { _ in vm.fieldDidChange() }

                if vm.championEnabled {
                    LabeledField(label: "Name") {
                        TextField("Champion name", text: $vm.championName)
                            .onChange(of: vm.championName) { _ in vm.fieldDidChange() }
                    }
                    LabeledField(label: "Email") {
                        TextField("Champion email", text: $vm.championEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .onChange(of: vm.championEmail) { _ in vm.fieldDidChange() }
                    }
                    LabeledField(label: "Phone") {
                        TextField("Champion phone", text: $vm.championPhone)
                            .keyboardType(.phonePad)
                            .onChange(of: vm.championPhone) { _ in vm.fieldDidChange() }
                    }
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

                Divider().opacity(0.4)

                Toggle("Champion email alerts", isOn: $vm.championNotifyEmail)
                    .onChange(of: vm.championNotifyEmail) { _ in vm.fieldDidChange() }
                Toggle("Champion SMS alerts", isOn: $vm.championNotifySms)
                    .onChange(of: vm.championNotifySms) { _ in vm.fieldDidChange() }

                Divider().opacity(0.4)

                DatePicker("Quiet hours start", selection: $vm.quietHoursStart, displayedComponents: .hourAndMinute)
                    .onChange(of: vm.quietHoursStart) { _ in vm.fieldDidChange() }
                DatePicker("Quiet hours end", selection: $vm.quietHoursEnd, displayedComponents: .hourAndMinute)
                    .onChange(of: vm.quietHoursEnd) { _ in vm.fieldDidChange() }
                Toggle("Apply quiet hours to critical alerts", isOn: $vm.quietHoursApplyCritical)
                    .onChange(of: vm.quietHoursApplyCritical) { _ in vm.fieldDidChange() }
            }
        }
    }

    // MARK: - Derived

    private var displayName: String {
        let candidate = "\(vm.firstName) \(vm.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "Your profile" : candidate
    }

    // MARK: - Load/save

    private func load() async {
        if vm.isLoading { return }
        vm.isLoading = true
        defer { vm.isLoading = false }

        do {
            // Auth email
            let email = try await authManager.getCurrentEmail() ?? ""
            vm.currentEmail = email
            vm.newEmail = email

            // Profile row
            let profile = try await dataManager.loadUserProfile()
            if let p = profile {
                vm.firstName = p.first_name ?? onboardingManager.firstName
                vm.lastName = p.last_name ?? onboardingManager.lastName
                vm.gender = p.gender ?? onboardingManager.gender
                vm.ethnicity = p.ethnicity ?? onboardingManager.ethnicity
                vm.smokingStatus = p.smoking_status ?? onboardingManager.smokingStatus

                if let h = p.height_cm { vm.heightCm = String(h) }
                if let w = p.weight_kg { vm.weightKg = String(w) }
                vm.nutritionQuality = p.nutrition_quality ?? onboardingManager.nutritionQuality

                vm.bloodPressureStatus = p.blood_pressure_status ?? onboardingManager.bloodPressureStatus
                vm.diabetesStatus = p.diabetes_status ?? onboardingManager.diabetesStatus
                vm.hasPriorHeartAttack = p.has_prior_heart_attack ?? onboardingManager.hasPriorHeartAttack
                vm.hasPriorStroke = p.has_prior_stroke ?? onboardingManager.hasPriorStroke
                vm.familyHeartDiseaseEarly = p.family_heart_disease_early ?? onboardingManager.familyHeartDiseaseEarly
                vm.familyStrokeEarly = p.family_stroke_early ?? onboardingManager.familyStrokeEarly
                vm.familyType2Diabetes = p.family_type2_diabetes ?? onboardingManager.familyType2Diabetes

                // Champion + notifications
                vm.championEnabled = p.champion_enabled ?? onboardingManager.championEnabled
                vm.championName = p.champion_name ?? onboardingManager.championName
                vm.championEmail = p.champion_email ?? onboardingManager.championEmail
                vm.championPhone = p.champion_phone ?? onboardingManager.championPhone

                vm.notifyInApp = p.notify_inapp ?? onboardingManager.notifyInApp
                vm.notifyPush = p.notify_push ?? onboardingManager.notifyPush
                vm.notifyEmail = p.notify_email ?? onboardingManager.notifyEmail
                vm.championNotifyEmail = p.champion_notify_email ?? onboardingManager.championNotifyEmail
                vm.championNotifySms = p.champion_notify_sms ?? onboardingManager.championNotifySms

                if let dobString = p.date_of_birth, let dob = parseYmd(dobString) {
                    vm.dateOfBirth = dob
                    vm.hasDateOfBirth = true
                } else {
                    vm.hasDateOfBirth = false
                }

                if let start = p.quiet_hours_start, let startDate = parseHm(start) {
                    vm.quietHoursStart = startDate
                }
                if let end = p.quiet_hours_end, let endDate = parseHm(end) {
                    vm.quietHoursEnd = endDate
                }
                vm.quietHoursApplyCritical = p.quiet_hours_apply_critical ?? onboardingManager.quietHoursApplyCritical
            }

            // health_conditions (best-effort)
            let conditions = try await dataManager.fetchMyHealthConditions()
            vm.hasChronicKidneyDisease = conditions.contains("chronic_kidney_disease")
            vm.hasAtrialFibrillation = conditions.contains("atrial_fibrillation")
            vm.hasHighCholesterol = conditions.contains("high_cholesterol")

            vm.bindDirtyTracking()
        } catch {
            vm.saveState = .failure(error.localizedDescription)
        }
    }

    private func saveAll() async {
        let trimmedFirst = vm.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFirst.isEmpty {
            vm.saveState = .failure("First name can’t be empty.")
            return
        }

        if vm.isLoading { return }
        vm.isLoading = true
        defer { vm.isLoading = false }

        do {
            // 1) Profile fields (user_profiles)
            let height = Double(vm.heightCm.trimmingCharacters(in: .whitespacesAndNewlines))
            let weight = Double(vm.weightKg.trimmingCharacters(in: .whitespacesAndNewlines))
            let dob: Date? = vm.hasDateOfBirth ? vm.dateOfBirth : nil

            try await dataManager.saveUserProfile(
                firstName: trimmedFirst,
                lastName: vm.lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                gender: vm.gender.isEmpty ? nil : vm.gender,
                dateOfBirth: dob,
                ethnicity: vm.ethnicity.isEmpty ? nil : vm.ethnicity,
                smokingStatus: vm.smokingStatus.isEmpty ? nil : vm.smokingStatus,
                heightCm: height,
                weightKg: weight,
                nutritionQuality: vm.nutritionQuality,
                bloodPressureStatus: vm.bloodPressureStatus,
                diabetesStatus: vm.diabetesStatus,
                hasPriorHeartAttack: vm.hasPriorHeartAttack,
                hasPriorStroke: vm.hasPriorStroke,
                familyHeartDiseaseEarly: vm.familyHeartDiseaseEarly,
                familyStrokeEarly: vm.familyStrokeEarly,
                familyType2Diabetes: vm.familyType2Diabetes,
                onboardingStep: nil
            )

            // Keep family_members.first_name in sync immediately (so name updates reflect everywhere,
            // even if the DB-side trigger migration hasn’t been applied yet).
            try await dataManager.updateMyMemberName(firstName: trimmedFirst)

            // 2) health_conditions (keep in sync with onboarding + scoring)
            var heartHealthConditions: [String: Bool] = [:]
            switch vm.bloodPressureStatus {
            case "normal": heartHealthConditions["bp_normal"] = true
            case "elevated_untreated": heartHealthConditions["bp_elevated_untreated"] = true
            case "elevated_treated": heartHealthConditions["bp_elevated_treated"] = true
            default: heartHealthConditions["bp_unknown"] = true
            }
            switch vm.diabetesStatus {
            case "none": heartHealthConditions["diabetes_none"] = true
            case "pre_diabetic": heartHealthConditions["diabetes_pre_diabetic"] = true
            case "type_1": heartHealthConditions["diabetes_type_1"] = true
            case "type_2": heartHealthConditions["diabetes_type_2"] = true
            default: heartHealthConditions["diabetes_unknown"] = true
            }
            if vm.hasPriorHeartAttack { heartHealthConditions["prior_heart_attack"] = true }
            if vm.hasPriorStroke { heartHealthConditions["prior_stroke"] = true }
            if vm.hasChronicKidneyDisease { heartHealthConditions["chronic_kidney_disease"] = true }
            if vm.hasAtrialFibrillation { heartHealthConditions["atrial_fibrillation"] = true }
            if vm.hasHighCholesterol { heartHealthConditions["high_cholesterol"] = true }

            try await dataManager.saveHealthConditions(conditions: heartHealthConditions, sourceStep: "heart_health")

            let medicalHistoryConditions: [String: Bool] = [
                "family_history_heart_early": vm.familyHeartDiseaseEarly,
                "family_history_stroke_early": vm.familyStrokeEarly,
                "family_history_type2_diabetes": vm.familyType2Diabetes
            ]
            try await dataManager.saveHealthConditions(conditions: medicalHistoryConditions, sourceStep: "medical_history")

            // 3) Champion
            try await dataManager.saveChampionSettings(
                name: vm.championEnabled ? nullIfEmpty(vm.championName) : nil,
                email: vm.championEnabled ? nullIfEmpty(vm.championEmail) : nil,
                phone: vm.championEnabled ? nullIfEmpty(vm.championPhone) : nil,
                enabled: vm.championEnabled
            )

            // 4) Notifications / quiet hours
            try await dataManager.saveAlertPreferences(
                notifyInApp: vm.notifyInApp,
                notifyPush: vm.notifyPush,
                notifyEmail: vm.notifyEmail,
                championEmail: vm.championNotifyEmail,
                championSms: vm.championNotifySms,
                quietStart: formatHm(vm.quietHoursStart),
                quietEnd: formatHm(vm.quietHoursEnd),
                quietApplyCritical: vm.quietHoursApplyCritical
            )

            // 5) Auth: email change (optional)
            var authNote: String? = nil
            let targetEmail = vm.newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !targetEmail.isEmpty, targetEmail.lowercased() != vm.currentEmail.lowercased() {
                try await reauthIfNeeded()
                try await authManager.updateEmail(to: targetEmail)
                // Depending on Supabase project settings, this may require confirmation via email.
                // We optimistically update the UI and show a banner to prompt confirmation.
                vm.currentEmail = targetEmail
                authNote = "Check your inbox to confirm your new email."
            }

            // 6) Auth: password change (optional)
            if !vm.newPassword.isEmpty || !vm.confirmNewPassword.isEmpty {
                guard vm.newPassword == vm.confirmNewPassword else {
                    throw DataError.invalidData("New passwords don’t match.")
                }
                guard vm.newPassword.count >= 8 else {
                    throw DataError.invalidData("Password must be at least 8 characters.")
                }
                try await reauthIfNeeded()
                try await authManager.updatePassword(to: vm.newPassword)
                vm.newPassword = ""
                vm.confirmNewPassword = ""
                authNote = authNote ?? "Password updated."
            }

            // 7) Refresh local state used across the app
            onboardingManager.firstName = trimmedFirst
            onboardingManager.lastName = vm.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            onboardingManager.gender = vm.gender
            onboardingManager.ethnicity = vm.ethnicity
            onboardingManager.smokingStatus = vm.smokingStatus
            if vm.hasDateOfBirth {
                onboardingManager.dateOfBirth = vm.dateOfBirth
            }
            if let height { onboardingManager.heightCm = height }
            if let weight { onboardingManager.weightKg = weight }
            onboardingManager.nutritionQuality = vm.nutritionQuality
            onboardingManager.bloodPressureStatus = vm.bloodPressureStatus
            onboardingManager.diabetesStatus = vm.diabetesStatus
            onboardingManager.hasPriorHeartAttack = vm.hasPriorHeartAttack
            onboardingManager.hasPriorStroke = vm.hasPriorStroke
            onboardingManager.familyHeartDiseaseEarly = vm.familyHeartDiseaseEarly
            onboardingManager.familyStrokeEarly = vm.familyStrokeEarly
            onboardingManager.familyType2Diabetes = vm.familyType2Diabetes
            onboardingManager.championEnabled = vm.championEnabled
            onboardingManager.championName = vm.championName
            onboardingManager.championEmail = vm.championEmail
            onboardingManager.championPhone = vm.championPhone
            onboardingManager.notifyInApp = vm.notifyInApp
            onboardingManager.notifyPush = vm.notifyPush
            onboardingManager.notifyEmail = vm.notifyEmail
            onboardingManager.championNotifyEmail = vm.championNotifyEmail
            onboardingManager.championNotifySms = vm.championNotifySms
            onboardingManager.quietHoursStart = vm.quietHoursStart
            onboardingManager.quietHoursEnd = vm.quietHoursEnd
            onboardingManager.quietHoursApplyCritical = vm.quietHoursApplyCritical

            onboardingManager.hasChronicKidneyDisease = vm.hasChronicKidneyDisease
            onboardingManager.hasAtrialFibrillation = vm.hasAtrialFibrillation
            onboardingManager.hasHighCholesterol = vm.hasHighCholesterol

            if let authNote {
                vm.saveState = .success("Saved changes. \(authNote)")
            } else {
                vm.saveState = .success("Saved changes.")
            }
            vm.bindDirtyTracking()

            // Tell the rest of the app to refresh any name-dependent UI (e.g. Champions).
            NotificationCenter.default.post(name: .profileDidUpdate, object: nil)
        } catch {
            vm.saveState = .failure(error.localizedDescription)
        }
    }

    private func reauthIfNeeded() async throws {
        let email = vm.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        guard !vm.currentPassword.isEmpty else {
            throw DataError.invalidData("Enter your current password to update email or password.")
        }
        try await authManager.reauthenticate(email: email, password: vm.currentPassword)
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

    private func parseHm(_ value: String) -> Date? {
        // value from Postgres TIME may come as "HH:mm:ss" or "HH:mm"
        let parts = value.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: h, minute: m))
    }

    private func formatHm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    private func nullIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
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

