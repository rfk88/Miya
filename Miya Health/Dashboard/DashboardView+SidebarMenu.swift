import SwiftUI
import Supabase

// MARK: - DashboardView Sidebar Menu Extension
// Extracted from DashboardView.swift for better organization and compilation performance

extension DashboardView {
    // MARK: - Sidebar mode
    
    enum SidebarMode {
        case menu
        case account
        case manageMembers
    }
    
    // MARK: - SIDEBAR MENU
    
    struct SidebarMenu: View {
        @Binding var isVisible: Bool
        @Binding var isInviteMemberSheetPresented: Bool
        let familyMemberRecords: [FamilyMemberRecord]
        let currentUserId: String?
        let familyDisplayName: String
        let onReloadMembers: () -> Void
        let onUpdateResolvedFamilyName: (String) -> Void
        
        // Needed for sign-out + cache reset. Do not access private auth props from views.
        @EnvironmentObject var authManager: AuthManager
        @EnvironmentObject var dataManager: DataManager
        @EnvironmentObject var onboardingManager: OnboardingManager
        
        @State private var mode: SidebarMode = .menu
        @State private var isWearableSyncing: Bool = false
        @State private var wearableSyncErrorMessage: String?
        @State private var isWearableSyncErrorPresented: Bool = false
        @State private var showWearableSelectionSheet: Bool = false
        
        private var isSuperAdminUser: Bool {
            guard let uid = currentUserId else { return false }
            return familyMemberRecords.first(where: { $0.userId?.uuidString == uid })?.role.lowercased() == "superadmin"
        }
        
        private var accountName: String {
            let first = onboardingManager.firstName.trimmingCharacters(in: .whitespaces)
            let last = onboardingManager.lastName.trimmingCharacters(in: .whitespaces)
            let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { return full }
            if !onboardingManager.email.isEmpty { return onboardingManager.email }
            return "You"
        }
        
        private var accountEmail: String {
            if !onboardingManager.email.isEmpty { return onboardingManager.email }
            return ""
        }
        
        private var membersDisplayString: String {
            let memberNames = familyMemberRecords.map { record in
                if record.userId?.uuidString == currentUserId {
                    return "\(record.firstName) (you)"
                } else {
                    return record.firstName
                }
            }
            return memberNames.joined(separator: ", ")
        }
        
        var body: some View {
            let menuWidth = UIScreen.main.bounds.width * 0.75
            
            ZStack {
                Color.miyaEmerald
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Brand line
                    VStack(alignment: .leading, spacing: 6) {
                        Text("One family, one mission.")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                            .padding(.trailing, 40)
                    }
                    .padding(.top, 40)
                    
                    // Main content
                    modeContent
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .frame(width: menuWidth, alignment: .leading)
            .alert("Wearable sync error", isPresented: $isWearableSyncErrorPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(wearableSyncErrorMessage ?? "Something went wrong while syncing your wearables.")
            }
            .sheet(isPresented: $showWearableSelectionSheet, onDismiss: {
                Task {
                    await recomputeWearableBaselineWithRetries()
                }
            }) {
                NavigationStack {
                    WearableSelectionView(isGuidedSetupInvite: false, isReconnectMode: true)
                        .environmentObject(authManager)
                        .environmentObject(dataManager)
                        .environmentObject(onboardingManager)
                }
            }
        }

        private func triggerWearableSync() {
            showWearableSelectionSheet = true
        }

        private func recomputeWearableBaselineWithRetries() async {
            guard !isWearableSyncing else { return }
            await MainActor.run {
                isWearableSyncing = true
                wearableSyncErrorMessage = nil
            }
            defer {
                Task { @MainActor in
                    isWearableSyncing = false
                }
            }

            var lastAttempt: DataManager.WearableBaselineAttempt?
            for attempt in 1...6 {
                do {
                    let attemptResult = try await dataManager.computeAndPersistWearableBaseline(days: 21)
                    lastAttempt = attemptResult
                    if attemptResult.snapshot != nil {
                        // Success! Refresh dashboard to show updated vitality
                        print("✅ Dashboard: Wearable baseline recomputed successfully, refreshing dashboard")
                        onReloadMembers()
                        return
                    }
                } catch {
                    await MainActor.run {
                        wearableSyncErrorMessage = "Wearable sync error: \(error.localizedDescription)"
                        isWearableSyncErrorPresented = true
                    }
                    return
                }

                if attempt < 6 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }

            if let info = lastAttempt {
                await MainActor.run {
                    wearableSyncErrorMessage =
                        "We're still missing enough data to calculate your Vitality. Days: \(info.daysUsed)/7, sleep: \(info.sleepDays), steps: \(info.stepDays), heart signal: \(info.stressSignalDays)."
                    isWearableSyncErrorPresented = true
                }
            } else {
                await MainActor.run {
                    wearableSyncErrorMessage =
                        "We haven't received enough wearable data yet to compute Vitality. Try again after your next device sync."
                    isWearableSyncErrorPresented = true
                }
            }
        }
        
        // MARK: - Mode content
        
        @ViewBuilder
        private var modeContent: some View {
            switch mode {
            case .menu:
                menuContent
                
            case .account:
                AccountSidebarView(
                    userName: accountName,
                    userEmail: accountEmail,
                    familyName: familyDisplayName,
                    familyMembersDisplay: membersDisplayString,
                    isSuperAdmin: isSuperAdminUser,
                    isSyncingWearables: isWearableSyncing,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .menu
                        }
                    },
                    onSignOut: {
                        Task {
                            do {
                                // signOut() posts .userDidLogout notification which triggers full state reset
                                try await authManager.signOut()
                            } catch {
                                print("❌ Dashboard: Sign out failed: \(error.localizedDescription)")
                            }
                        }
                    },
                    onConnectWearables: {
                        triggerWearableSync()
                    },
                    onManageMembers: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .manageMembers
                        }
                    },
                    onSaveProfile: { newName in
                        try await dataManager.updateMyMemberName(firstName: newName)
                        onboardingManager.firstName = newName
                    },
                    onSaveFamilyName: { newName in
                        guard let familyId = dataManager.currentFamilyId else {
                            throw NSError(
                                domain: "MiyaDashboard",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Family not loaded"]
                            )
                        }
                        try await dataManager.updateFamilyName(familyId: familyId, name: newName)
                        onUpdateResolvedFamilyName(newName)
                    }
                )
                
