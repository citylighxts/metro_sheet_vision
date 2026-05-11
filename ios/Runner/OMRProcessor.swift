import CoreML
import UIKit
import Vision

private let OMR_LABELS: [String] = [
    "noteheadFull",
    "noteheadHalf",
    "accidentalFlat",
    "accidentalNatural",
    "accidentalSharp",
]

enum OMRError: LocalizedError {
    case imageLoadFailed(String)
    case unexpectedOutputFormat(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let path):     return "Cannot decode image at path: \(path)"
        case .unexpectedOutputFormat(let d): return "Unrecognised CoreML output: \(d)"
        }
    }
}

private struct Detection {
    let xCenter:    Float
    let yCenter:    Float
    let width:      Float
    let height:     Float
    let confidence: Float
    let classIndex: Int

    var normRect: CGRect {
        CGRect(x: CGFloat(xCenter - width / 2), y: CGFloat(yCenter - height / 2),
               width: CGFloat(width), height: CGFloat(height))
    }

    func remapped(tileRect: CGRect, imageSize: CGSize) -> Detection {
        let sx = Float(tileRect.width  / imageSize.width)
        let sy = Float(tileRect.height / imageSize.height)
        let ox = Float(tileRect.minX   / imageSize.width)
        let oy = Float(tileRect.minY   / imageSize.height)
        return Detection(xCenter:    xCenter * sx + ox,
                         yCenter:    yCenter * sy + oy,
                         width:      width   * sx,
                         height:     height  * sy,
                         confidence: confidence,
                         classIndex: classIndex)
    }
}

final class OMRProcessor {

    private let visionModel:          VNCoreMLModel?
    private let confidenceThreshold:  Float  = 0.25
    private let iouThreshold:         Float  = 0.45
    private let tilePx:               Int    = 640
    private let maxInputDim:          Int    = 2_048
    private let tileOverlap:          Double = 0.15

    init() {
        if let url     = Bundle.main.url(forResource: "MetroSheetOMR", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: url),
           let wrapped = try? VNCoreMLModel(for: mlModel) {
            visionModel = wrapped
        } else {
            visionModel = nil
        }
    }

