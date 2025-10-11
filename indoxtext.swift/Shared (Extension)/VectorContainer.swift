//
//  Indox.swift
//  indox
//
//  Created by Oleksandr Korenyuk on 13.10.2021.
//

import Foundation
import CoreML

public struct Meta {
    public var i: Int;
    public var k: Int;
    public var file_index: Int;
    
    public init(i: Int, k: Int, file_index: Int) {
        self.i = i;
        self.k = k;
        self.file_index = file_index;
    }
}

public struct BatchedVectorContainer {
    public var input_ids: [MLMultiArray];
    public var input_mask: [MLMultiArray];
    public var segment_ids: [MLMultiArray];
    public var meta:[Meta];
    
    public init(input_ids: [MLMultiArray], input_mask: [MLMultiArray], segment_ids: [MLMultiArray], meta: [Meta]) {
        self.input_ids = input_ids;
        self.input_mask = input_mask;
        self.segment_ids = segment_ids;
        self.meta = meta;
    }
}

public struct VectorContainer {
    public var input_ids: [Int];
    public var input_mask: [Int];
    public var segment_ids: [Int];
    public var meta:Meta;
    
    public init(input_ids: [Int], input_mask: [Int], segment_ids: [Int], meta: Meta) {
        self.input_ids = input_ids;
        self.input_mask = input_mask;
        self.segment_ids = segment_ids;
        self.meta = meta;
    }
}

public struct VectorContainerML {
    internal var input: [sentenceModelInput];
    public var meta: [Meta];
    
    internal init(input: [sentenceModelInput], meta: [Meta]) {
        self.input = input;
        self.meta = meta;
    }
}
