//
//  Silero.swift
//  iTourOffline
//
//  Created by Rain on 2024/4/15.
//

import Foundation
import onnxruntime_objc

struct VadOptions {
    var threshold: Float = 0.35
    var minSilenceDurationMs: Float = 0.6
    var minSpeechDurationMs: Float = 0.25
    var maxSpeechDurationS: Float = 20
    var speechPadMs: Float = 0.2
    var windowSizeSamples: Int = 512
}

let vadOptions = VadOptions()

class SpeechProcesser{
    
    var triggered = false
    
    var audios = [Float]()
    //    var min_silence_duration : Float = 0.2
    //    var pad_silence_duration : Float = 0.25
    //    var min_voice_duration : Float = 1.5
    //    var max_voice_duration : Float = 30.0
    var threshold : Float = vadOptions.threshold
    var negThreshold : Float = vadOptions.threshold
    
    var org_min_silence_duration : Float = vadOptions.minSilenceDurationMs
    var min_voice_duration : Float = vadOptions.minSpeechDurationMs
    var max_voice_duration : Float = vadOptions.maxSpeechDurationS
    var pad_silence_duration : Float = vadOptions.speechPadMs
    
    var min_silence_duration : Float = vadOptions.minSilenceDurationMs
    
    
    var last_start_time : Float = 0
    var last_end_time : Float = 0
    var start_time : Float = 0
    var temp_end : Float = 0
    var real_end : Float = 0
    var temp_real_end : Float = 0
    var real_start_time : Float = 0

    
    var callback : (([Float])->())?
    
    init(){
        min_silence_duration = org_min_silence_duration
    }
    
    
    func formatTime(ms:Float) -> String{
        let hour = Int(ms) / 3600
        let min = Int(ms) % 3600 / 60
        let sec = Int(ms) % 60
        let ms = Int(ms * 1000) % 1000
        
        return String.init(format: "[%d:%d:%d]", min,sec,ms)
    }
    
