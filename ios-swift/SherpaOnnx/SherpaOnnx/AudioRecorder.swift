//
//  AudioRecorder.swift
//  SherpaOnnx
//
//  Created by Rain on 2024/10/12.
//

import Foundation
import AVFAudio
import AVFoundation

extension AudioBuffer {
    func array() -> [Float] {
        return Array(UnsafeBufferPointer(self))
    }
}

extension AVAudioPCMBuffer {
    func array() -> [Float] {
        return self.audioBufferList.pointee.mBuffers.array()
    }
}

protocol AudioRecorderDelegate {
    func audioDidRev( audio:[Float],power:Int?)
}

class AudioRecorder {
    var audioEngine: AVAudioEngine? = nil
    
    var delegate : AudioRecorderDelegate? = nil
    
    private var buffsize : Int = 1024
    
    private var enablePower = false
    
    private var power = SpeechToPower()
    
    private var outputFormat:AVAudioFormat? = nil
    
    init(delegate : AudioRecorderDelegate? = nil, audioEngine: AVAudioEngine? = nil,outputFormat:AVAudioFormat? = nil,  enablePower:Bool = false,buffsize : Int = 1024) {
        
        self.delegate = delegate
        self.audioEngine = audioEngine
        self.outputFormat = outputFormat
        self.enablePower = enablePower
        self.buffsize = buffsize
    }
    
    
    func requestAccess(){
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted{
                
            }else{
                
            }
        }
    }
    
    func initEngine(){
        
        if audioEngine == nil{
            self.audioEngine = AVAudioEngine()
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

        let inputNode = self.audioEngine?.inputNode
        let bus = 0
        let inputFormat = inputNode?.outputFormat(forBus: bus)
        
        let outputFormat = self.outputFormat ?? AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1,
            interleaved: false)!
        
        let converter = AVAudioConverter(from: inputFormat!, to: outputFormat)!
        
        inputNode!.installTap(
            onBus: bus,
            bufferSize: AVAudioFrameCount(self.buffsize),
            format: inputFormat
        ) {
            [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            
            guard let self = self else {return}
            
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
            let res = converter.convert(
                to: convertedBuffer,
                error: &error, withInputFrom: inputCallback)
            
            if res == .haveData || res == .inputRanDry{
                let array = convertedBuffer.array()
                var powerValue : Int?
                if self.enablePower{
                    powerValue = self.power.speechDataToPower(fromFloat32: array)
                }
                self.delegate?.audioDidRev(audio: array,power: powerValue)
            }
        }
    }
    
    func start() throws{
        do {
            try self.audioEngine?.start()
        } catch let error as NSError {
            print("Got an error starting audioEngine: \(error.domain), \(error)")
            throw error
        }
    }
    
    func stop() {
        audioEngine?.stop()
        print("stopped")
    }
    
}

import Foundation
import AVFoundation
  
class SpeechToPower {
    private let speechPermutation: [Int8] = [
        0, 1, 2, 3, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
    ]
  
    func speechAbs(vector: [Int16]) -> Int16 {
        var maximum: Int = 0
  
        for value in vector {
            let absolute = abs(Int(value))
            if absolute > maximum {
                maximum = absolute
            }
        }
  
        if maximum > 32767 {
            maximum = 32767
        }
  
        return Int16(maximum)
    }
  
    func speechToLevel(data: [Int16]) -> Int {
        var absMax: Int16 = 0
        var currentLevel: Int8 = 0
  
        let absValue = speechAbs(vector: data)
  
        if absValue > absMax {
            absMax = absValue
        }
  
        var position = Int(absMax) / 1000
  
        if position == 0 && absMax > 250 {
            position = 1
        }
  
        currentLevel = speechPermutation[position]
        absMax >>= 2
  
        return Int(currentLevel)
    }
    
    
    func speechDataToPower(fromFloat32 array: [Float32]) -> Int {
        let audio : [Int16] = array.map { value in
            let scaledValue = Int(value * 32768)
            return Int16(clamping: scaledValue)
        }
        return speechToLevel(data: audio)
    }
  
    func speechDataToPower(fromInt16 data: NSData) -> Int {
        let length = data.length / MemoryLayout<Int16>.size
        var int16Array = [Int16](repeating: 0, count: length)
        data.getBytes(&int16Array, length: data.length)
        return speechToLevel(data: int16Array)
    }
  
    func speechDataToPower(fromFloat32 data: NSData) -> Int {
        let length = data.length / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: length)
        data.getBytes(&floatArray, length: data.length)
  
        var int16Array = [Int16](repeating: 0, count: length)
        for (index, value) in floatArray.enumerated() {
            int16Array[index] = Int16(value * 32768)
        }
        return speechToLevel(data: int16Array)
    }
}

