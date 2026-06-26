import SwiftUI
import AVFoundation

// MARK: - Barcode Scanner
//
// A live camera barcode scanner used by the food diary's add-food flow to look up a
// packaged food in Open Food Facts. Wraps an `AVCaptureSession` configured for the
// common grocery symbologies and reports the first decoded code. Camera permission
// copy lives in Info.plist (`NSCameraUsageDescription`). Design-system styled chrome.

struct BarcodeScannerView: View {
    /// Called once with the decoded barcode string.
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didScan = false
    @State private var cameraDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraDenied {
                deniedState
            } else {
                BarcodeCameraView { code in
                    guard !didScan else { return }
                    didScan = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onScan(code)
                    dismiss()
                } onDenied: {
                    cameraDenied = true
                }
                .ignoresSafeArea()

                VStack {
                    header
                    Spacer()
                    reticle
                    Spacer()
                    Text("Point your camera at a barcode")
                        .font(PulseFont.body(13))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("SCAN BARCODE")
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(0.9), lineWidth: 2)
            .frame(width: 260, height: 150)
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.8))
            Text("Camera access needed")
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to scan barcodes.")
                .font(PulseFont.body(13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Close")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(32)
    }
}

// MARK: - AVFoundation preview

private struct BarcodeCameraView: UIViewRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        configureSession(view: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    private func configureSession(view: PreviewView, coordinator: Coordinator) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            coordinator.start(on: view)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { coordinator.start(on: view) } else { onDenied() }
                }
            }
        default:
            DispatchQueue.main.async { onDenied() }
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private let queue = DispatchQueue(label: "barcode.session")

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func start(on view: PreviewView) {
            queue.async { [weak self] in
                guard let self else { return }
                guard self.session.inputs.isEmpty else {
                    if !self.session.isRunning { self.session.startRunning() }
                    return
                }
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else { return }
                self.session.addInput(input)

                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else { return }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [
                    .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr,
                ]

                DispatchQueue.main.async {
                    view.previewLayer.session = self.session
                    view.previewLayer.videoGravity = .resizeAspectFill
                }
                self.session.startRunning()
            }
        }

        func stop() {
            queue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue, !value.isEmpty else { return }
            stop()
            onCode(value)
        }
    }
}
