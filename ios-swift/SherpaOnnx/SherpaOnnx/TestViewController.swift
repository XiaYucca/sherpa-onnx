import AVFoundation
import UIKit
import OfflineFramework



class ViewController: UIViewController, TranscribeManagerDelegate {
    func recvAudios(audio: [Float]) {
        
    }
    
    func transcribe(segment: OfflineFramework.Sentence) {
        print("transcribe \(segment)")
        self.updateLabel(item: segment)
    }
    
    @IBOutlet weak var tableView: UITableView!

    @IBOutlet weak var recordBtn: UIButton!

    var audioEngine: AVAudioEngine? = nil
    var recognizer: SherpaOnnxRecognizer! = nil
    
    var sentences =  [Sentence]()
    
    weak var lastCell : UITableViewCell?
    
    var diarization = SpeakerDiarization()
    var totalSamples =  [Float]()
    var lastSamplesCount = 0
    
    func translator(text:String,callback:((_ text:String)->())?){
        let parameters: [String: Any] = ["text": text
        ]
        callback?("")
        return;
        
//        AF.request("http://40.82.153.252:8763/translator", method: .post, parameters: parameters).responseJSON { response in
//
//            switch response.result{
//
//            case .success(let data):
//                if let data = data as? [String : Any],
//                   let content = data["content"] as? [String : [String]],
//                   let text = content["text"]?[0]
//                {
//                    print(text)
//                    callback?(text)
//                }
//            case .failure(let error): break
//
//            }
//        }

    }
    
    func updateLabel(item:Sentence) {
        var item = item
        if item.source.count == 0 || item.source == "。" {return}
        
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
    
    var manager : TranscribeManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        do{
           
           var model = getResource("source-zh", "ezn")

            manager = TranscribeManager.init(lan: "zh", delgate: self)
            manager.prepare(path: URL.init(fileURLWithPath: model)) { progress, info in
                print("progress\(progress) info\(info)")
            }
        }

        recordBtn.setTitle("Start", for: .normal)
    }
    
    var index = 0

    @IBAction func onRecordBtnClick(_ sender: UIButton) {

        if recordBtn.currentTitle == "Start" {
//            startRecorder()
//            SherpaOnnxManager.shared.startRecorder()
            
//            if index % 2 == 0{
//                manager = TranscribeManager.init(lan: "zh", delgate: self)
//            }else{
//                manager = TranscribeManager.init(lan: "en", delgate: self)
//            }
//            index = index + 1
            manager = TranscribeManager.init(lan: "zh", delgate: self)
            
            
            recordBtn.setTitle("Stop", for: .normal)
            manager.load()
            try! manager.start()
            
        } else {
            recordBtn.setTitle("Start", for: .normal)
            self.manager.stop()
            self.manager.release()
            
        }
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

