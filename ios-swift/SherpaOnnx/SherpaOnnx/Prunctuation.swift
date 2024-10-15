//
//  Prunctuation.swift
//  SherpaOnnx
//
//  Created by Rain on 2024/6/7.
//

import Foundation

class OfflinePunction {
    
    var modelName : String = "model-punc"
    
    fileprivate var offlinePunctuation: OpaquePointer!
    
    func createPunctuation()->OfflinePunction{
        if offlinePunctuation == nil{
            let path = getResource(modelName, "onnx")
            let modelConfig = self.sherpaOnnxOfflinePunctuationModelConfig(path:path)
            var config = self.getPunctuationModel(config: modelConfig)
            let offlinePunctuation_pointer = SherpaOnnxCreateOfflinePunctuation(&config)
            offlinePunctuation = offlinePunctuation_pointer
        }
        return self
    }
    
    func destroyPunctuation()->OfflinePunction{
        if offlinePunctuation != nil{
            let pointer = offlinePunctuation
            SherpaOnnxDestroyOfflinePunctuation(pointer)
            offlinePunctuation = nil
        }
        return self
    }
    
    func addPunctuation(text:String)->String?{
        if let c_result = SherpaOfflinePunctuationAddPunct(offlinePunctuation, toCPointer(text)){
            return String(cString: c_result)
        }
        return nil
    }
    
    func sherpaOnnxOfflinePunctuationModelConfig(path:String)->SherpaOnnxOfflinePunctuationModelConfig
    {
        let ctTransformer = path
        let numThreads : Int32 = 2
        let debug : Int32 = 0
        let provider = "cpu"
        return SherpaOnnxOfflinePunctuationModelConfig(ct_transformer: toCPointer(ctTransformer), num_threads: numThreads, debug: debug, provider: toCPointer(provider))
    }
    
    func getPunctuationModel(config:SherpaOnnxOfflinePunctuationModelConfig)->SherpaOnnxOfflinePunctuationConfig{
        return SherpaOnnxOfflinePunctuationConfig(model: config)
    }

}
