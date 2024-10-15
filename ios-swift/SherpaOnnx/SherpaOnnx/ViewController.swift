//
//  ViewController.swift
//  SherpaOnnx
//
//  Created by fangjun on 2023/1/28.
//

import AVFoundation
import UIKit
import Alamofire


class ViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!

    @IBOutlet weak var recordBtn: UIButton!

    var audioEngine: AVAudioEngine? = nil
    var recognizer: SherpaOnnxRecognizer! = nil
    
    var sentences =  [Sentence]()
    
    weak var lastCell : UITableViewCell?
 
    
    func translator(text:String,callback:((_ text:String)->())?){
        let parameters: [String: Any] = ["text": text
        ]
        AF.request("http://40.82.153.252:8763/translator", method: .post, parameters: parameters).responseJSON { response in
                
            switch response.result{
                
            case .success(let data):
                if let data = data as? [String : Any],
                   let content = data["content"] as? [String : [String]],
                   let text = content["text"]?[0]
                {
                    print(text)
                    callback?(text)
                }
            case .failure(let error): break
                
            }
        
        }

    }
    
    func updateLabel(item:Sentence) {
        var item = item
        if item.source == "。"{return}
        
        self.translator(text: item.source) { text in
            item.target = text
            self.updateTableView(item: item)
        }
    }
    
    func updateTableView(item:Sentence){
        DispatchQueue.main.async {
            
            let lastItem = self.sentences.last
            self.tableView.beginUpdates()
            
            if (lastItem?.state ?? .final) == .final{
                self.sentences.append(item)
                self.tableView.insertRows(at: [IndexPath(row: self.sentences.count - 1, section: 0)], with: .none)
            }else{
                self.sentences.removeLast()
                self.sentences.append(item)
                self.tableView.reloadRows(at: [IndexPath(row: self.sentences.count - 1, section: 0)], with: .none)
            }
            
            self.tableView.endUpdates()

            self.tableView.scrollToRow(at: IndexPath(row: self.sentences.count - 1, section: 0), at: .middle, animated: false)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        recordBtn.setTitle("Start", for: .normal)
//        initRecognizer()
//        initRecorder()
        SherpaOnnxManager.shared.start()
        SherpaOnnxManager.shared.offline_vad_final_callback = {
            item in
            self.updateLabel(item: item)
        }
        SherpaOnnxManager.shared.offline_vad_parctial_callback = {
            item in
            self.updateLabel(item: item)
        }

    }

    @IBAction func onRecordBtnClick(_ sender: UIButton) {

        if recordBtn.currentTitle == "Start" {
//            startRecorder()
            SherpaOnnxManager.shared.startRecorder()
            recordBtn.setTitle("Stop", for: .normal)
            
        } else {
//            stopRecorder()
            SherpaOnnxManager.shared.stopRecorder()
            recordBtn.setTitle("Start", for: .normal)
        }
    }

    func initRecognizer() {
        // Please select one model that is best suitable for you.
        //
        // You can also modify Model.swift to add new pre-trained models from
        // https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html

         let modelConfig = getBilingualStreamZhEnZipformer20230220()
        // let modelConfig = getZhZipformer20230615()
        // let modelConfig = getEnZipformer20230626()
//        let modelConfig = getBilingualStreamingZhEnParaformer()

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80)

        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            enableEndpoint: true,
            rule1MinTrailingSilence: 2.4,
            rule2MinTrailingSilence: 0.8,
            rule3MinUtteranceLength: 30,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )
        recognizer = SherpaOnnxRecognizer(config: &config)
    }

    func initRecorder() {
        print("init recorder")
        audioEngine = AVAudioEngine()
        let inputNode = self.audioEngine?.inputNode
        let bus = 0
        let inputFormat = inputNode?.outputFormat(forBus: bus)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1,
            interleaved: false)!

        let converter = AVAudioConverter(from: inputFormat!, to: outputFormat)!

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
            if !array.isEmpty {
                self.recognizer.acceptWaveform(samples: array)
                while (self.recognizer.isReady()){
                    self.recognizer.decode()
                }
                let isEndpoint = self.recognizer.isEndpoint()
                let text = self.recognizer.getResult().text

                

                if isEndpoint {
                    if !text.isEmpty {
                       
                    }
                    self.recognizer.reset()
                }
            }
        }

    }

    func startRecorder() {
        sentences = []

        do {
            try self.audioEngine?.start()
        } catch let error as NSError {
            print("Got an error starting audioEngine: \(error.domain), \(error)")
        }
        print("started")
    }

    func stopRecorder() {
        audioEngine?.stop()
        print("stopped")
    }
}


extension ViewController : UITableViewDelegate,UITableViewDataSource{
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sentences.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tableViewCellId", for: indexPath)

        let titleLabel = cell.viewWithTag(10) as! UILabel
        let contentLabel = cell.viewWithTag(20) as! UILabel
        let item = self.sentences[indexPath.row]
        titleLabel.text = item.source
        contentLabel.text = item.target
        
//        if indexPath.row == self.sentences.count - 1{
//            contentLabel.font = .systemFont(ofSize: 32)
//        }
//        if lastCell != cell{
//            if let contentLabel = lastCell?.viewWithTag(20) as? UILabel{
//                contentLabel.font = .systemFont(ofSize: 15)
//            }
//            lastCell = cell
//        }
        return cell
    }
    
    
}