    func analyze(imagePath: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let cgImage = UIImage(contentsOfFile: imagePath)?.cgImage else {
                completion(.failure(OMRError.imageLoadFailed(imagePath)))
                return
            }

            guard let model = visionModel else {
                completion(.success(stubJSON()))
                return
            }

            let src  = prescale(cgImage) ?? cgImage
            let imgW = src.width
            let imgH = src.height

            if imgW > tilePx || imgH > tilePx {
                analyzeTiled(cgImage: src, imgW: imgW, imgH: imgH, model: model, completion: completion)
            } else {
                analyzeWhole(cgImage: src, model: model, completion: completion)
            }
        }
    }

    private func analyzeTiled(
        cgImage: CGImage, imgW: Int, imgH: Int,
        model: VNCoreMLModel,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let origins  = tileOrigins(imageWidth: imgW, imageHeight: imgH)
        let imgSize  = CGSize(width: imgW, height: imgH)
        var allDets  = [Detection]()
        let lock     = NSLock()
        let group    = DispatchGroup()
        var firstErr: Error?

        for (ox, oy) in origins {
            let pw       = min(tilePx, imgW - ox)
            let ph       = min(tilePx, imgH - oy)
            let tileRect = CGRect(x: ox, y: oy, width: pw, height: ph)
            guard let tile = cgImage.cropping(to: tileRect) else { continue }

            group.enter()
            detectFromImage(cgImage: tile, model: model) { result in
                defer { group.leave() }
                switch result {
                case .success(let dets):
                    let remapped = dets.map { $0.remapped(tileRect: tileRect, imageSize: imgSize) }
                    lock.lock(); allDets.append(contentsOf: remapped); lock.unlock()
                case .failure(let err):
                    lock.lock(); if firstErr == nil { firstErr = err }; lock.unlock()
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self else { return }
            if let err = firstErr { completion(.failure(err)); return }
            completion(.success(toJSONString(applyNMS(allDets).map(toDict))))
        }
    }

    private func analyzeWhole(
        cgImage: CGImage, model: VNCoreMLModel,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        detectFromImage(cgImage: cgImage, model: model) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let dets): completion(.success(toJSONString(applyNMS(dets).map(toDict))))
            case .failure(let err):  completion(.failure(err))
            }
        }
    }

    private func detectFromImage(
        cgImage: CGImage, model: VNCoreMLModel,
        completion: @escaping (Result<[Detection], Error>) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak self] req, error in
            guard let self else { return }
            if let error { completion(.failure(error)); return }

            if let obs = req.results as? [VNRecognizedObjectObservation], !obs.isEmpty {
                completion(.success(detectionsFromObservations(obs)))
                return
            }

            if let features = req.results as? [VNCoreMLFeatureValueObservation] {
                do    { completion(.success(try detectionsFromFeatures(features))) }
                catch { completion(.failure(error)) }
                return
            }

            completion(.success([]))
        }
        request.usesCPUOnly             = false
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do    { try handler.perform([request]) }
        catch { completion(.failure(error)) }
    }

    private func detectionsFromObservations(_ obs: [VNRecognizedObjectObservation]) -> [Detection] {
        obs.compactMap { o in
            guard let lbl = o.labels.first, lbl.confidence >= confidenceThreshold else { return nil }
            let idx = OMR_LABELS.firstIndex(of: lbl.identifier) ?? 0
            let box = o.boundingBox
            return Detection(
                xCenter:    Float(box.origin.x + box.width  / 2),
                yCenter:    Float(1.0 - box.origin.y - box.height / 2),
                width:      Float(box.width),
                height:     Float(box.height),
                confidence: lbl.confidence,
                classIndex: idx)
        }
    }

    private func detectionsFromFeatures(_ features: [VNCoreMLFeatureValueObservation]) throws -> [Detection] {
        guard let arr = features
            .compactMap({ $0.featureValue.multiArrayValue })
            .max(by: { $0.count < $1.count })
        else { return [] }
        return try detectionsFromMultiArray(arr)
    }

    private func detectionsFromMultiArray(_ array: MLMultiArray) throws -> [Detection] {
        let shape = array.shape.map { $0.intValue }
        if shape.count == 3, shape[2] == 6 { return try postNMSTensor(array, shape: shape) }
        if shape.count == 3, shape[0] == 1, shape[1] >= 5 { return try preNMSTensor(array, shape: shape) }
        throw OMRError.unexpectedOutputFormat("Unrecognised tensor shape: \(shape)")
    }

    private func postNMSTensor(_ array: MLMultiArray, shape: [Int]) throws -> [Detection] {
        let n = shape[1]
        var dets = [Detection]()
        array.withUnsafeBytes { buf in
            let ptr = buf.bindMemory(to: Float.self).baseAddress!
            for i in 0 ..< n {
                let b    = i * 6
                let conf = ptr[b + 4]
                guard conf >= confidenceThreshold else { continue }
                dets.append(Detection(xCenter: ptr[b], yCenter: ptr[b+1],
                                      width: ptr[b+2], height: ptr[b+3],
                                      confidence: conf, classIndex: Int(ptr[b+5])))
            }
        }
        return dets
    }

    private func preNMSTensor(_ array: MLMultiArray, shape: [Int]) throws -> [Detection] {
        let nCh = shape[1]; let nA = shape[2]; let nC = nCh - 4
        guard nC > 0 else { throw OMRError.unexpectedOutputFormat("nCh=\(nCh) has no classes") }
        guard array.dataType == .float32 else { return try preNMSFallback(array, shape: shape) }

        var cands = [Detection]()
        array.withUnsafeBytes { buf in
            let ptr = buf.bindMemory(to: Float.self).baseAddress!
            for a in 0 ..< nA {
                var bC = 0; var bS: Float = 0
                for c in 0 ..< nC {
                    let s = ptr[(4 + c) * nA + a]
                    if s > bS { bS = s; bC = c }
                }
                guard bS >= confidenceThreshold else { continue }
                cands.append(Detection(xCenter: ptr[0*nA+a], yCenter: ptr[1*nA+a],
                                       width:   ptr[2*nA+a], height:  ptr[3*nA+a],
                                       confidence: bS, classIndex: bC))
            }
        }
        return applyNMS(cands)
    }

    private func preNMSFallback(_ array: MLMultiArray, shape: [Int]) throws -> [Detection] {
        let nCh = shape[1]; let nA = shape[2]; let nC = nCh - 4
        var cands = [Detection]()
        for a in 0 ..< nA {
            var bC = 0; var bS: Float = 0
            for c in 0 ..< nC {
                let s = Float(truncating: array[[0, 4+c, a] as [NSNumber]])
                if s > bS { bS = s; bC = c }
            }
            guard bS >= confidenceThreshold else { continue }
            cands.append(Detection(
                xCenter: Float(truncating: array[[0,0,a] as [NSNumber]]),
                yCenter: Float(truncating: array[[0,1,a] as [NSNumber]]),
                width:   Float(truncating: array[[0,2,a] as [NSNumber]]),
                height:  Float(truncating: array[[0,3,a] as [NSNumber]]),
                confidence: bS, classIndex: bC))
        }
        return applyNMS(cands)
    }

    private func prescale(_ image: CGImage) -> CGImage? {
        let w = image.width; let h = image.height
        guard max(w, h) > maxInputDim else { return nil }
        let scale = CGFloat(maxInputDim) / CGFloat(max(w, h))
        let nw = max(1, Int(CGFloat(w) * scale))
        let nh = max(1, Int(CGFloat(h) * scale))
        guard let ctx = CGContext(data: nil, width: nw, height: nh,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    private func tileOrigins(imageWidth w: Int, imageHeight h: Int) -> [(x: Int, y: Int)] {
        let xs = stepOrigins(total: w, patchSize: min(tilePx, w))
        let ys = stepOrigins(total: h, patchSize: min(tilePx, h))
        return xs.flatMap { x in ys.map { y in (x: x, y: y) } }
    }

    private func stepOrigins(total: Int, patchSize: Int) -> [Int] {
        guard total > patchSize else { return [0] }
        let step = max(1, Int(Double(patchSize) * (1.0 - tileOverlap)))
        var origins = [Int]()
        var pos = 0
        while pos + patchSize < total {
            origins.append(pos)
            pos += step
        }
        let tail = total - patchSize
        if origins.last != tail { origins.append(tail) }
        return origins
    }

    private func applyNMS(_ detections: [Detection]) -> [Detection] {
        let sorted  = detections.sorted { $0.confidence > $1.confidence }
        var kept    = [Detection]()
        var removed = Set<Int>()
        for i in 0 ..< sorted.count {
            guard !removed.contains(i) else { continue }
            kept.append(sorted[i])
            for j in (i+1) ..< sorted.count {
                guard !removed.contains(j) else { continue }
                if iou(sorted[i].normRect, sorted[j].normRect) > iouThreshold { removed.insert(j) }
            }
        }
        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let i = Float(inter.width * inter.height)
        let u = Float(a.width * a.height + b.width * b.height) - i
        return u > 0 ? i / u : 0
    }

    private func toDict(_ d: Detection) -> [String: Any] {
        let label = d.classIndex < OMR_LABELS.count ? OMR_LABELS[d.classIndex] : "class_\(d.classIndex)"
        return ["label":      label,
                "confidence": Double(d.confidence),
                "normX":      Double(d.xCenter - d.width  / 2),
                "normY":      Double(d.yCenter - d.height / 2),
                "normWidth":  Double(d.width),
                "normHeight": Double(d.height)]
    }

    private func toJSONString(_ payload: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s    = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func stubJSON() -> String {
        let stubs: [[String: Any]] = [
            ["label": "noteheadFull",    "confidence": 0.96,
             "normX": 0.18, "normY": 0.20, "normWidth": 0.03, "normHeight": 0.06],
            ["label": "noteheadFull",    "confidence": 0.94,
             "normX": 0.28, "normY": 0.24, "normWidth": 0.03, "normHeight": 0.06],
            ["label": "accidentalSharp", "confidence": 0.95,
             "normX": 0.26, "normY": 0.21, "normWidth": 0.02, "normHeight": 0.08],
        ]
        return toJSONString(stubs)
    }
}

private extension MLMultiArray {
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) -> T) -> T {
        let ptr   = UnsafeRawPointer(dataPointer)
        let count = self.count * MemoryLayout<Float>.size
        return body(UnsafeRawBufferPointer(start: ptr, count: count))
    }
}
