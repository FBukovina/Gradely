import SwiftUI

struct AppLanguageOptionsList: View {
    @Bindable var store: AppLanguageStore
    var usesSettingsChrome: Bool
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: usesSettingsChrome ? Spacing.xl : Spacing.md) {
            languageOptions
            chronicallyOnlineToggle
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appLanguageOptions")
    }

    private var languageOptions: some View {
        Group {
            if usesSettingsChrome {
                SettingsSurface(padding: 0) {
                    options
                }
            } else {
                SettingsSurface(padding: 0) {
                    options
                }
            }
        }
    }

    private var chronicallyOnlineToggle: some View {
        Group {
            if usesSettingsChrome {
                SettingsSurface {
                    toggleContent
                }
            } else {
                SettingsSurface {
                    toggleContent
                }
            }
        }
    }

    private var toggleContent: some View {
        Toggle(isOn: $store.isChronicallyOnline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("settings.language.chronicallyOnline.title")
                    .font(.gradely(.body).weight(.medium))
                Text("settings.language.chronicallyOnline.subtitle")
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Brand.primary)
        .accessibilityIdentifier("chronicallyOnlineToggle")
    }

    private var options: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppLanguage.pickerLanguages.enumerated()), id: \.element.id) { index, language in
                Button {
                    store.selectPickerLanguage(language)
                } label: {
                    languageRow(language)
                        .padding(.horizontal, 20)
                        .padding(.vertical, compact ? Spacing.sm : Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appLanguageOption-\(language.rawValue)")
                .accessibilityAddTraits(isSelected(language) ? [.isSelected] : [])

                if index < AppLanguage.pickerLanguages.count - 1 {
                    SettingsRowDivider(leadingInset: SettingsRowMetrics.inset)
                }
            }
        }
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text(language.displayName)
                .font(.gradely(.body).weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected(language) {
                GradelyIcon("checkmark-circle-02", size: 18)
                    .foregroundStyle(Brand.primary)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(minHeight: ControlMetrics.minHeight)
    }

    private var rowMinHeight: CGFloat {
        #if os(macOS)
        36
        #else
        compact ? 58 : 72
        #endif
    }

    private func isSelected(_ language: AppLanguage) -> Bool {
        store.selection.pickerLanguage == language
    }
}
