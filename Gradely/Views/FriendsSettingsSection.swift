import SwiftUI

/// Friends in Settings → Connected services: who's there, where their
/// timetable comes from, rename or remove, and Add friend.
struct FriendsSettingsSection: View {
    let friends: FriendsViewModel

    @State private var isAddPresented = false
    @State private var renaming: Friend?
    @State private var isRenamePresented = false
    @State private var newName = ""
    @State private var removing: Friend?
    @State private var isRemovePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if friends.friends.isEmpty {
                SettingsSurface {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        SettingsIcon(name: "user-group")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("friends.settings.empty.title")
                                .font(.gradely(.headline))
                            Text("friends.settings.empty.message")
                                .font(.gradely(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                SettingsSurface(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(friends.friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { SettingsRowDivider() }
                            row(friend)
                        }
                    }
                }
            }

            Button {
                isAddPresented = true
            } label: {
                Label {
                    Text("friends.menu.add")
                } icon: {
                    GradelyIcon("user-add-02", size: 15)
                        .foregroundStyle(Brand.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: ControlMetrics.minHeight)
            }
            .buttonStyle(.bordered)
            .tint(Brand.primary)
            .accessibilityIdentifier("settingsAddFriendButton")
        }
        .sheet(isPresented: $isAddPresented) {
            AddFriendView(friends: friends)
        }
        // The dialogs carry the friend they act on: by the time a button's
        // action runs, the presentation binding may already have been reset.
        .alert(AppL10n.string("friends.rename.title"), isPresented: $isRenamePresented, presenting: renaming) { friend in
            TextField(AppL10n.string("friends.add.name"), text: $newName)
            Button(AppL10n.string("action.save")) { friends.rename(friend, to: newName) }
            Button(AppL10n.string("action.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            String(format: AppL10n.string("friends.remove.title"), removing?.name ?? ""),
            isPresented: $isRemovePresented,
            titleVisibility: .visible,
            presenting: removing
        ) { friend in
            Button(AppL10n.string("friends.remove.action"), role: .destructive) { friends.remove(friend) }
            Button(AppL10n.string("action.cancel"), role: .cancel) {}
        } message: { _ in
            Text("friends.remove.message")
        }
    }

    private func row(_ friend: Friend) -> some View {
        HStack(spacing: Spacing.md) {
            SettingsIcon(name: icon(for: friend.source))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: friend.name)
                    .font(.gradely(.body).weight(.semibold))
                Text(verbatim: friend.source.summary)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button {
                    newName = friend.name
                    renaming = friend
                    isRenamePresented = true
                } label: {
                    GradelyLabel("friends.rename.action", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) {
                    removing = friend
                    isRemovePresented = true
                } label: {
                    GradelyLabel("friends.remove.action", systemImage: "trash")
                }
            } label: {
                GradelyIcon(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string("friends.settings.actions"))
            .accessibilityIdentifier("friendActions-\(friend.id)")
        }
        .padding(.horizontal, SettingsRowMetrics.inset)
        .padding(.vertical, Spacing.md)
        .accessibilityIdentifier("friendRow-\(friend.id)")
    }

    private func icon(for source: FriendTimetableSource) -> String {
        switch source {
        case .bakalari: "key-01"
        case .publicClass: "globe-02"
        case .imported: "legal-document-01"
        }
    }
}
