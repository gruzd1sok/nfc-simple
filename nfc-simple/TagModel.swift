//
//  TagModel.swift
//  nfc-simple
//
//  Created by Ilya Gruzdev on 21.12.2022.
//


struct TagModel: Codable {
    let name: String
    var tagID: String
    var tagType: String
    var records: [String]
    
    init(name: String) {
        self.name = name
        self.tagID = ""
        self.tagType = ""
        records = []
    }
}
