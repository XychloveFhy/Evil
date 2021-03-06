//
//  Recognizer.swift
//  Evil iOS
//
//  Created by Gix on 1/26/18.
//  Copyright © 2018 Gix. All rights reserved.
//

import Foundation
import CoreGraphics
import CoreImage
import CoreML

/// 那些类型可以识别
public protocol Recognizable {
    var croppedMaxRectangle: CorpMaxRectangleResult { get }
}

extension CIImage: Recognizable {
    public var croppedMaxRectangle: CorpMaxRectangleResult {
        return preprocessor.croppedMaxRectangle()
    }
}

public typealias Processor = (Recognizable) -> CIImage?

public enum Recognizer {
    
    case chineseIDCard
    case custom(name: String, model: URL, needComplie: Bool, processor: Processor?) // local complied model url
    
    static func modelBaseURL(_ name: String) -> URL {
       let info = Bundle.main.infoDictionary
        guard let baseURL = (info?["Evil"] as? [String: String])?[name] else {
            fatalError("please set `EvilModelBaseURL` in `info.plist`")
        }
        guard let url = URL(string: baseURL) else {
            fatalError("please double check \(name)'s download url: \(baseURL)")
        }
        return url
    }
    
    static let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
    static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] as URL
    
    var needComplie: Bool {
        if case .custom(_, _, let needComplie, _) = self {
            return needComplie
        }
        return true
    }
    
    public var name: String {
        switch self {
        case .chineseIDCard:
            return "ChineseIDCard"
        case .custom(let name, _, _, _):
            return name
        }
    }
    
    // 未编译的model 下载地址
    var modelURL: URL? {
        if case .custom(_, let url, let needComplie, _) = self {
            return needComplie ? url : nil
        }
        return Recognizer.modelBaseURL(name)
    }
    
    // 已经编译好的model 可以直接使用
    var modelcURL: URL {
        if case .custom(_, let url, let needComplie, _) = self, !needComplie {
            return url
        }
        return Recognizer.documentURL.appendingPathComponent("evil/\(name).mlmodelc")
    }
    
    var existModel: Bool {
        return (try? MLModel(contentsOf: modelcURL)) != nil
    }
    
    var processor: Processor? {
        switch self {
        case .chineseIDCard:
            return Recognizer.cropChineseIDCardNumberArea
        case .custom(_, _, _, let processor):
            return processor
        }
    }
    
    public static func cropChineseIDCardNumberArea(_ object: Recognizable) -> CIImage? {
        return object.croppedMaxRectangle
            .correctionByFace()
            .cropChineseIDCardNumberArea()
            .process().value?.image
    }
    
    ///   从默认的地址下载深度学习模型，并更新
    ///
    /// - parameter force: 若本地存在模型文件，是否强制更新
    ///
    public func dowloadAndUpdateModel(force: Bool = false) throws {
        guard needComplie else { return }
        guard !existModel || !force else {
            return
        }
        guard let url = modelURL else {
            fatalError("no model download url for: \(self)")
        }
        let data = try Data(contentsOf: url)
        let cachedModel = Recognizer.cacheURL.appendingPathComponent(name)
        try data.write(to: cachedModel)
        try update(model: cachedModel)
        try FileManager.default.removeItem(at: cachedModel) // remove cache file
    }
    
    /// 用指定的文件更新本地深度学习模型
    ///
    /// - parameter source: 新的, 未编译的模型文件地址
    ///
    public func update(model source: URL) throws {
        let comiledURL = try MLModel.compileModel(at: source)

        try? FileManager.default.removeItem(at: modelcURL) // if exits remove it.
        let path = modelcURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: comiledURL, to: modelcURL)
        
        debugPrint("[Recognizer] model \(name) compile succeed")
    }
}

extension Evil {
    
    public func recognize(_ object: Recognizable, placeholder: String = "?") -> String? {
        if let images = recognizer.processor?(object)?.preprocessor.divideText().value?.map({ $0.image }) {
            return try? prediction(images).map { $0 ?? placeholder }.joined()
        }
        return nil
    }
}

public extension Valueable where T == Value {
    public func cropChineseIDCardNumberArea() -> Result<Value> {
        guard let image = value?.image else {
            return .failure(.notFound)
        }
        return .success(image.cropChineseIDCardNumberArea())
    }
}

public extension CIImage {
    public func cropChineseIDCardNumberArea() -> Value {
        // 截取 数字区
        // 按照真实比例截取，身份证号码区
        let x = extent.width * 0.33
        let y = extent.height * 0
        let w = extent.width * 0.63
        let h = extent.height * 0.25
        let rect = CGRect(x: x, y: y, width: w, height: h)
        return Value(cropped(to: rect).transformed(by: CGAffineTransform(translationX: -x, y: -y)), rect)
    }
}

