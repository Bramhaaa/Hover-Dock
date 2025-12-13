//
//  ContentView.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 13/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dockDetector: DockDetector
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(systemName: "dock.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(dockDetector.isHoveringDock ? .green : .gray)
            
            // App Title
            Text("HoverDock")
                .font(.title)
                .fontWeight(.bold)
            
            // Status
            VStack(spacing: 8) {
                Text("Dock Position: \(dockDetector.dockPosition.rawValue.capitalized)")
                    .font(.headline)
                
                Text(dockDetector.isHoveringDock ? "🟢 Hovering Dock" : "⚪️ Not Hovering")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(dockDetector.isHoveringDock ? .green : .secondary)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Status: Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Move your mouse over the Dock to test detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
        .environmentObject(DockDetector())
}