    func realEnd(start:Float,end:Float){
        let startIndex = Int(start * 16000)
        let endIndex = Int(end * 16000)
        
        let audio = Array(self.audios[startIndex..<endIndex])
        
        self.callback?(audio)
        print("start\(formatTime(ms: start))------>end\(formatTime(ms: end))")
    }
    
    
    func getWave()->[Float]{
        let startIndex = Int(start_time * 16000)
        let endIndex = Int(audios.count)
        
        if startIndex > 0 && startIndex < endIndex {
            let audio = Array(self.audios[startIndex..<endIndex])
            return audio
        }
        return []
    }
    
    
    func accept(speechProb:Float,audio:[Float]){
        audios += audio
        let current_time : Float = Float(audios.count) / 16000.0
        
//        print("accept(speechProb:\(speechProb) \(formatTime(ms: current_time))")
        
        // 检测到人声开始
        if speechProb > negThreshold && !triggered{
//            startIndex = max ((index - 6),0)
            //如果上次结束时间.
            let overTime = current_time - last_end_time
            if overTime > pad_silence_duration * 2{
                print("start 添加pading:\(formatTime(ms: current_time))")
                //下次开始 上一个确定了
                if real_end > 0{
                    last_end_time += pad_silence_duration
                    start_time = last_end_time
                }else{
                    start_time = max(current_time - pad_silence_duration,0)
                }
                
            }else{
                print("start 切割上一个end:\(formatTime(ms: current_time))")
//                start_time = last_end_time + overTime * 0.5
//                if real_end > 0{
//                    last_end_time = start_time
//                }
                /*
                   情况1.最小静音要求之后 取中间
                // 情况2.最长静音之后 静音已经延迟了(0.5 + 2 * 0.25) 够了0.25
                */
                //下次开始 上一个确定了
                
                if real_end > 0{
//                    start_time = last_end_time + (current_time - last_end_time) * 0.5
                    //TODO:--这里有些问题. 粘语音包
                    start_time = current_time - (overTime + min_silence_duration) * 0.5
                    last_end_time = start_time//last_end_time + (overTime) * 0.5
                }else{
                    start_time = max(current_time - pad_silence_duration,0)
                }
            }
            if real_end > 0{
                print("重新启动触发:\(formatTime(ms: current_time))")
                self.realEnd(start: last_start_time, end: last_end_time)
                real_end = 0
                temp_end = 0
                temp_real_end = 0
                negThreshold = threshold
                min_silence_duration = org_min_silence_duration
                
            }else{
                print("重新启动没有触发:\(formatTime(ms: current_time))")
            }
            real_start_time = current_time
            triggered = true
        }
        
        //检测到结束
        if speechProb < negThreshold && triggered{
            
            if temp_end == 0{
                temp_end = current_time
            }else{
                //但是有效音频长度太小
                if current_time - real_start_time < min_voice_duration{
//                    print("没有达到最小音频!!\(formatTime(ms: current_time))")
                    temp_end = 0
                }else{
                    if current_time - temp_end < min_silence_duration{
                        if current_time - temp_end > min_silence_duration * 0.5{
                            print("没有达到最小静音!!达到要求的一半\(formatTime(ms: current_time))")
                            temp_real_end = current_time
                        }
                    }else{
                        print("达到最小静音要求!!\(formatTime(ms: current_time))")
                        temp_end = current_time
                        real_end = temp_end
                        triggered = false
                        last_end_time = temp_end
                        last_start_time = start_time
                        temp_real_end = 0
//                        negThreshold = threshold - 0.15
                    }
                }
            }
        }
        
        //已经触发了停止但是延后一些处理到结束
        if speechProb < negThreshold && !triggered{
            //达到最大静音时间
            if real_end > 0 && current_time - real_end > pad_silence_duration * 3{
                print("达到最大静音要求!!\(formatTime(ms: current_time))")
                last_end_time = last_end_time + pad_silence_duration
                self.realEnd(start: last_start_time, end: last_end_time)
                temp_end = 0
                real_end = 0
                temp_real_end = 0
                negThreshold = threshold
                min_silence_duration = org_min_silence_duration
                start_time = -1
            }
        }
        
        //中间有音频活动时
        if speechProb > negThreshold && triggered{
            
            if real_end == 0{
                let duration = current_time - start_time
                let loss_voice_duration =  max_voice_duration
                let rate_duration = duration / loss_voice_duration
                
                //方式一: 使用缓入缓出函数
                do{
                    var loss_min_silence_duration = org_min_silence_duration * 0.95
                    var loss_negThreshold = 1.0 - threshold
                    
                    let rate = self.customEaseInOut(rate_duration)
                    loss_negThreshold = loss_negThreshold * rate
                    
                    negThreshold = threshold + loss_negThreshold
                    
                    loss_min_silence_duration = loss_min_silence_duration * rate
                    min_silence_duration = org_min_silence_duration - loss_min_silence_duration
                    
                    print("duaration:\(duration)--rate\(rate) min_silence\(min_silence_duration) --negThreshold\(negThreshold)")
                }
                
//                if rate_duration > 0.5{
//                    
//                    var loss_min_silence_duration = org_min_silence_duration * 0.85
//                    
//                    var loss_negThreshold = 0.9 - threshold
//                    let rate = self.customEaseOut(rate_duration)
//                    loss_negThreshold = loss_negThreshold * rate
//                    
//                    negThreshold = threshold + loss_negThreshold
//                    
//                    loss_min_silence_duration = loss_min_silence_duration * rate
//                    min_silence_duration = org_min_silence_duration - loss_min_silence_duration
//                    
//                    print("duaration:\(duration)--rate\(rate) min_silence\(min_silence_duration) --negThreshold\(negThreshold)")
//                }
            }
            
            if current_time - start_time > max_voice_duration - 2 * org_min_silence_duration - pad_silence_duration * 2{
                if real_end > 0{
                    print("达到最大音频要求!!符合最小静音\(formatTime(ms: last_end_time))")
                    last_end_time = real_end + min_silence_duration * 0.5
                    
                    self.realEnd(start: last_start_time, end: last_end_time)
                    real_end = 0
                    temp_end = 0
                    temp_real_end = 0
                    negThreshold = threshold
                    min_silence_duration = org_min_silence_duration
                    start_time = last_end_time - min_silence_duration
                    triggered = true
                    
                }else if temp_real_end > 0{
                    print("达到最大音频要求!!不符合最小静音\(formatTime(ms: last_end_time))")
                    last_end_time = temp_real_end
                    last_start_time = start_time
                    
                    self.realEnd(start: last_start_time, end: last_end_time)
                    real_end = 0
                    temp_end = 0
                    temp_real_end = 0
                    triggered = true
                    negThreshold = threshold
                    start_time = max(last_end_time - min_silence_duration * 0.5,0)
                    min_silence_duration = org_min_silence_duration
                    
                }else{
                    print("达到最大音频要求!!之前没有静音\(formatTime(ms: last_end_time))")
                    negThreshold = 1.2
                }
            }else{
                if temp_end > 0{
                    temp_end = 0
                }
            }
        }
    
    }

      
    func customEaseOut(_ input: Float,min:Float = 0.5,max:Float = 1.0) -> Float {
        // 输入检查，确保输入在 0.5 到 1 之间
        var input = input
        if input < min {input = min}
        if input > max {input = max}
        let t = (input - min) / (max - min)
        // 应用缓动函数
        return t == 1 ? 1 : 1 - pow(2, -10 * t)
    }
    
