//
//  PrinterWidgetBundle.swift
//  PrinterWidget
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import WidgetKit

// NOTE: This file belongs to the widgetExtension target only, not the main Printer target.
// The WIDGET_EXTENSION flag is defined in the widget target's build settings to prevent
// SourceKit-LSP from treating this @main as conflicting with the app's @main.

#if WIDGET_EXTENSION
@main
#endif
struct PrinterWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrinterLiveActivity()
    }
}
