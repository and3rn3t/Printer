//
//  PrinterWidgetBundle.swift
//  PrinterWidget
//
//  Created by Matt on 2/10/26.
//

import WidgetKit
import SwiftUI

// NOTE: When a Widget Extension target is added via Xcode (File → New → Target → Widget Extension),
// uncomment @main below and move these files into that target.
// For now, leaving @main commented out to avoid conflicting with the app's @main entry point,
// which causes SourceKit indexing failures ("trampoline errors") in the IDE.

// @main
struct PrinterWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrinterLiveActivity()
    }
}