    func customEaseInOut(_ input: Float, min: Float = 0.0, max: Float = 1.0) -> Float {
        // 输入检查，确保输入在 min 到 max 之间
        var input = input
        if input < min { input = min }
        if input > max { input = max }
          
        // 归一化输入值到 0 到 1 之间
        let t = (input - min) / (max - min)
          
        // 使用五次多项式实现缓入缓出函数
        let easedValue: Float
        if t < 0.5 {
            easedValue = 16 * t * t * t * t * t
        } else {
            let f = ((2 * t) - 2)
            easedValue = 0.5 * f * f * f * f * f + 1
        }
          
        return easedValue
    }
    
}


class SileroVad {
    
    enum SileroVadError: Error {
        case Error(_ message: String)
    }
    

//    
    var voiceActivityDetector : SherpaOnnxVoiceActivityDetectorWrapper?

    init(modelName:String="silero_vad") {
        let silero_path = getResource(modelName, "onnx")
        
        let silero_config = SherpaOnnxSileroVadModelConfig.init(model: toCPointer(silero_path), threshold: 0.5, min_silence_duration: 0.2, min_speech_duration: 0.4, window_size: 512, max_speech_duration: 10)
        
        var config = SherpaOnnxVadModelConfig(silero_vad: silero_config, sample_rate: 16000, num_threads: 1, provider: toCPointer("coreml"), debug: 0)
        
        voiceActivityDetector = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 10)
        
    }
    func process(input:[Float]) throws -> Float? {
        let res = voiceActivityDetector?.vad(samples: input)
        return res
    }
    
//    private let ortEnv: ORTEnv
//    private let ortSession: ORTSession
//    private var hValue : ORTValue?
//    private var cValue : ORTValue?
//    private var srValue : ORTValue?
    
//    init(modelName:String="silero_vad",sample:Int=16000) throws{
//        
//        self.ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
//        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "onnx") else {
//          throw SileroVadError.Error("Failed to find model file.")
//        }
//        self.ortSession = try ORTSession(env: self.ortEnv, modelPath: modelPath, sessionOptions: nil)
//        
//        try self.initParams(sample: sample)
//    }
//    
//    func initParams(sample:Int=16000) throws{
//        let hData = Data.init(repeating: 0, count: 64 * 2 * 2 * 2)
//        let hShape: [NSNumber] = [2, 1, 64]
//        self.hValue = try ORTValue(
//          tensorData: NSMutableData(data: hData),
//          elementType: ORTTensorElementDataType.float,
//          shape: hShape)
//        
//        let cData = Data.init(repeating: 0, count: 64 * 2 * 2 * 2)
//        let cShape: [NSNumber] = [2, 1, 64]
//        self.cValue = try ORTValue(
//          tensorData: NSMutableData(data: cData),
//          elementType: ORTTensorElementDataType.float,
//          shape: cShape)
//        
//        var number: Int64 = Int64(sample)
//        let srdata = Data(bytes: &number, count: MemoryLayout<Int64>.size)
//        let srShape: [NSNumber] = []
//        self.srValue = try ORTValue(
//          tensorData: NSMutableData(data: srdata),
//          elementType: ORTTensorElementDataType.int64,
//          shape: srShape)
//    }
//    
//    func process(input:[Float]) throws -> Float? {
//        let data = Data(buffer: UnsafeBufferPointer(start: input, count: input.count))
//        let res = try self.process(input: data)
//        return res
//    }
//    
//    func process(input:Data) throws -> Float? {
//
//        let inputShape: [NSNumber] = [1, input.count / MemoryLayout<Float32>.stride as NSNumber]
//        let input = try ORTValue(
//          tensorData: NSMutableData(data: input),
//          elementType: ORTTensorElementDataType.float,
//          shape: inputShape)
//          
//        let outputs = try ortSession.run(
//            withInputs: ["input": input,"h":self.hValue!,"c":self.cValue!,"sr":self.srValue!],
//          outputNames: ["output","hn","cn"],
//          runOptions: nil)
//        
//        guard let hn = outputs["hn"] else {
//          throw SileroVadError.Error("Failed to get model output.")
//        }
//        self.hValue = hn
//        
//        guard let cn = outputs["cn"] else {
//          throw SileroVadError.Error("Failed to get model output.")
//        }
//        self.cValue = cn
//        
//        guard let output = outputs["output"] else {
//          throw SileroVadError.Error("Failed to get model output.")
//        }
//        let outputData = try output.tensorData() as Data
//        let numberFromData = outputData.withUnsafeBytes { $0.load(as: Float.self) }
//        return numberFromData
//    }
}



