//
//  ContentView.swift
//  nfc-simple
//
//  Created by Ilya Gruzdev on 21.12.2022.
//

import SwiftUI

struct ContentView: View {
    let nfcUtility = NFCUtility()
    @State private var tagModel: TagModel?
    
    var body: some View {
        VStack {
            if let tagModel {
                Spacer()
                Text("Tag ID: \(tagModel.tagID)")
                Text("Tag Type: \(tagModel.tagType)")
                Text("Tag Name: \(tagModel.name)")
                ForEach(tagModel.records, id: \.self) { record in
                    Text(record)
                }
            }
            Spacer()
            
            HStack(spacing: 20) {
                Button {
                    nfcUtility.read() { result in
                        switch result {
                        case let .success(tagModel):
                            self.tagModel = tagModel
                        case .failure:
                            break
                        }
                        print("readed")
                    }
                } label: {
                    Text("Read")
                        .foregroundColor(.white)
                        .padding()
                        .background(.black)
                }
                
                Button {
                    nfcUtility.write(action: .write(message: "techno"))
                } label: {
                    Text("Write")
                        .foregroundColor(.white)
                        .padding()
                        .background(.black)
                }
                
                Button {
                    nfcUtility.write(action: .setup(tagModel: TagModel(name: "rmr")))
                } label: {
                    Text("Setup")
                        .foregroundColor(.white)
                        .padding()
                        .background(.black)
                }
            }
            Spacer()
                .frame(height: 20)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
