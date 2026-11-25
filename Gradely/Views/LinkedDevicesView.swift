import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

struct LinkedDevicesSettingsDetail: View {
    @Bindable var viewModel: LinkedDevicesViewModel
    let isGuestMode: Bool
    let hasSchoolSession: Bool
    let schoolSummary: String?
    let onLeaveGuestMode: () -> Void

    @State private var isScannerPresented = false
    @State private var devicePendingRevoke: LinkedWebDevice?
    @State private var isRevokeAllConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if isGuestMode {
                guestModePrompt
            } else {
                heroActionSection
                activeSessionsSection
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            QRDeviceScannerSheet { rawCode in
                let succeeded = await viewModel.handleScannedCode(rawCode)
                if succeeded {
                    isScannerPresented = false
                }
                return succeeded
            }
        }
        .sheet(item: Binding(
            get: { viewModel.pendingApproval },
            set: { newValue in
                if newValue == nil {
                    Task { await viewModel.cancelPendingApproval() }
                }
            }
        )) { approval in
            LinkWebDeviceConfirmationSheet(
                approval: approval,
                schoolSummary: schoolSummary,
                isApproving: viewModel.isApproving,
                errorMessage: viewModel.errorMessage,
                onApprove: {
                    _ = await viewModel.confirmPendingApproval()
                },
                onCancel: {
                    await viewModel.cancelPendingApproval()
                }
            )
        }
        .confirmationDialog(
            "settings.linkedDevices.revoke.title",
            isPresented: Binding(
                get: { devicePendingRevoke != nil },
                set: { if !$0 { devicePendingRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let device = devicePendingRevoke {
                Button("settings.linkedDevices.revoke.confirm", role: .destructive) {
                    Task {
                        await viewModel.revoke(device)
                        devicePendingRevoke = nil
                    }
                }
                .accessibilityIdentifier("linkedDeviceRevokeConfirmButton")
            }
            Button("action.cancel", role: .cancel) {
                devicePendingRevoke = nil
            }
        } message: {
            if let device = devicePendingRevoke {
                Text(String(format: AppL10n.string("settings.linkedDevices.revoke.message"), device.browserAndDeviceTitle))
            }
        }
        .confirmationDialog(
            "settings.linkedDevices.revokeAll.title",
            isPresented: $isRevokeAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("settings.linkedDevices.revokeAll.confirm", role: .destructive) {
                Task { await viewModel.revokeAll() }
            }
            .accessibilityIdentifier("linkedDevicesRevokeAllConfirmButton")
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.linkedDevices.revokeAll.message")
        }
        .alert(
            "settings.linkedDevices.title",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil && viewModel.pendingApproval == nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("action.ok", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            if !isGuestMode {
                await viewModel.refresh()
            }
        }
    }

    private var guestModePrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DetailSectionHeader(title: "settings.linkedDevices.title")
            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("settings.linkedDevices.guest.message")
                        .font(.gradely(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onLeaveGuestMode) {
                        GradelyLabel("gradey.guest.accountSection.action", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("linkedDevicesSignInButton")
                }
            }
        }
    }

    private var heroActionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    GradelyIcon("laptop-phone-sync", size: 22)
                        .foregroundStyle(Brand.primary)
                    Text("settings.linkedDevices.heading")
                        .font(.gradely(.headline))
                }

                Text("settings.linkedDevices.instructions")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xs)