            case .manageMembers:
                ManageMembersView(
                    members: familyMemberRecords.map {
                        FamilyMemberSummary(
                            id: $0.id.uuidString,
                            name: $0.firstName,
                            isYou: $0.userId?.uuidString == currentUserId,
                            isSuperAdmin: $0.role.lowercased() == "superadmin"
                        )
                    },
                    isSuperAdmin: isSuperAdminUser,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .account
                        }
                    },
                    onRemove: { member in
                        guard isSuperAdminUser else { return }
                        Task {
                            do {
                                try await dataManager.softRemoveFamilyMember(memberId: member.id)
                                onReloadMembers()
                            } catch {
                                print("❌ Dashboard: Remove member failed: \(error.localizedDescription)")
                            }
                        }
                    },
                    onInvite: {
                        guard isSuperAdminUser else { return }
                        isInviteMemberSheetPresented = true
                    }
                )
            }
        }
        
        // MARK: - MENU CONTENT
        
        private var menuContent: some View {
                VStack(alignment: .leading, spacing: 24) {
                
                // Account block (tap to open Account page)
                VStack(alignment: .leading, spacing: 4) {
                    let displayName = accountName
                    Text("Account")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(sidebarInitials(from: displayName))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
                                .font(.system(size: 15, weight: .semibold))
                            Text("Account & Settings")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .account
                        }
                    }
                }
                
                // Main menu items
                VStack(alignment: .leading, spacing: 20) {
                    menuItem(icon: "book.closed", title: "Education Hub") {
                        print("Education Hub tapped")
                    }
                    
                    // Superadmin-only: reuse onboarding invite flow (same validations + DB writes).
                    if isSuperAdminUser {
                        menuItem(icon: "person.badge.plus", title: "Invite Member") {
                            print("✅ Invite Member tapped")
                            isInviteMemberSheetPresented = true
                        }
                    }
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Sign out at bottom (still accessible from menu view)
                Button {
                    Task {
                        do {
                            try await authManager.signOut()
                        } catch {
                            print("⚠️ Sign out failed: \(error.localizedDescription)")
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Sign out")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Color.red.opacity(0.9))
                }
                .padding(.bottom, 24)
            }
        }
        
        // MARK: - Helpers
        
        private func menuItem(icon: String, title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, alignment: .leading)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        
        // Local initials helper just for SidebarMenu
        private func sidebarInitials(from name: String) -> String {
            let parts = name.split(separator: " ").map(String.init)
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
    }
}
