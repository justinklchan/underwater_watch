//
//  ContentView.swift
//  test_companion Watch App
//
//  Created by Justin Kwok Lam CHAN on 1/3/23.
//

import SwiftUI
import CoreMotion
import AVFoundation

extension DispatchQueue {
    static func background(delay: Double = 0.0, background: (()->Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async {
            background?()
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
                    completion()
                })
            }
        }
    }
}

struct ContentView: View {
    let motion = CMMotionManager()
    
    @State var timer_accel:Timer?
    @State var timer_gyro:Timer?
    @State var timer_mag:Timer?
    
    @State var accel_file_url:URL?
    @State var accel_fileHandle:FileHandle?
    @State var gyro_file_url:URL?
    @State var gyro_fileHandle:FileHandle?
    @State var mag_file_url:URL?
    @State var mag_fileHandle:FileHandle?
    
    @State var ts: Double = 0
    @State var mystarted:Int=0
    @State private var total_time: Int = UserDefaults.standard.integer(forKey: "total_time") == 0 ? 1 : UserDefaults.standard.integer(forKey: "total_time")
    @State private var fileID: Int = UserDefaults.standard.integer(forKey: "fileID") == 0 ? 1 : UserDefaults.standard.integer(forKey: "fileID")
    @State private var volume: Float32 = UserDefaults.standard.float(forKey: "volume") == 0 ? 0.01 : UserDefaults.standard.float(forKey: "volume")
    
    @State var audioSession:AVAudioSession!
    @State var audioRecorder:AVAudioRecorder!
    @State var player: AVAudioPlayer?
    
