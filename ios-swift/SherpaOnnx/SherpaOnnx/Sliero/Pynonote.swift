//
//  Pynonote.swift
//  SherpaOnnx
//
//  Created by Rain on 2024/10/28.
//

import Foundation
import onnxruntime_objc
import Accelerate

class Pynonote {
    
    enum SileroVadError: Error {
        case Error(_ message: String)
    }
    
    private let ortEnv: ORTEnv
    private let ortSession: ORTSession
    
    private var lastOutput : [[Float]]?
    
    init(modelName:String="model-pynonote",sample:Int=16000) throws{
        
        self.ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "onnx") else {
            throw SileroVadError.Error("Failed to find model file.")
        }
        self.ortSession = try ORTSession(env: self.ortEnv, modelPath: modelPath, sessionOptions: nil)
        
    }
    
    func process(input:[Float]) throws -> [[Float]]?  {
        let minCount = 160000
        var input = input
        
        if input.count < minCount {
             input.append(contentsOf: repeatElement(0, count: minCount - input.count))
        }else{
             input = Array(input.suffix(minCount))
        }
        
        let data = Data(buffer: UnsafeBufferPointer(start: input, count: input.count))
        let res = try self.process(input: data)
        return res
    }
    
    func process(input:Data) throws -> [[Float]]? {
        
        if input.count < 160000{
            throw SileroVadError.Error("input data less than 10s samples")
        }
        
        let inputShape: [NSNumber] = [1,1, 160000]
        
        let input = try ORTValue(
            tensorData: NSMutableData(data: input),
            elementType: ORTTensorElementDataType.float,
            shape: inputShape)
        
        let outputs = try ortSession.run(
            withInputs: ["x": input],
            outputNames: ["y"],
            runOptions: nil)
        
        guard let output = outputs["y"] else {
            throw SileroVadError.Error("Failed to get model output.")
        }
        let outputData = try output.tensorData() as Data
        // 验证数据长度
        
        let expectedLength = 589 * 7 * MemoryLayout<Float>.size
        
        guard outputData.count == expectedLength else {
            fatalError("Data length is not equal to 16492 bytes")
        }
          
        // 将 Data 转换为 [Float] 数组
        let floatArray: [Float] = outputData.withUnsafeBytes {
            Array(UnsafeBufferPointer<Float>(start: $0.bindMemory(to: Float.self).baseAddress, count: $0.count / MemoryLayout<Float>.size))
        }
          
        // 构建 [589, 7] 的二维数组
        let rowCount = 589
        let columnCount = 7
          
        var twoDimensionalArray: [[Float]]? = floatArray.withUnsafeBufferPointer { bufferPointer in
            // 使用 Accelerate 框架进行矩阵操作
            var matrix = [Float](repeating: 0, count: rowCount * columnCount)
            vDSP_mtrans(bufferPointer.baseAddress!, 1, &matrix, 1, vDSP_Length(columnCount), vDSP_Length(rowCount))
          
            return (0..<rowCount).map { row in
                Array(matrix[(row * columnCount)..<((row + 1) * columnCount)])
            }
        }
          
        if let lastOutput = self.lastOutput ,let outrtp = twoDimensionalArray{
            twoDimensionalArray = self.reorder(x: lastOutput, y: outrtp)
            // 示例输出
            for row in twoDimensionalArray! {
                print(row)
            }
        }
        self.lastOutput = twoDimensionalArray
        
        return twoDimensionalArray
    }
    
    // Helper function to generate permutations
    func permutations<T>(_ array: [T]) -> [[T]] {
        if array.isEmpty {
            return [[]]
        } else {
            return permutations(Array(array.dropFirst())).flatMap { perm in
                (0...perm.count).map { i in
                    var newPerm = perm
                    newPerm.insert(array[0], at: i)
                    return newPerm
                }
            }
        }
    }
      
    // Helper function to transpose a 2D array
    func transpose<T>(_ array: [[T]]) -> [[T]] {
        guard let firstRow = array.first else { return [] }
        return (0..<firstRow.count).map { index in
            array.map { $0[index] }
        }
    }
      
    // Reorder function with optimizations
    func reorder(x: [[Float]], y: [[Float]]) -> [[Float]]? {
        let yTransposed = transpose(y)
        let perms = permutations(yTransposed).map { transpose($0) }
          
        // Initialize an array to store differences
        var diffs = [Float](repeating: 0, count: perms.count)
          
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
          
        for (index, perm) in perms.enumerated() {
            dispatchGroup.enter()
            queue.async {
                var permFlat = perm.flatMap { $0 }
                var xFlat = x.flatMap { $0 }
                var diff: Float = 0
                  
                // Using Accelerate to compute the absolute differences and sum
                var temp = [Float](repeating: 0, count: permFlat.count)
                vDSP_vsub(xFlat, 1, permFlat, 1, &temp, 1, vDSP_Length(permFlat.count))
                vDSP_vabs(temp, 1, &temp, 1, vDSP_Length(temp.count))
                vDSP_sve(temp, 1, &diff, vDSP_Length(temp.count))
                  
                diffs[index] = diff
                dispatchGroup.leave()
            }
        }
          
        dispatchGroup.wait()
          
        guard let minIndex = diffs.indices.min(by: { diffs[$0] < diffs[$1] }) else {
            return nil
        }
          
        return perms[minIndex]
    }  
}
