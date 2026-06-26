import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var sessions: [ActivitySession]
    @Query private var friends: [Friend]
    @Query(sort: \MedicationLog.loggedAt, order: .reverse) private var medLogs: [MedicationLog]
    @State private var showEditProfile = false
    private var profile: UserProfile? { profiles.first }
    private var userName: String { profile?.name ?? "Saksham Bhutani" }
    private var userInitial: String { String(userName.prefix(1)).uppercased() }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                avatarSection
                nameSection
                editButton
                statsRow
                profileStrengthCard
                visibleToFriendsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditProfile) { EditProfileView() }
    }

    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = profile?.avatarData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Text(userInitial)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
            }
            Button { showEditProfile = true } label: {
                Circle()
                    .fill(PulseColors.background)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    .overlay {
                        Circle().stroke(PulseColors.borderHairline, lineWidth: 1)
                    }
            }
            .offset(x: -2, y: -2)
        }
    }

    private var nameSection: some View {
        VStack(spacing: 6) {
            Text(userName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PulseColors.textPrimary)
            Text("@\(userName.lowercased().replacingOccurrences(of: " ", with: "")) · joined \(profile?.createdAt.formatted(.dateTime.month(.abbreviated).year()) ?? "2026")")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.textMuted)
            Text(profile?.sex != nil ? "Tracking health, habits & wellness." : "Building a calm, AI-run life.")
                .font(.system(size: 15))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var editButton: some View {
        Button { showEditProfile = true } label: {
            Text("Edit profile")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PulseColors.borderStrong, lineWidth: 1)
                }
        }
    }

    private var statsRow: some View {
        let workoutCount = sessions.filter { $0.statusRaw == "finished" }.count
        let friendCount = friends.count
        let streak = calculateProfileStreak()
        return HStack(spacing: 0) {
            statCell("\(streak)", "day streak")
            Rectangle().fill(PulseColors.borderHairline).frame(width: 1, height: 44)
            statCell("\(friendCount)", "friends")
            Rectangle().fill(PulseColors.borderHairline).frame(width: 1, height: 44)
            statCell("\(workoutCount)", "workouts")
        }
        .padding(.vertical, 16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func calculateProfileStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        let logDays = Set(medLogs.filter { $0.statusRaw == "taken" }.map { cal.startOfDay(for: $0.loggedAt) })
        var check = cal.startOfDay(for: Date())
        while logDays.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileStrengthCard: some View {
        let hasPhoto = profile?.avatarData != nil
        let hasDevice = true
        let hasFriends = !friends.isEmpty
        let completedCount = [hasPhoto, hasDevice, hasFriends].filter { $0 }.count
        let percentage = Int(Double(completedCount) / 3.0 * 100)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Profile strength")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .frame(width: geo.size.width * CGFloat(percentage) / 100, height: 8)
                }
            }
            .frame(height: 8)

            VStack(alignment: .leading, spacing: 12) {
                strengthRow("Add a photo & bio", done: hasPhoto)
                strengthRow("Connect a device", done: hasDevice)
                strengthRow("Add a friend", done: hasFriends)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func strengthRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.green)
            } else {
                Circle()
                    .stroke(PulseColors.borderStrong, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(done ? PulseColors.textSecondary : PulseColors.textPrimary)
        }
    }

    private var visibleToFriendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VISIBLE TO FRIENDS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                Text("Streaks & activity")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Text("Shared")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(16)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }
}

// MARK: - EditProfileView

