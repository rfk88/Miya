import SwiftUI
import PhotosUI

// MARK: - Sidebar and Settings Components
// Extracted from DashboardView.swift - Phase 10 of refactoring

// Wrapper so we can present the crop sheet with .sheet(item:) and always have the image.
private struct ImageForCrop: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Account Sidebar View

struct AccountSidebarView: View {
    let userName: String
    let userEmail: String
    let familyName: String
    let familyMembersDisplay: String
    let isSuperAdmin: Bool
    let onBack: () -> Void
    let onSignOut: () -> Void
    let onManageMembers: () -> Void
    let onSaveProfile: (String) async throws -> Void
    let onSaveFamilyName: ((String) async throws -> Void)?
    let isSyncingWearables: Bool
    let onConnectWearables: () -> Void
    var avatarURL: String? = nil
    var onAvatarURLUpdated: ((String?) -> Void)? = nil

    @EnvironmentObject private var dataManager: DataManager

    // TEMP: mocked devices – later wire real data
    private let connectedDevices: [ConnectedDevice] = [
        ConnectedDevice(name: "Apple Health", lastSyncDescription: "2 hours ago")
    ]
    
    // Profile editing state
    @State private var isEditingProfile: Bool = false
    @State private var draftName: String = ""
    @State private var draftEmail: String = ""
    @State private var isSavingProfile: Bool = false
    @State private var profileErrorMessage: String?
    
    // DISABLED: Family name editing state variables (feature temporarily removed)
    // @State private var isEditingFamilyName: Bool = false
    // @State private var draftFamilyName: String = ""
    // @State private var isSavingFamilyName: Bool = false
    // @State private var familyNameErrorMessage: String?
    
    // Device detail state
    @State private var activeDevice: ConnectedDevice? = nil
    
    // Notification preferences state
    @State private var isShowingNotificationPrefs: Bool = false
    @State private var notifWeeklySummary: Bool = true
    @State private var notifChallenges: Bool = true
    @State private var notifFamilyUpdates: Bool = true
    
    // Quiet mode state
    private enum QuietDuration: String {
        case hours24 = "24 hours"
        case days3   = "3 days"
        case week1   = "1 week"
    }
    @State private var isShowingQuietMode: Bool = false
    @State private var selectedQuietDuration: QuietDuration? = nil
    
    // Contact support state
    @State private var isShowingSupport: Bool = false
    
    @State private var isPresentingChallengeSheet: Bool = false

    // Profile picture flow
    @State private var showAvatarOptions: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var imageForCrop: ImageForCrop? = nil
    @State private var isPhotoPickerPresented: Bool = false
    @State private var isUploadingAvatar: Bool = false
    @State private var avatarErrorMessage: String? = nil

    @State private var localUserName: String
    @State private var localFamilyName: String
    