class SlieroVad {
    
    var model : SileroVad!
    var vadOptions : VadOptions!
    
//    var tail : [Float] = []
    
    var realChunk : [Float] = []
    var tempChunk : [Float] = []
    
    var speechProbs : [Float] = []
    
    var triggered = false
    var speeches: [[String: Int]] = []
    var currentSpeech: [String: Int] = [:]
//    var negThreshold = threshold - 0.15
    
    var tempEnd = 0
    var prevEnd = 0
    var nextStart = 0
    
    var speechProbIndex = 0
    
    var speechProcesser = SpeechProcesser()
    
    
    init(vadOptions:VadOptions? = nil,callback:(([Float])->())?) {
        
        if let vadOptions = vadOptions{
            self.vadOptions = vadOptions
        }else{
            self.vadOptions = VadOptions()
        }
        if ![512, 1024, 1536].contains(self.vadOptions.windowSizeSamples) {
            print("Unusual window_size_samples! Supported window_size_samples: - [512, 1024, 1536] for 16000 sampling_rate")
        }
        self.model = try! SileroVad()
        
        self.speechProcesser.callback = callback
    }
    
    func getWav()->[Float]{
        return speechProcesser.getWave()
    }
    
    func acceptWav(audio: [Float]){
        
        tempChunk = tempChunk + audio
        
        let audioLengthSamples = tempChunk.count
        let windowSizeSamples = vadOptions!.windowSizeSamples
        var tail : [Float] = []
        for currentStartSample in stride(from: 0, to: audioLengthSamples, by: windowSizeSamples) {
            let chunk = Array(tempChunk[currentStartSample..<min(currentStartSample + windowSizeSamples, audioLengthSamples)])
            if chunk.count < windowSizeSamples {
                tail = chunk
            }else{
                realChunk += chunk
                
                processTimestamp(audio: chunk)
                speechProbIndex += 1
                
            }
        }
        tempChunk = tail
    }
    
    func processTimestamp(audio: [Float]){
        let speechProb = try! model.process(input: audio)
//        let speechProb : Float? = 0.8
//        speechProbs.append(speechProb!)
        self.speechProcesser.accept(speechProb: speechProb!,audio: audio)
        
    }
    
    
    
    
    
    
    
    
    
    
    
    
    func speechStart()->[String:Int]?{
        if speeches.count > 0, let newStart = currentSpeech["start"] {
            var speech = speeches.last!
            let silenceDuration = newStart - speech["end"]!
            
            let speechPadMs = vadOptions!.speechPadMs
            let samplingRate : Float = 16000
            let speechPadSamples = samplingRate * speechPadMs / 1000
                        
            if silenceDuration < 2 * Int(speechPadSamples) {
                speech["end"]! += silenceDuration / 2
                currentSpeech["start"] = max(0, newStart - silenceDuration / 2)
            } else {
                speech["end"] = speech["end"]! + Int(speechPadSamples)
                currentSpeech["start"] = max(0, newStart - Int(speechPadSamples))
            }
            
            // 重置所有数据
            let arr = Array(realChunk[currentSpeech["start"]!...])
            
            let audio = Array(realChunk[speech["start"]!...speech["start"]!])
            speechFinal(audio: audio)
            
            speeches.removeAll()
            currentSpeech["start"] = 0
            
            return speech
        }
        return nil
    }
    
    func speechEnd(){
        if let speech = speeches.last {
            //TODO:---
//            let arr = Array(self.realChunk[end...])
//            self.realChunk = arr
        }
    }
    
    func speechFinal(audio:[Float]){
        let realAudio = Array(self.realChunk)
        let speech = self.speeches.last
        self.speeches.removeAll()
        
    }
    
    func preProcessSpeechProb(speechProb:Float){
        if speeches.count > 0{
            
        }
    }
    
