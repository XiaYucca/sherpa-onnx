//
//  SherpaOnnxManager.swift
//  iTourOffline
//
//  Created by Rain on 2024/6/11.
//

import AVFoundation
import Foundation


enum SentenceState : Int{
    case parital=0,final
}

enum ProcessFinalState : Int{
    case none=0,start=1,processing=2,end=3
}

struct Sentence {
    var id = ""
    var source = ""
    var target = ""
    var state : SentenceState = .parital
    var lan = ""
}

class SherpaOnnxManager {

    static let shared = SherpaOnnxManager()
    
    var audioEngine: AVAudioEngine? = nil
    var recognizer: SherpaOnnxRecognizer! = nil
    var offlinePunction: OfflinePunction! = nil
    
    var offlineRecognizer: SherpaOnnxOfflineRecognizer! = nil
    
    var voiceActivityDetector: SherpaOnnxVoiceActivityDetectorWrapper! = nil
    /// It saves the decoded results so far

    var lastSentence: String = ""
    
    var resultCallBack : ((_ state:Sentence)->())?
    
    var powerCallBack : ((_ power:Int)->())?
    
    var totalSamples =  [Float]()
    
    var lastSampleSecond : Int?
    var lastSampleIndex : Int?
    
    var lastText : String?
    var lastFinalTempText : String = ""
    var sameSegment = 0
    
    var transcribeQue = DispatchQueue(label: "transcribeQue")
    
    var lock = NSLock()
    
    var vad : SlieroVad!
    
    var isRuning = false
    
    func updateLabel() {
//        print("result:\(self.results)")
    }
    
    
    var isProcessFinal : ProcessFinalState = .none
    var lastParctialAudioCount : Int = 0
    var offline_vad_final_callback : ((_ item: Sentence)->())?
    
    var offline_vad_parctial_callback : ((_ item: Sentence)->())?
    
    var audioRecord : AudioRecorder!

    func start() {
        
        self.vad = SlieroVad(callback: { sample in
            self.isProcessFinal = .start
            let res = self.offlineRecognizer.decode(samples: sample)
            print("final:\(res.lang): \(self.lastFinalTempText)\(res.text)")
            var item = Sentence()
//            var lan = res.lang
//            lan = String(lan[lan.index(lan.startIndex, offsetBy: 2)..<lan.index(lan.startIndex, offsetBy: lan.count - 2)])
//            item.lan = lan
            item.source = res.text
            item.state = .final
            
            self.offline_vad_final_callback?(item)
            self.isProcessFinal = .end
            
        })

        initRecognizer(model: "sence")
//        initPunctuation()
        initRecorder()
//        initVoiceActivityDetector()

        
//        let start_time = Date().timeIntervalSince1970
//        let res = offlinePunction.addPunctuation(text: "hello are you ok how do you do")
//        print(res)
//        let duration = Date().timeIntervalSince1970 - start_time
//        print("duration \(duration)")
    }

    
    
    func initRecognizer(model:String = "sence") {
//        let modelConfig = getES()//getStreame1040MS()
        
        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80)
        
        switch model {
        case "sence":
            do{
                let modelConfig = sherpaOnnxOfflineSenseVoiceModelConfig(model: getResource("model.int8","onnx"),language: "zh",useInverseTextNormalization: true)
                
                let config = sherpaOnnxOfflineModelConfig(tokens: getResource("sense_tokens", "txt"),numThreads:2,provider: "coreml",debug:0, senseVoice: modelConfig)
                
                var offlineConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: config)
                
                offlineRecognizer = SherpaOnnxOfflineRecognizer(config: &offlineConfig)
            }
        case "nemo":
            do{
                
                let modelConfig = sherpaOnnxOfflineNemoEncDecCtcModelConfig(model:getResource("nemo_es_ctc_model","onnx") )
                
//                let modelConfig = sherpaOnnxOfflineTransducerModelConfig(
//                encoder: getResource("nemo_es_encoder","onnx"),
//                decoder: getResource("nemo_es_decoder","onnx"),
//                joiner: getResource("nemo_es_joiner","onnx")
//                )
//                
                let config = sherpaOnnxOfflineModelConfig(tokens: getResource("nemo_es_ctc_tokens", "txt"),nemoCtc:modelConfig,numThreads:2,provider: "coreml",debug:1 )
                
                var offlineConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: config)
                
                offlineRecognizer = SherpaOnnxOfflineRecognizer(config: &offlineConfig)
            }
        case "whisper":
            do{
                let modelConfig = sherpaOnnxOfflineWhisperModelConfig(encoder: getResource("tiny-encoder.int8","onnx"),decoder: getResource("tiny-decoder.int8","onnx"),language: "en")
                
                let config = sherpaOnnxOfflineModelConfig(tokens: getResource("tiny-tokens", "txt"),whisper: modelConfig,numThreads:1,provider: "cpu",debug:0,modelType: "whisper" )
                
                var offlineConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: featConfig, modelConfig: config)
                
                offlineRecognizer = SherpaOnnxOfflineRecognizer(config: &offlineConfig)
            }
        default:
            break
        }
        