    @State var manager: CMWaterSubmersionManager = CMWaterSubmersionManager()
    
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("File ID")
                    TextField("",value: $fileID, format: .number)
                    .onChange(of: fileID) {
                        UserDefaults.standard.set($0, forKey: "fileID")
                    }
                }
                HStack {
                    Text("Volume")
                    TextField("",value: $volume, format: .number)
                    .onChange(of: volume) {
                        UserDefaults.standard.set($0, forKey: "volume")
                    }
                }
                HStack {
                    Text("Record length")
                    TextField("",value: $total_time, format: .number)
                    .onChange(of: total_time) {
                        UserDefaults.standard.set($0, forKey: "total_time")
                    }
                }
                Text(String(ts))
                Button("start") {
                    startSensors()
                }.disabled(mystarted==1)
                    .foregroundColor(mystarted==0 ? .blue : .black)
                Button("stop") {
                    stopSensors()
                }.disabled(mystarted==0)
                    .foregroundColor(mystarted==1 ? .blue : .black)
            }
        }
        .padding()
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func myrecord(filename: String, maxtime: Int) {
        audioSession = AVAudioSession.sharedInstance()
        let desc = audioSession.availableInputs?.first
        print (desc!)
        do {
            try
                audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: audioSession.mode)
                
            var url = URL(string:"")
            if let parent = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nmslab") {
                url = parent.appendingPathComponent(filename)
            }
            print (url!)
            
            let recordSettings:[String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,
                                               AVSampleRateKey:48000.0,
                                               AVNumberOfChannelsKey:1,
                                               AVLinearPCMIsNonInterleaved: true,
                                               AVLinearPCMBitDepthKey: 16]
            
            // initialize audio recorder and session
            try audioRecorder = AVAudioRecorder(url:url!, settings: recordSettings)
            audioRecorder.prepareToRecord()
            
            try audioSession.setActive(true)
            
            audioRecorder.record()
            
            guard let chirpurl = Bundle.main.url(forResource: "shortchirp", withExtension: "wav") else { return }
            
            player = try AVAudioPlayer(contentsOf: chirpurl, fileTypeHint: AVFileType.mp3.rawValue)
            player?.numberOfLoops = -1
            guard let player = player else { return }
            player.volume=volume
            
            player.play()
            
            sleep(UInt32(maxtime))
            
            audioRecorder.stop()
            player.stop()
            try audioSession.setActive(false)
        }catch let error {
            print("ERROR")
            print(error.localizedDescription)
        }
    }
    
    func readfile(filename: String) -> Array<Double> {
        var vals = [Double]();
        
        let filePath = NSURL(fileURLWithPath: getDocumentsDirectory().absoluteString).appendingPathComponent(filename)!
        
        do {
            if try filePath.checkResourceIsReachable() {
                print(filePath.absoluteString+" exists")
            }
            else {
                print(filePath.absoluteString+" doesn't exists")
            }
            let file = try AVAudioFile.init(forReading: filePath)
            
            let length = AVAudioFrameCount(file.length)
            let processingFormat = file.processingFormat
            
            let buffer = AVAudioPCMBuffer.init(pcmFormat: processingFormat, frameCapacity: length)!
            try file.read(into: buffer)
            
            let channelCount = buffer.format.channelCount
            
            let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(channelCount))
            let data = UnsafeBufferPointer(start: channels[0], count: Int(length))
            
            for i in 0..<data.count {
                vals.append(Double(data[i]))
            }
        }
        catch let error {
            print (error.localizedDescription)
        }
        return vals;
    }
    
    func startSensors() {
        print ("volume \(volume)")
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print ("granted")
            } else {
                print ("not granted")
            }
        }
        
        ts=NSDate().timeIntervalSince1970
        
        mystarted=1
        
        let audio_filename = "audio-\(ts).caf"
        DispatchQueue.background(background: {
            myrecord(filename: audio_filename, maxtime: total_time)
        }, completion:{
        })
        
        let sensors_enabled = 1
        if self.motion.isDeviceMotionAvailable && sensors_enabled==1 {
            do {
                let file = "accel_file_\(ts).txt"
                if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nmslab") {
                    accel_file_url = dir.appendingPathComponent(file)
                }

                // write first line of file
                try "ts,x,y,z\n".write(to: accel_file_url!, atomically: true, encoding: String.Encoding.utf8)

                accel_fileHandle = try FileHandle(forWritingTo: accel_file_url!)
                accel_fileHandle!.seekToEndOfFile()
            } catch {
                print("Error writing to file \(error)")
            }
            
            do {
                let file = "gyro_file_\(ts).txt"
                if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nmslab") {
                    gyro_file_url = dir.appendingPathComponent(file)
                }

                // write first line of file
                try "ts,x,y,z\n".write(to: gyro_file_url!, atomically: true, encoding: String.Encoding.utf8)

                gyro_fileHandle = try FileHandle(forWritingTo: gyro_file_url!)
                gyro_fileHandle!.seekToEndOfFile()
            } catch {
                print("Error writing to file \(error)")
            }
            
            do {
                let file = "mag_file_\(ts).txt"
                if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nmslab") {
                    mag_file_url = dir.appendingPathComponent(file)
                }

                // write first line of file
                try "ts,x,y,z\n".write(to: mag_file_url!, atomically: true, encoding: String.Encoding.utf8)

                mag_fileHandle = try FileHandle(forWritingTo: mag_file_url!)
                mag_fileHandle!.seekToEndOfFile()
            } catch {
                print("Error writing to file \(error)")
            }
            
            //START
            let timestamp0 = NSDate().timeIntervalSince1970
            self.motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue.current!, withHandler: { (data, error) in
                if let validData = data {
                    let aX = validData.userAcceleration.x
                    let aY = validData.userAcceleration.y
                    let aZ = validData.userAcceleration.z
                    let rX = validData.rotationRate.x
                    let rY = validData.rotationRate.y
                    let rZ = validData.rotationRate.z
                    let mX = validData.magneticField.field.x
                    let mY = validData.magneticField.field.y
                    let mZ = validData.magneticField.field.z
                    let timeStamp = NSDate().timeIntervalSince1970

//                    print ("A: \(timeStamp) \(aX) \(aY) \(aZ)")
//                    print ("G: \(timeStamp) \(rX) \(rY) \(rZ)")
//                    print ("M: \(timeStamp) \(mX) \(mY) \(mZ)")
                    
                    let text1 = "\(timeStamp), \(aX), \(aY), \(aZ)\n"
                    let text2 = "\(timeStamp), \(rX), \(rY), \(rY)\n"
                    let text3 = "\(timeStamp), \(mX), \(mY), \(mZ)\n"
                    self.accel_fileHandle!.write(text1.data(using: .utf8)!)
                    self.gyro_fileHandle!.write(text2.data(using: .utf8)!)
                    self.mag_fileHandle!.write(text3.data(using: .utf8)!)
                    
                    if Int(timeStamp - timestamp0) >= total_time {
                        stopSensors()
                    }
                }
            })
        }
        else {
          print("The motion data is not availble")
        }
        print (audio_filename)
    }
    
    func stopSensors() {
        mystarted=0
        self.motion.stopDeviceMotionUpdates()
        
        if self.accel_fileHandle != nil {
            accel_fileHandle!.closeFile()
            print (accel_file_url!)
            accel_fileHandle = nil
        }
        if self.gyro_fileHandle != nil {
            gyro_fileHandle!.closeFile()
            print (gyro_file_url!)
            gyro_fileHandle = nil
        }
        if self.mag_fileHandle != nil {
            mag_fileHandle!.closeFile()
            print (mag_file_url!)
            mag_fileHandle = nil
        }
        
        print ("stop")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