    func processSpeechProb(speechProb:Float){
        
        let threshold = vadOptions!.threshold
        let minSpeechDurationMs = vadOptions!.minSpeechDurationMs
        let maxSpeechDurationS = vadOptions!.maxSpeechDurationS
        let minSilenceDurationMs = vadOptions!.minSilenceDurationMs
        let windowSizeSamples = vadOptions!.windowSizeSamples
        let speechPadMs = vadOptions!.speechPadMs
        
        let samplingRate : Float = 16000
        let minSpeechSamples = samplingRate * minSpeechDurationMs / 1000
        let speechPadSamples = samplingRate * speechPadMs / 1000
        let maxSpeechSamples : Int = Int(samplingRate) * Int(maxSpeechDurationS) - windowSizeSamples - 2 * Int(speechPadSamples)
        let minSilenceSamples = samplingRate * minSilenceDurationMs / 1000
        let minSilenceSamplesAtMaxSpeech = samplingRate * 98 / 1000
        
        var negThreshold = threshold - 0.15
        
        let i = speechProbIndex
        
        //
        if (speechProb >= threshold) && tempEnd != 0 {
            tempEnd = 0
            if nextStart < prevEnd {
                nextStart = windowSizeSamples * i
            }
        }
        
        if (speechProb >= threshold) && !triggered {
            triggered = true
            currentSpeech["start"] = windowSizeSamples * i
            self.speechStart()
            return;
        }
        
        if triggered && (windowSizeSamples * i - (currentSpeech["start"] ?? 0)) > Int(maxSpeechSamples) {
            //达到最大值,但是前面出现过很短的停顿
            if prevEnd != 0 {
                currentSpeech["end"] = prevEnd
                speeches.append(currentSpeech)
                currentSpeech = [:]
                
                //达到最大值,但是前面出现过很短的停顿,但是一直是静音
                if nextStart < prevEnd {
                    triggered = false
                } else {
                    //达到最大值,但是前面出现过很短的停顿,但是停顿后出现了人声
                    currentSpeech["start"] = nextStart
                }
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
            } else{
                //达到最大值,但是前面没有出现过停顿
                currentSpeech["end"] = windowSizeSamples * i
                speeches.append(currentSpeech)
                currentSpeech = [:]
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
                triggered = false
                self.speechEnd()
                return;
            }
        }
        
        if speechProb < negThreshold && triggered {
            if tempEnd == 0 {
                tempEnd = windowSizeSamples * i
            }
            // condition to avoid cutting in very short silence
            if (windowSizeSamples * i) - tempEnd > Int(minSilenceSamplesAtMaxSpeech) {
                prevEnd = tempEnd
            }
            if (windowSizeSamples * i) - tempEnd < Int(minSilenceSamples) {
//                continue
                print("silence to small")
            }
            else {
                currentSpeech["end"] = tempEnd
                if (currentSpeech["end"]! - currentSpeech["start"]!) > Int(minSpeechSamples) {
                    speeches.append(currentSpeech)
                }
                currentSpeech = [:]
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
                triggered = false
                
                self.speechEnd()
                
                return;
            }
        }
        
        if speechProb < negThreshold && !triggered {
            if speeches.count > 0{
                var speech = speeches.last!
                let end = speech["end"]!
                if (windowSizeSamples * i) - end > Int(speechPadSamples) {
                    speech["end"] = windowSizeSamples * i
                    speeches.removeAll()
                    speeches.append(speech)
                    //TODO:------
//                    self.speechFinal()
                }
            }
        }
        
        
        
    }
    
}