struct EditProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var name = ""
    @State private var bio = ""
    @State private var goals = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isProcessing = false
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let avatarImage {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                                    }
                            } else if let data = profile?.avatarData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                                    }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(PulseColors.fillSubtle)
                                        .frame(width: 80, height: 80)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(PulseColors.textMuted)
                                }
                            }
                        }
                        if isProcessing {
                            Text("Processing...")
                                .font(.system(size: 11))
                                .foregroundStyle(PulseColors.textMuted)
                        } else {
                            Text("Tap to change")
                                .font(.system(size: 11))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Personal Info") {
                    TextField("Name", text: $name).font(PulseFont.body(15))
                    TextField("Bio", text: $bio, axis: .vertical)
                        .font(PulseFont.body(15)).lineLimit(3...5)
                }
                Section("Health Goals") {
                    TextField("e.g. Sleep 8h, walk 10k steps", text: $goals, axis: .vertical)
                        .font(PulseFont.body(15)).lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { name = profile?.name ?? "" }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                processSelectedPhoto(item)
            }
        }
    }

    private func saveProfile() {
        profile?.name = name.isEmpty ? nil : name
        if let avatarImage, let data = convertToLineArt(avatarImage).pngData() {
            profile?.avatarData = data
        }
        try? modelContext.save()
        dismiss()
    }

    private func processSelectedPhoto(_ item: PhotosPickerItem) {
        isProcessing = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { isProcessing = false }
                return
            }
            let processed = convertToLineArt(image)
            await MainActor.run {
                avatarImage = processed
                isProcessing = false
            }
        }
    }

    private func convertToLineArt(_ image: UIImage) -> UIImage {
        ImageFilterService.lineArt(image)
    }
}

// MARK: - SharedSpaceView

struct SharedSpaceView: View {
    @State private var tasks: [SharedTask] = [
        .init(title: "Grocery run", done: false),
        .init(title: "Book flights", done: true),
        .init(title: "Plan weekend hike", done: false),
    ]
    @State private var notes = ["Meeting notes from Monday", "Recipe ideas"]
    @State private var expenses: [ExpenseEntry] = [
        .init(from: "You", to: "Alex", amount: 24.50),
        .init(from: "Sam", to: "You", amount: 12.00),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                spaceHeader
                membersSection
                sharedTasksSection
                sharedNotesSection
                expenseSplitSection
                Button { } label: {
                    Label("Invite Members", systemImage: "person.badge.plus")
                        .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(PulseColors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(PulseColors.canvas)
        .navigationTitle("Shared Space")
    }

    private var spaceHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill").font(.system(size: 18)).foregroundStyle(PulseColors.accent)
            Text("Household").font(PulseFont.bodySemibold(18)).foregroundStyle(PulseColors.textPrimary)
            Spacer()
        }
    }

    private var membersSection: some View {
        HStack(spacing: -8) {
            memberAvatar("R", .blue)
            memberAvatar("A", .green)
            memberAvatar("S", .orange)
            Spacer()
            Text("3 members").font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
        }
        .modifier(CardMod())
    }

    private func memberAvatar(_ initial: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
            Text(initial).font(PulseFont.bodySemibold(14)).foregroundStyle(color)
        }
        .overlay { Circle().stroke(PulseColors.background, lineWidth: 2) }
    }

    private var sharedTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tasks", systemImage: "checklist")
                .font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
            ForEach($tasks) { $task in
                HStack(spacing: 10) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.done ? PulseColors.success : PulseColors.textFaint)
                        .onTapGesture { task.done.toggle() }
                    Text(task.title).font(PulseFont.body(14))
                        .foregroundStyle(task.done ? PulseColors.textMuted : PulseColors.textPrimary)
                        .strikethrough(task.done)
                }
            }
        }
        .modifier(CardMod())
    }

    private var sharedNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
            ForEach(notes, id: \.self) { note in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(PulseColors.textFaint)
                    Text(note).font(PulseFont.body(14)).foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .modifier(CardMod())
    }

    private var expenseSplitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expenses", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                .font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
            ForEach(expenses) { entry in
                HStack {
                    Text(entry.from).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(PulseColors.textFaint)
                    Text(entry.to).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    Text("$\(entry.amount, specifier: "%.2f")")
                        .font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.accent)
                }
            }
        }
        .modifier(CardMod())
    }
}

// MARK: - Shared Helpers

private struct CardMod: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
    }
}

private struct SharedTask: Identifiable {
    let id = UUID()
    var title: String
    var done: Bool
}

private struct ExpenseEntry: Identifiable {
    let id = UUID()
    var from: String
    var to: String
    var amount: Double
}
