//
//  ArchiveManager.swift
//  SherpaOnnx
//
//  Created by Rain on 2024/10/30.
//

import Foundation
import SSZipArchive


public class ArchiveManager {
    public static let shared = ArchiveManager()
    
    public var getDownloadPath : String{
        get{
           return NSHomeDirectory()  + "/Documents" + "/Download"
        }
    }
    
    private var getDataPath : String{
        get{
           return NSHomeDirectory()  + "/Documents" + "/Data"
        }
    }
    
    func testArchive() {
        let ap = getResource("source-en", "zn")
        let tp = self.getDownloadPath + "/source-en.zn"
        try? FileManager.default.copyItem(atPath: ap, toPath: tp)
        unArchive()
    }
    
    init() {
        createDirectoryIfNotExists(at: self.getDownloadPath)
    }
    
    public func unArchive(){
        for source in checkArchive(){
            self.preProcess(atPath: source)
        }
    }
    
    func checkArchive()->[String]{
        var files = [String]()
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: self.getDownloadPath)
            for item in items {
                if item.hasSuffix(".zn"){
                    files.append(self.getDownloadPath + "/" + item)
                }
            }
            return files
        } catch {
            print("Error reading contents of directory: \(error.localizedDescription)")
        }
        return files
    }
    
    func preProcess(atPath:String){
        let uri = URL.init(fileURLWithPath: atPath)
        let fileName = uri.lastPathComponent
        var dir = self.getDataPath
        switch fileName{
        case "source-en.zn":
            dir = dir + "/0"
        case "source-zh.zn":
            dir = dir + "/1"
        default:
            break
        }
        createDirectoryIfNotExists(at: dir)
        self.unArchive(atPath: atPath, destination: dir, password: "xy9114")
        
    }
    

      
    func createDirectoryIfNotExists(at path: String) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
      
        // 检查文件夹是否存在
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
      
        if exists && isDirectory.boolValue {
            print("Directory already exists.")
        } else {
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                print("Directory created successfully.")
            } catch {
                print("Error creating directory: \(error.localizedDescription)")
            }
        }
    }
      
    
    func unArchive(atPath:String,destination:String,password:String?) -> Bool {
        SSZipArchive.unzipFile(atPath: atPath, toDestination: destination, overwrite: true, password: password) { entry, info, entryNumber, total in
            print("entry:\(entry)\r\n info:\(info) entryNumber:\(entryNumber) total:\(total)")
        } completionHandler: { path, succeeded, error in
            print("completionHandler \(path) \(succeeded)")
            if succeeded{
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}
