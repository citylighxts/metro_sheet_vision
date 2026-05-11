import Flutter
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let processor = OMRProcessor()
    private var omrChannel: FlutterMethodChannel?
    private var pendingScanResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        GeneratedPluginRegistrant.register(with: self)

        let messenger = registrar(forPlugin: "OMRChannel")!.messenger()
        omrChannel = FlutterMethodChannel(
            name: "com.hana.metro_sheet_vision/omr",
            binaryMessenger: messenger
        )
        omrChannel?.setMethodCallHandler { [weak self] call, flutterResult in
            guard let self else { return }
            switch call.method {
            case "analyzeSheet":  handleAnalyzeSheet(call: call, result: flutterResult)
            case "scanDocument":  handleScanDocument(result: flutterResult)
            default:              flutterResult(FlutterMethodNotImplemented)
            }
        }

        return result
    }

    private func handleAnalyzeSheet(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let args      = call.arguments as? [String: Any],
            let imagePath = args["imagePath"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGS", message: "imagePath is required", details: nil))
            return
        }

        processor.analyze(imagePath: imagePath) { outcome in
            DispatchQueue.main.async {
                switch outcome {
                case .success(let json): result(json)
                case .failure(let err):  result(FlutterError(code: "OMR_ERROR", message: err.localizedDescription, details: nil))
                }
            }
        }
    }

    private func handleScanDocument(result: @escaping FlutterResult) {
        guard VNDocumentCameraViewController.isSupported else {
            result(FlutterError(code: "UNSUPPORTED", message: "Document scanner not available on this device", details: nil))
            return
        }

        guard pendingScanResult == nil else {
            result(FlutterError(code: "BUSY", message: "A scan is already in progress", details: nil))
            return
        }

        pendingScanResult = result

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        else {
            pendingScanResult = nil
            result(FlutterError(code: "NO_VC", message: "Cannot find root view controller", details: nil))
            return
        }
        rootVC.present(scanner, animated: true)
    }
}

extension AppDelegate: VNDocumentCameraViewControllerDelegate {

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)

        guard scan.pageCount > 0 else {
            pendingScanResult?(FlutterError(code: "NO_PAGES", message: "No pages scanned", details: nil))
            pendingScanResult = nil
            return
        }

        let image  = scan.imageOfPage(at: 0)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        if let data = image.jpegData(compressionQuality: 0.92) {
            do {
                try data.write(to: tmpURL)
                pendingScanResult?(tmpURL.path)
            } catch {
                pendingScanResult?(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
            }
        } else {
            pendingScanResult?(FlutterError(code: "ENCODE_FAILED", message: "Could not encode scanned image", details: nil))
        }
        pendingScanResult = nil
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        pendingScanResult?(nil)
        pendingScanResult = nil
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
        pendingScanResult?(FlutterError(code: "SCAN_FAILED", message: error.localizedDescription, details: nil))
        pendingScanResult = nil
    }
}