func getSpeechTimestamps(audio: [Float], vadOptions: VadOptions? = nil) -> [[String: Int]] {
    var vadOptions = vadOptions
    if vadOptions == nil {
        vadOptions = VadOptions()
    }
    
    let threshold = vadOptions!.threshold
    
    let minSpeechDurationMs = vadOptions!.minSpeechDurationMs
    let maxSpeechDurationS = vadOptions!.maxSpeechDurationS
    let minSilenceDurationMs = vadOptions!.minSilenceDurationMs
    let windowSizeSamples = vadOptions!.windowSizeSamples
    let speechPadMs = vadOptions!.speechPadMs
    
    if ![512, 1024, 1536].contains(windowSizeSamples) {
        print("Unusual window_size_samples! Supported window_size_samples: - [512, 1024, 1536] for 16000 sampling_rate")
    }
    
    let samplingRate : Float = 16000
    let minSpeechSamples = samplingRate * minSpeechDurationMs / 1000
    let speechPadSamples = samplingRate * speechPadMs / 1000
    let maxSpeechSamples : Int = Int(samplingRate) * Int(maxSpeechDurationS) - windowSizeSamples - 2 * Int(speechPadSamples)
    let minSilenceSamples = samplingRate * minSilenceDurationMs / 1000
    let minSilenceSamplesAtMaxSpeech = samplingRate * 98 / 1000
    
    let audioLengthSamples = audio.count
    
    let model = try! SileroVad()
    
    var speechProbs: [Float] = []
    for currentStartSample in stride(from: 0, to: audioLengthSamples, by: windowSizeSamples) {
        
        var chunk = Array(audio[currentStartSample..<min(currentStartSample + windowSizeSamples, audio.count)])
        if chunk.count < windowSizeSamples {
            chunk.append(contentsOf: Array(repeating: 0, count: windowSizeSamples - chunk.count))
        }
        let speechProb = try! model.process(input: chunk)
        speechProbs.append(speechProb!)
    }
    
    var triggered = false
    var speeches: [[String: Int]] = []
    var currentSpeech: [String: Int] = [:]
    let negThreshold = threshold - 0.15
    
    var tempEnd = 0
    var prevEnd = 0
    var nextStart = 0
    //
    for i in 0..<speechProbs.count {
        let speechProb = speechProbs[i]
        if (speechProb >= threshold) && tempEnd != 0 {
            tempEnd = 0
            if nextStart < prevEnd {
                nextStart = windowSizeSamples * i
            }
        }
        
        if (speechProb >= threshold) && !triggered {
            triggered = true
            currentSpeech["start"] = windowSizeSamples * i
            continue
        }
        
        if triggered && (windowSizeSamples * i - (currentSpeech["start"] ?? 0)) > Int(maxSpeechSamples) {
            if prevEnd != 0 {
                currentSpeech["end"] = prevEnd
                speeches.append(currentSpeech)
                currentSpeech = [:]
                if nextStart < prevEnd {
                    triggered = false
                } else {
                    currentSpeech["start"] = nextStart
                }
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
            } else{
                currentSpeech["end"] = windowSizeSamples * i
                speeches.append(currentSpeech)
                currentSpeech = [:]
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
                triggered = false
                continue
            }
        }
        
        if speechProb < negThreshold && triggered {
            if tempEnd == 0 {
                tempEnd = windowSizeSamples * i
            }
            // condition to avoid cutting in very short silence
            if (windowSizeSamples * i) - tempEnd > Int(minSilenceSamplesAtMaxSpeech) {
                prevEnd = tempEnd
            }
            if (windowSizeSamples * i) - tempEnd < Int(minSilenceSamples) {
                continue
            }
            else {
                currentSpeech["end"] = tempEnd
                if (currentSpeech["end"]! - currentSpeech["start"]!) > Int(minSpeechSamples) {
                    speeches.append(currentSpeech)
                }
                currentSpeech = [:]
                prevEnd = 0
                nextStart = 0
                tempEnd = 0
                triggered = false
                continue
            }
        }

    }
    
    if let start = currentSpeech["start"], audioLengthSamples - start > Int(minSpeechSamples) {
        currentSpeech["end"] = audioLengthSamples
        speeches.append(currentSpeech)
    }
      
    for i in 0..<speeches.count {
        var speech = speeches[i]
        if i == 0 {
            speech["start"] = max(0, speech["start"]! - Int(speechPadSamples))
        }
        if i != speeches.count - 1 {
            let silenceDuration = speeches[i + 1]["start"]! - speech["end"]!
            if silenceDuration < 2 * Int(speechPadSamples) {
                speech["end"]! += silenceDuration / 2
                speeches[i + 1]["start"] = max(0, speeches[i + 1]["start"]! - silenceDuration / 2)
            } else {
                speech["end"] = min(audioLengthSamples, speech["end"]! + Int(speechPadSamples))
                speeches[i + 1]["start"] = max(0, speeches[i + 1]["start"]! - Int(speechPadSamples))
            }
        } else {
            speech["end"] = min(audioLengthSamples, speech["end"]! + Int(speechPadSamples))
        }
    }
      
    return speeches

    
}

func getAudio(speechStamps:[[String: Int]], audio:[Float]) -> [Float]{
    var res = audio
    if !speechStamps.isEmpty{
        res = []
        for stamp in speechStamps {
            res += audio[stamp["start"]!...stamp["end"]!]
        }
    }
    return res
}