            #if os(iOS)
            Button {
                isScannerPresented = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    if viewModel.isInspectingQR {
                        ProgressView()
                            .tint(Brand.onAccent)
                    } else {
                        GradelyIcon("qr-code-scan", size: 18)
                    }
                    Text("settings.linkedDevices.linkAction")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!hasSchoolSession || viewModel.isInspectingQR)
            .accessibilityIdentifier("linkWebDeviceButton")
            #else
            Label {
                Text("settings.linkedDevices.macHint")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                GradelyIcon("smart-phone-01", size: 15)
                    .foregroundStyle(.secondary)
            }
            .font(.gradely(.footnote))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.xs)
            #endif

            if !hasSchoolSession {
                Label {
                    Text("settings.linkedDevices.error.missingSchool")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    GradelyIcon("alert-02", size: 14)
                        .foregroundStyle(Color.gradelySystemOrange)
                }
                .font(.gradely(.footnote))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                DetailSectionHeader(title: "settings.linkedDevices.activeSection")
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if viewModel.devices.isEmpty && !viewModel.isLoading {
                SettingsSurface {
                    HStack(spacing: Spacing.md) {
                        SettingsIcon(name: "laptop", color: .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.linkedDevices.empty.title")
                                .font(.gradely(.body).weight(.medium))
                            Text("settings.linkedDevices.empty.message")
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("linkedDevicesEmptyState")
            } else if !viewModel.devices.isEmpty {
                SettingsSurface(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.devices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 {
                                SettingsRowDivider()
                            }
                            deviceRow(device)
                        }
                    }
                }

                SettingsSurface(padding: 0) {
                    Button {
                        isRevokeAllConfirmationPresented = true
                    } label: {
                        SettingsActionRow(
                            title: "settings.linkedDevices.revokeAll.action",
                            iconName: "logout-01",
                            tint: .red,
                            accessory: viewModel.isRevokingAll ? .progress : .none
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRevokingAll)
                    .accessibilityIdentifier("linkedDevicesRevokeAllButton")
                }
            }
        }
    }

    private func deviceRow(_ device: LinkedWebDevice) -> some View {
        let isRevoking = viewModel.revokingDeviceIDs.contains(device.id)

        return VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack(alignment: .center, spacing: Spacing.md) {
                SettingsIcon(name: device.hugeiconName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: device.browserName)
                        .font(.gradely(.body).weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(verbatim: deviceSubtitle(device))
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRevoking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(role: .destructive) {
                        devicePendingRevoke = device
                    } label: {
                        Text("settings.linkedDevices.revoke.button")
                            .font(.gradely(.footnote).weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, Spacing.sm + 2)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("linkedDeviceRevoke-\(device.id)")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(AppL10n.string("settings.linkedDevices.firstLogin")) · \(formattedTimestamp(device.firstLoginAt))")
                Text(verbatim: "\(AppL10n.string("settings.linkedDevices.lastActive")) · \(formattedTimestamp(device.lastActiveAt))")
            }
            .font(.gradely(.caption2).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.leading, SettingsIcon.frameSize + Spacing.md)
        }
        .settingsRowInsets(vertical: Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("linkedDeviceRow-\(device.id)")
    }

    private func deviceSubtitle(_ device: LinkedWebDevice) -> String {
        var parts = [device.osName]
        if let school = device.schoolName, !school.isEmpty {
            parts.append(school)
        } else if !device.studentName.isEmpty {
            parts.append(device.studentName)
        }
        return parts.joined(separator: " · ")
    }

    private func formattedTimestamp(_ date: Date) -> String {
        "\(SchoolDateFormatting.shortDate(date)) \(date.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Pairing Confirmation Sheet

private struct LinkWebDeviceConfirmationSheet: View {
    let approval: LinkedDevicesViewModel.PendingApproval
    let schoolSummary: String?
    let isApproving: Bool
    let errorMessage: String?
    let onApprove: () async -> Void
    let onCancel: () async -> Void

    var body: some View {
        ModalNavigationContainer {
            ZStack {
                SettingsBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        SettingsModalHeader(title: "settings.linkedDevices.confirm.title") {
                            Task { await onCancel() }
                        }

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(Brand.primary.opacity(0.14))
                                        .frame(width: 52, height: 52)
                                    GradelyIcon("laptop-phone-sync", size: 24)
                                        .foregroundStyle(Brand.primary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: approval.preview.browserName)
                                        .font(.gradely(.title3).weight(.bold))
                                    Text(verbatim: approval.preview.osName)
                                        .font(.gradely(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        SettingsSurface {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                SettingsValueRow(
                                    title: "settings.linkedDevices.confirm.browser",
                                    value: approval.preview.browserName
                                )
                                Divider()
                                SettingsValueRow(
                                    title: "settings.linkedDevices.confirm.os",
                                    value: approval.preview.osName
                                )
                                if let schoolSummary, !schoolSummary.isEmpty {
                                    Divider()
                                    SettingsValueRow(
                                        title: "settings.linkedDevices.confirm.account",
                                        value: schoolSummary
                                    )
                                }
                            }
                        }

                        Label {
                            Text("settings.linkedDevices.confirm.securityNote")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            GradelyIcon("security-check", size: 16)
                                .foregroundStyle(Brand.primary)
                        }
                        .font(.gradely(.footnote))
                        .foregroundStyle(.secondary)

                        if let errorMessage, !errorMessage.isEmpty {
                            Label {
                                Text(verbatim: errorMessage)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                GradelyIcon("alert-circle", size: 15)
                                    .foregroundStyle(.red)
                            }
                            .font(.gradely(.footnote))
                            .foregroundStyle(.red)
                        }

                        VStack(spacing: Spacing.md) {
                            Button {
                                Task { await onApprove() }
                            } label: {
                                if isApproving {
                                    ProgressView()
                                        .tint(Brand.onAccent)
                                } else {
                                    Text("settings.linkedDevices.confirm.approve")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isApproving)
                            .accessibilityIdentifier("approveWebDeviceButton")

                            Button {
                                Task { await onCancel() }
                            } label: {
                                Text("action.cancel")
                                    .font(.gradely(.subheadline).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: ControlMetrics.minHeight)
                            }
                            .buttonStyle(.plain)
                            .disabled(isApproving)
                            .accessibilityIdentifier("cancelWebDeviceButton")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
            .settingsModalNavigationChrome()
        }
        .gradelyMacSheetSize(minWidth: 440, idealWidth: 480, minHeight: 460, idealHeight: 540)
    }
}

// MARK: - QR Camera Scanner Sheet

private struct QRDeviceScannerSheet: View {
    let onScan: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss

    #if os(iOS)
    @State private var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isProcessingCode = false
    @State private var scanError: String?
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                SettingsBackground()
                scannerContent
            }
            .navigationTitle("settings.linkedDevices.linkAction")
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        #if os(iOS)
        switch authorizationStatus {
        case .authorized:
            ZStack {
                QRCameraPreviewView(isPaused: isProcessingCode) { code in
                    guard !isProcessingCode else { return }
                    isProcessingCode = true
                    scanError = nil
                    Task {
                        let accepted = await onScan(code)
                        if !accepted {
                            scanError = AppL10n.string("settings.linkedDevices.error.invalidQR")
                            try? await Task.sleep(for: .seconds(1.2))
                            isProcessingCode = false
                        }
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    Spacer()

                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(Brand.primary, lineWidth: 3)
                        .frame(width: 248, height: 248)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                                .fill(Color.black.opacity(0.08))
                        )

                    VStack(spacing: Spacing.xs) {
                        if isProcessingCode {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(scanError ?? AppL10n.string("settings.linkedDevices.scanner.hint"))
                            .font(.gradely(.subheadline).weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.black.opacity(0.62), in: Capsule())
                    }

                    Spacer()
                }
                .padding(Spacing.xl)
            }
        case .notDetermined:
            VStack(spacing: Spacing.lg) {
                ProgressView()
                Text("settings.linkedDevices.scanner.requesting")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorizationStatus = granted ? .authorized : .denied
            }
        case .denied, .restricted:
            VStack(spacing: Spacing.lg) {
                GradelyIcon("camera-01", size: 32)
                    .foregroundStyle(.secondary)
                Text("settings.linkedDevices.scanner.deniedTitle")
                    .font(.gradely(.headline))
                Text("settings.linkedDevices.scanner.deniedMessage")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                Button("settings.notifications.permission.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.primary)
            }
            .padding(Spacing.xl)
        @unknown default:
            EmptyView()
        }
        #else
        VStack(spacing: Spacing.md) {
            GradelyIcon("smart-phone-01", size: 28)
                .foregroundStyle(.secondary)
            Text("settings.linkedDevices.macHint")
                .font(.gradely(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(Spacing.xl)
        }
        #endif
    }
}

#if os(iOS)
private struct QRCameraPreviewView: UIViewControllerRepresentable {
    let isPaused: Bool
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onCodeScanned = onCodeScanned
        uiViewController.setPaused(isPaused)
    }
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isPaused = false
    private let sessionQueue = DispatchQueue(label: "com.bukovinafilip.Gradely.qrscanner")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    private func configureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput)
        else {
            return
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else { return }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
            metadataOutput.metadataObjectTypes = [.qr]
        }

        captureSession.startRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              readable.type == .qr,
              let stringValue = readable.stringValue
        else {
            return
        }
        onCodeScanned?(stringValue)
    }
}
#endif