//

//        
//        var config = sherpaOnnxOnlineRecognizerConfig(
//            featConfig: featConfig,
//            modelConfig: modelConfig,
//            enableEndpoint: true,
//            rule1MinTrailingSilence: 2.4,
//            rule2MinTrailingSilence: 0.8,
//            rule3MinUtteranceLength: 30,
//            decodingMethod: "greedy_search",
//            maxActivePaths: 4
//        )
//        
//        recognizer = SherpaOnnxRecognizer(config: &config)
         

    }
    
    func initPunctuation(){
        self.offlinePunction = OfflinePunction().createPunctuation()
    }
    
    func initVoiceActivityDetector(){
        let silero_path = getResource("silero_vad", "onnx")
        
        let silero_config = SherpaOnnxSileroVadModelConfig.init(model: toCPointer(silero_path), threshold: 0.5, min_silence_duration: 0.2, min_speech_duration: 0.4, window_size: 512, max_speech_duration: 10)

        var config = SherpaOnnxVadModelConfig(silero_vad: silero_config, sample_rate: 16000, num_threads: 1, provider: toCPointer("cpu"), debug: 0)
        
        self.voiceActivityDetector = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 10)
        
    }
    
    func runTranscribeQue(){
        while true{
            var count = self.totalSamples.count
            while count > 512{
                let poppedElements = Array(self.totalSamples.prefix(512))
                self.voiceActivityDetector.acceptWaveform(samples: poppedElements)
                self.lock.lock()
                self.totalSamples.removeFirst(512)
                count = self.totalSamples.count
                self.lock.unlock()
            }
            var hasFinal = false
            while !self.voiceActivityDetector.isEmpty(){
                
                if self.voiceActivityDetector.front().samples.count < Int(0.5 * 16000){
                    self.voiceActivityDetector.pop()
                    continue
                }
                let samples = self.voiceActivityDetector.front().samples
                self.voiceActivityDetector.pop()
                self.vad_recv(samples,isFinal: true)
                hasFinal = true
                self.lastSampleSecond = nil
                self.lastSampleIndex = nil
                
                print("===========================")
            }
            
            if !hasFinal{
                let segment = self.voiceActivityDetector.inspect()
                if segment.start > 0{
                    do{
                        if self.lastSampleIndex == nil {
                            self.lastSampleIndex = 0
                            self.lastText = ""
                            self.sameSegment = 0
                            self.lastFinalTempText = ""
                        }
                        if segment.samples.count - self.lastSampleIndex! > 1 * 16000{
                            
                            let subfix = segment.samples.count - self.lastSampleIndex!
                            
                            let samples = segment.samples
                            
                            
                            let appendSamples = Array(segment.samples[self.lastSampleIndex!...])
                            let res = self.offlineRecognizer.decode(samples: appendSamples)
                            print("parctial:\(res.lang): \(self.lastFinalTempText)\(res.text)")
                            
                            // 结果一样
                            if self.lastText == res.text{
                                self.sameSegment += 1
                                self.lastSampleSecond = segment.samples.count
                            }else{
                                self.sameSegment = 0
                            }
                            
                            if self.sameSegment >= 1{
                                self.lastSampleIndex = self.lastSampleSecond
                                self.sameSegment = 0
                                self.lastFinalTempText += res.text
                                print("++++++\(res.text)")
                            }
                            self.lastText = res.text
                            
                        }
                        else{
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                    }
                }else{
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
    }
    
    func initRecorder() {
        self.audioRecord = AudioRecorder(delegate: self,enablePower: true)
        self.audioRecord.requestAccess()
        self.audioRecord.initEngine()
    }

    func initRecorder2() {
        print("init recorder")
        
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted{
                
            }else{
                
            }
        }
        
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            let sampleRate = audioSession.sampleRate
            print("Supported sample rate: \(sampleRate)")
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        
        audioEngine = AVAudioEngine()
        let inputNode = self.audioEngine?.inputNode
        let bus = 0
        let inputFormat = inputNode?.outputFormat(forBus: bus)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1,
            interleaved: false)!

        let converter = AVAudioConverter(from: inputFormat!, to: outputFormat)!
        
        var speechData = Data()
        
        var lastSpeechData : [Float] = []

        inputNode!.installTap(
            onBus: bus,
            bufferSize: 1024,
            format: inputFormat
        ) {
            (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            var newBufferAvailable = true

            let inputCallback: AVAudioConverterInputBlock = {
                inNumPackets, outStatus in
                if newBufferAvailable {
                    outStatus.pointee = .haveData
                    newBufferAvailable = false

                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity:
                    AVAudioFrameCount(outputFormat.sampleRate)
                * buffer.frameLength
                / AVAudioFrameCount(buffer.format.sampleRate))!

            var error: NSError?
            let _ = converter.convert(
                to: convertedBuffer,
                error: &error, withInputFrom: inputCallback)

            // TODO(fangjun): Handle status != haveData

            let array = convertedBuffer.array()
            self.lock.lock()
            self.totalSamples = self.totalSamples + array
            self.lock.unlock()
//            
            
            self.vad.acceptWav(audio: array)
            
            
            
//            let data = convertedBuffer.floatChannelData![0]
//            let data = convertAVAudioPCMBufferToData(pcmBuffer: convertedBuffer) as! Data
//            
//            speechData.append(data)
            
//            if speechData.count >= 32000{
////                let tmp = data[0...10].map{String.init(format: " %02x", $0)}.joined()
////                print(tmp)
//                let power = SpeechDataToPowerFromFloat32(speechData)
//                self.powerCallBack?(Int(power))
//                print("power \(power)")
//                speechData = Data()
//                
//            }
            
            
            
            
//            if !array.isEmpty {
//                self.recognizer.acceptWaveform(samples: array)
//                while (self.recognizer.isReady()){
//                    self.recognizer.decode()
//                }
//                let isEndpoint = self.recognizer.isEndpoint()
//                var text = self.recognizer.getResult().text
//                
//                if !text.isEmpty && (self.lastSentence != text || isEndpoint) {
//                    
//                    self.lastSentence = text
//                    text = self.offlinePunction.addPunctuation(text: text) ?? text
//                    let semaphore = DispatchSemaphore(value: 0)
//                    var trans = text
//                    
//                    self.updateLabel()
//                    let state = Sentence(source: text,target: trans,state: isEndpoint ? .final: .parital)
//                    self.resultCallBack?(state)
//                    
//                    if isEndpoint {
//                        if !text.isEmpty {
//                            self.lastSentence = ""
//                        }
//                        self.recognizer.reset()
//                    }
//                }
//
//            }
        }

    }
    
    func vad_recv(_ samples:[Float] ,isFinal:Bool){
        let res = self.offlineRecognizer.decode(samples: samples)
        if isFinal{
            print("final:\(res.lang): \(res.text)")
        }else{
            print("parctial:\(res.lang): \(res.text)")
        }
        
    }

    func startRecorder() {
        lastSentence = ""

        do {
//            try self.audioEngine?.start()
            try self.audioRecord.start()
            self.isRuning = true
            transcribeQue.async {
                self.parctialQue()
            }
        } catch let error as NSError {
            print("Got an error starting audioEngine: \(error.domain), \(error)")
        }
        print("started")
        
    }
    
    func parctialQue(){
        
        while self.isRuning {
            Thread.sleep(forTimeInterval: 0.5)
            let sample = self.vad.getWav()
            
            if sample.count == 0  {
                continue
            }

            if self.isProcessFinal != .none {
                if self.isProcessFinal == .end{
                    self.isProcessFinal = .none
                }

                continue
            }
            let res = self.offlineRecognizer.decode(samples: sample)
            
            if self.isProcessFinal != .none {
                if self.isProcessFinal == .end{
                    self.isProcessFinal = .none
                }

                continue
            }
            
            print("final 0:\(res.lang): \(self.lastFinalTempText)\(res.text)")
            
            var item = Sentence()
            
//            var lan = res.lang
//            lan = String(lan[lan.index(lan.startIndex, offsetBy: 2)..<lan.index(lan.startIndex, offsetBy: lan.count - 2)])
//            item.lan = lan
            item.source = res.text
            
            if self.isProcessFinal != .none {
                if self.isProcessFinal == .end{
                    self.isProcessFinal = .none
                }

                continue
            }
            self.offline_vad_parctial_callback?(item)
        }
        
    }

    func stopRecorder() {
//        audioEngine?.stop()
        self.audioRecord.stop()
        self.isRuning = false
        print("stopped")
    }
}


import AVFoundation
  
func convertAVAudioPCMBufferToData(pcmBuffer: AVAudioPCMBuffer) -> Data? {
    guard let floatChannelData = pcmBuffer.floatChannelData else {
        return nil
    }
  
    let channelCount = Int(pcmBuffer.format.channelCount)
    let frameLength = Int(pcmBuffer.frameLength)
  
    var data = Data(capacity: channelCount * frameLength * MemoryLayout<Float>.size)
  
    for channel in 0..<channelCount {
        let channelDataPointer = floatChannelData[channel]
        let channelDataBuffer = UnsafeBufferPointer(start: channelDataPointer, count: frameLength)
        data.append(channelDataBuffer)
    }
    
    return data
}
extension SherpaOnnxManager : AudioRecorderDelegate{
    func audioDidRev(audio: [Float], power: Int?) {
        print("power \(power!)")
        self.vad.acceptWav(audio: audio)
    }
    
    
}