    private enum ProfileSaveError: LocalizedError {
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Saving took too long. Please check your connection and try again."
            }
        }
    }

    private var userInitials: String {
        initials(from: localUserName)
    }
    
    init(userName: String,
         userEmail: String,
         familyName: String,
         familyMembersDisplay: String,
         isSuperAdmin: Bool,
         isSyncingWearables: Bool,
         onBack: @escaping () -> Void,
         onSignOut: @escaping () -> Void,
         onConnectWearables: @escaping () -> Void,
         onManageMembers: @escaping () -> Void,
         onSaveProfile: @escaping (String) async throws -> Void,
         onSaveFamilyName: ((String) async throws -> Void)? = nil,
         avatarURL: String? = nil,
         onAvatarURLUpdated: ((String?) -> Void)? = nil) {
        self.userName = userName
        self.userEmail = userEmail
        self.familyName = familyName
        self.familyMembersDisplay = familyMembersDisplay
        self.isSuperAdmin = isSuperAdmin
        self.isSyncingWearables = isSyncingWearables
        self.onBack = onBack
        self.onSignOut = onSignOut
        self.onConnectWearables = onConnectWearables
        self.onManageMembers = onManageMembers
        self.onSaveProfile = onSaveProfile
        self.onSaveFamilyName = onSaveFamilyName
        self.avatarURL = avatarURL
        self.onAvatarURLUpdated = onAvatarURLUpdated
        _localUserName = State(initialValue: userName)
        _localFamilyName = State(initialValue: familyName)
    }
    
    var body: some View {
        ZStack {
                // MAIN ACCOUNT CONTENT – scrollable
                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Top bar
                    HStack(spacing: 8) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Text("Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 4)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // ABOUT YOU
                        AccountSection("About you") {
                            HStack(spacing: 12) {
                                Button {
                                    showAvatarOptions = true
                                } label: {
                                    ZStack {
                                        ProfileAvatarView(
                                            imageURL: avatarURL,
                                            initials: userInitials,
                                            diameter: 48,
                                            backgroundColor: Color.white.opacity(0.18),
                                            foregroundColor: .white
                                        )
                                        if isUploadingAvatar {
                                            Circle()
                                                .fill(Color.black.opacity(0.4))
                                                .frame(width: 48, height: 48)
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .disabled(isUploadingAvatar)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(localUserName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    Text(userEmail)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Spacer()
                            }
                            if let avatarErrorMessage {
                                Text(avatarErrorMessage)
                                    .font(.footnote)
                                    .foregroundColor(.red.opacity(0.9))
                            }
                            Button {
                                draftName = localUserName
                                draftEmail = userEmail
                                profileErrorMessage = nil
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingProfile = true
                                }
                            } label: {
                                Text(isEditingProfile ? "Editing…" : "Edit profile")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.18))
                                    .foregroundColor(.white)
                                    .cornerRadius(999)
                            }
                            
                            if isEditingProfile {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Name")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.miyaTextSecondary)
                                        TextField("Name", text: $draftName)
                                            .padding(10)
                                            .background(Color.miyaBackground)
                                            .cornerRadius(10)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Email")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.miyaTextSecondary)
                                        TextField("Email", text: $draftEmail)
                                            .padding(10)
                                            .background(Color.miyaBackground)
                                            .cornerRadius(10)
                                            .disabled(true)
                                        Text("Email is managed by your login provider.")
                                            .font(.footnote)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    if let profileErrorMessage {
                                        Text(profileErrorMessage)
                                            .font(.footnote)
                                            .foregroundColor(.red.opacity(0.9))
                                    }
                                    
                                    HStack {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                isEditingProfile = false
                                            }
                                            profileErrorMessage = nil
                                        } label: {
                                            Text("Cancel")
                                                .font(.system(size: 14, weight: .semibold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                        }
                                        
                                        Button {
                                            Task {
                                                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                                guard !trimmed.isEmpty else {
                                                    await MainActor.run {
                                                        profileErrorMessage = "Name can't be empty."
                                                    }
                                                    return
                                                }
                                                
                                                await MainActor.run {
                                                    isSavingProfile = true
                                                    profileErrorMessage = nil
                                                }
                                                
                                                defer {
                                                    Task { @MainActor in
                                                        isSavingProfile = false
                                                    }
                                                }
                                                
                                                do {
                                                    try await saveProfileWithTimeout(trimmed)
                                                    await MainActor.run {
                                                        localUserName = trimmed
                                                        withAnimation(.easeInOut(duration: 0.2)) {
                                                            isEditingProfile = false
                                                        }
                                                        profileErrorMessage = nil
                                                    }
                                                } catch {
                                                    await MainActor.run {
                                                        profileErrorMessage = error.localizedDescription
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                if isSavingProfile {
                                                    ProgressView()
                                                        .progressViewStyle(.circular)
                                                }
                                                Text(isSavingProfile ? "Saving…" : "Save")
                                                    .font(.system(size: 14, weight: .semibold))
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                        }
                                        .background(Color.miyaEmerald)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                        .disabled(isSavingProfile)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        
                        // CONNECTED DEVICES
                        AccountSection("Connected devices & data") {
                            if connectedDevices.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No devices connected yet.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.85))
                                    
                                    Button {
                                        onConnectWearables()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text(isSyncingWearables ? "Syncing…" : "Connect a device")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.white)
                                        .foregroundColor(.miyaEmerald)
                                        .cornerRadius(999)
                                    }
                                    .disabled(isSyncingWearables)
                                }
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(connectedDevices) { device in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(device.name)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                                
                                                Text("Last sync: \(device.lastSyncDescription)")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                activeDevice = device
                                            }
                                        }
                                    }
                                    
                                    Button {
                                        onConnectWearables()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text(isSyncingWearables ? "Syncing…" : "Connect another device")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                    }
                                    .padding(.top, 4)
                                    .disabled(isSyncingWearables)
                                }
                            }
                        }
                        
                        // FAMILY SETTINGS (edit gated by superadmin)
                            AccountSection("Family settings") {
                                VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                    Text("Family name")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                        Text(localFamilyName)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                    }
                                    Spacer()
                                    // DISABLED: Family name edit temporarily removed due to crash
                                }
                                }
                                
                                Divider().background(Color.white.opacity(0.15))
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Members")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(familyMembersDisplay)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                }
                                
                            if isSuperAdmin {
                                Button {
                                    onManageMembers()
                                } label: {
                                    Text("Manage members")
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(999)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        // APP SETTINGS + SIGN OUT
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingNotificationPrefs = true
                            }
                        } label: {
                            HStack {
                                Text("Notification preferences")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingQuietMode = true
                            }
                        } label: {
                            HStack {
                                Text("Quiet mode")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.vertical, 4)
                        }
                        
                        settingRow(title: "Data & privacy")
                        settingRow(title: "Terms of service")
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingSupport = true
                            }
                        } label: {
                            settingRow(title: "Contact support")
                        }
                        
                        Divider().background(Color.white.opacity(0.15))
                        
                        Button {
                            onSignOut()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Sign out")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(Color.red.opacity(0.95))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 16)
            }
            
            // NOTIFICATION PREFERENCES POPUP
            if isShowingNotificationPrefs {
                Color.clear
                
                VStack(spacing: 16) {
                    Text("Notification preferences")
                        .font(.system(size: 16, weight: .semibold))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $notifWeeklySummary) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weekly family health summary")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("One calm weekly digest for your whole family.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $notifChallenges) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Challenges & missions")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Invites and key updates for Miya challenges.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $notifFamilyUpdates) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Other family member updates")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("When someone completes a mission or hits a streak.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.miyaEmerald))
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingNotificationPrefs = false
                        }
                    } label: {
                        Text("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(16)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
            }
            
            // QUIET MODE POPUP
            if isShowingQuietMode {
                Color.clear
                
                VStack(spacing: 16) {
                    Text("Quiet mode")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Perfect for holidays, illness or busy weeks. Miya will still observe your data, but won't nudge or react.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        quietOptionRow(
                            title: "24 hours",
                            subtitle: "Pause Miya until this time tomorrow.",
                            isSelected: selectedQuietDuration == .hours24
                        ) {
                            selectedQuietDuration = .hours24
                        }
                        
                        quietOptionRow(
                            title: "3 days",
                            subtitle: "Pause Miya for a short break or busy period.",
                            isSelected: selectedQuietDuration == .days3
                        ) {
                            selectedQuietDuration = .days3
                        }
                        
                        quietOptionRow(
                            title: "1 week",
                            subtitle: "Perfect for holidays or recovery weeks.",
                            isSelected: selectedQuietDuration == .week1
                        ) {
                            selectedQuietDuration = .week1
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingQuietMode = false
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        
                        Button {
                            print("Quiet mode on for \(selectedQuietDuration?.rawValue ?? "none selected")")
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingQuietMode = false
                            }
                        } label: {
                            Text("Turn on Quiet mode")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.miyaEmerald)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
            }
            
            // CONTACT SUPPORT POPUP
            if isShowingSupport {
                Color.clear
                
                VStack(spacing: 16) {
                    Text("Contact support")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("If you need help, you can reach the Miya team anytime.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(spacing: 12) {
                        Button {
                            let email = "support@miya.health"
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "envelope")
                                Text("Email Miya Support")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.miyaEmerald)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button {
                            UIPasteboard.general.string = "support@miya.health"
                        } label: {
                            Text("Copy email address")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingSupport = false
                        }
                    } label: {
                        Text("Close")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(16)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
            }
            
        }
        .sheet(item: $activeDevice) { device in
            deviceDetailSheet(for: device)
        }
        .confirmationDialog("Profile picture", isPresented: $showAvatarOptions, titleVisibility: .visible) {
            Button("Change profile picture") {
                selectedPhotoItem = nil
                isPhotoPickerPresented = true
            }
            if avatarURL != nil {
                Button("Remove photo", role: .destructive) {
                    Task { await removeAvatar() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose an option for your profile picture.")
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared())
        .sheet(item: $imageForCrop) { item in
            AvatarCropView(image: item.image, onCancel: {
                imageForCrop = nil
            }, onSave: { data in
                imageForCrop = nil
                Task { await uploadAndSaveAvatar(data: data) }
            })
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let item = newItem else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await MainActor.run {
                            isPhotoPickerPresented = false
                            imageForCrop = ImageForCrop(image: img)
                        }
                    }
                } catch {
                    await MainActor.run {
                        avatarErrorMessage = "We couldn't use that photo. Please try a different one."
                    }
                }
            }
        }
    }

    @MainActor
    private func removeAvatar() async {
        isUploadingAvatar = true
        avatarErrorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            try await dataManager.updateAvatarURL(nil)
            await MainActor.run {
                onAvatarURLUpdated?(nil)
            }
        } catch {
            await MainActor.run {
                avatarErrorMessage = "Couldn't remove your picture. Please try again."
            }
        }
    }

    @MainActor
    private func uploadAndSaveAvatar(data: Data) async {
        isUploadingAvatar = true
        avatarErrorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            let urlString = try await dataManager.uploadAvatarImage(data: data, mimeType: "image/jpeg")
            try await dataManager.updateAvatarURL(urlString)
            await MainActor.run {
                onAvatarURLUpdated?(urlString)
            }
        } catch {
            await MainActor.run {
                avatarErrorMessage = "Couldn't upload your picture. Check your connection and try again."
            }
        }
    }
    
    private func saveProfileWithTimeout(_ name: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await onSaveProfile(name)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw ProfileSaveError.timeout
            }
            
            guard let firstResult = try await group.next() else {
                throw ProfileSaveError.timeout
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func deviceDetailSheet(for device: ConnectedDevice) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(device.name)
                    .font(.system(size: 18, weight: .semibold))
                
                Text("Last sync: \(device.lastSyncDescription)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Button {
                    Task { print("Reconnect \(device.name) tapped") }
                } label: {
                    Text("Reconnect")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    Task { print("Connect another device tapped") }
                } label: {
                    Text("Connect another device")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        activeDevice = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Local helpers (AccountSidebarView)
    
    private func settingRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private func quietOptionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .miyaEmerald : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    
    private func initials(from name: String) -> String {
        let parts = name
            .split(separator: " ")
            .map { String($0) }
        
        let first = parts.first?.first.map { String($0) } ?? ""
        let second = parts.dropFirst().first?.first.map { String($0) } ?? ""
        
        return (first + second).uppercased()
    }
}

// MARK: - Reusable section "card"

private struct AccountSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Simple connected device model

struct ConnectedDevice: Identifiable {
    let id = UUID()
    let name: String
    let lastSyncDescription: String
}

// MARK: - Notifications UI

struct NotificationPanel: View {
    let notifications: [BellNotification]
    let onClose: () -> Void
    let onTap: (BellNotification) -> Void
    let onDismissNotification: (BellNotification) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .padding(8)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                .accessibilityLabel("Close notifications")
            }
            .padding()
            .background(Color.white)
            
            ScrollView {
                VStack(spacing: 0) {
                    if notifications.isEmpty {
                        Text("No personal notifications yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(notifications) { notification in
                            BellNotificationRowView(
                                notification: notification,
                                onTap: { onTap(notification) },
                                onDismiss: { onDismissNotification(notification) }
                            )
                            
                            if notification.id != notifications.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .frame(maxWidth: 560, alignment: .top)
    }
}

private struct BellNotificationRowView: View {
    let notification: BellNotification
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    private var iconName: String {
        switch notification.kind {
        case .personalTrend(let pillar, _, _), .patternAlert(let pillar, _, _, _):
            switch pillar {
            case .sleep: return "moon.stars.fill"
            case .movement: return "figure.walk"
            case .stress: return "heart.text.square"
            }
        case .challengeInvite:
            return "flag.checkered"
        case .challengeDaily:
            return "chart.bar.xaxis"
        case .challengeCompleted:
            return "checkmark.seal.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.orange)
                .padding(6)
                .background(Circle().fill(Color.orange.opacity(0.12)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(notification.subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - FAMILY MEMBERS

struct FamilyMemberSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let isYou: Bool
    let isSuperAdmin: Bool
}

struct ManageMembersView: View {
    let members: [FamilyMemberSummary]
    let isSuperAdmin: Bool
    
    let onBack: () -> Void
    let onRemove: (FamilyMemberSummary) -> Void
    let onInvite: () -> Void
    
    @State private var selectedMemberForRemoval: FamilyMemberSummary? = nil
    
    var body: some View {
        ZStack {
            Color.miyaEmerald.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                
                // Top bar
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Family members")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 40)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(members) { member in
                            memberRow(member)
                        }
                    }
                    .padding(.top, 8)
                    
                    if isSuperAdmin {
                        // Invite member action (moved here from sidebar)
                        Button {
                            onInvite()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Invite member")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.miyaPrimary)
                            .background(Color.white)
                            .cornerRadius(14)
                        }
                        .padding(.top, 16)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        // Remove member
        .confirmationDialog(
            "Remove this family member?",
            isPresented: Binding(
                get: { selectedMemberForRemoval != nil },
                set: { if !$0 { selectedMemberForRemoval = nil } }
            ),
            presenting: selectedMemberForRemoval
        ) { member in
            Button("Remove \(member.name)", role: .destructive) {
                onRemove(member)
                selectedMemberForRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                selectedMemberForRemoval = nil
            }
        } message: { member in
            Text("Are you sure you want to remove \(member.name) from this family?")
        }
    }
    
    // MARK: - Row
    
    private func memberRow(_ member: FamilyMemberSummary) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(memberInitials(from: member.name))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if member.isYou {
                        Text("You")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.20))
                            .cornerRadius(999)
                    }
                }
                
                Text(member.isSuperAdmin ? "Superadmin" : "Member")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            if isSuperAdmin && !member.isSuperAdmin && !member.isYou {
            Menu {
                    Button("Remove member", role: .destructive) {
                        selectedMemberForRemoval = member
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(6)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // Local initials helper just for ManageMembersView
    private func memberInitials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

// MARK: - Shared Helper (for Sidebar, Account, ManageMembers)

fileprivate func initials(from name: String) -> String {
    let parts = name.split(separator: " ").map(String.init)
    let first = parts.first?.first.map(String.init) ?? ""
    let second = parts.dropFirst().first?.first.map(String.init) ?? ""
    return (first + second).uppercased()
}