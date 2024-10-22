import AVFoundation

class SpeakerDiarization {
    
    var sd : SherpaOnnxOfflineSpeakerDiarizationWrapper?
    
    func initModel(pynonoteModel:String = "model-pynonote.int8",
                   extractorModel:String = "3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k"){
        let segmentationModel = getResource(pynonoteModel,"onnx")
        let embeddingExtractorModel = getResource(extractorModel,"onnx")
        let numSpeakers = 3
        var config = sherpaOnnxOfflineSpeakerDiarizationConfig(
            segmentation: sherpaOnnxOfflineSpeakerSegmentationModelConfig(
                pyannote: sherpaOnnxOfflineSpeakerSegmentationPyannoteModelConfig(model: segmentationModel)),
            embedding: sherpaOnnxSpeakerEmbeddingExtractorConfig(model: embeddingExtractorModel,debug: 1),
            clustering: sherpaOnnxFastClusteringConfig(numClusters: numSpeakers)
        )
        sd = SherpaOnnxOfflineSpeakerDiarizationWrapper(config: &config)
    }
    
    func dearization(audio:[Float]) -> [SherpaOnnxOfflineSpeakerDiarizationSegmentWrapper]?{
        let start = Date()
        if let segments = self.sd?.process(samples: audio){
            let duration = Date().timeIntervalSince(start)
            print("============================\(duration)")
            for i in 0..<segments.count {
                print("\(segments[i].start) -- \(segments[i].end) speaker_\(segments[i].speaker)")
            }
            return segments
        }
        return nil
    }
    
    func run() {

        self.initModel()
        
        let waveFilename = getResource("0-four-speakers-zh","wav")
        
        let fileURL: NSURL = NSURL(fileURLWithPath: waveFilename)
        let audioFile = try! AVAudioFile(forReading: fileURL as URL)
        
        let audioFormat = audioFile.processingFormat
        assert(Int(audioFormat.sampleRate) == self.sd!.sampleRate)
        assert(audioFormat.channelCount == 1)
        assert(audioFormat.commonFormat == AVAudioCommonFormat.pcmFormatFloat32)
        
        let audioFrameCount = UInt32(audioFile.length)
        let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount)
        
        try! audioFile.read(into: audioFileBuffer!)
        let array: [Float]! = audioFileBuffer?.array()
        print("Started!")
        self.dearization(audio: array)
        
    }
}



//@main
//struct App {
//  static func main() {
//    run()
//  }
//}
