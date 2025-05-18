//
//  ImmersiveView.swift
//  SpatialGestureDemo
//
//  Created by GUNNER on 2025/4/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import SpatialGestures
import AVFoundation

struct ImmersiveView: View {
    @StateObject private var gestureManager = SpatialGestures.createManager(
        referenceAnchor: Entity(),
        enableMeshDetection: true,
        showDebugVisualization: false,
        isDebugEnabled: true,
        rotationAxis: .y
    )
    @StateObject private var debugViewModel = DebugViewModel()
    var basicEntity = Entity()
    @State var audioPlayer: AVAudioPlayer?
    
    var body: some View {
        RealityView { content, attachments in
            content.add(basicEntity)
            if let debugOverlay = attachments.entity(for: "debugOverlay") {
                debugOverlay.position = SIMD3<Float>(0.2, 1.5, -0.6)
                basicEntity.addChild(debugOverlay)
            }

            Task {
                do {
                    let robotEntity = try await Entity(named: "Robot", in: realityKitContentBundle)
                    await gestureManager.addEntity(robotEntity, name: "Robot")
                    basicEntity.addChild(robotEntity)
                    
                    robotEntity.position = SIMD3<Float>(-0.2, 1.4, -0.6)
                    
                    // init audio
                    do {
                        let url = Bundle.main.url(forResource: "placement", withExtension: "mp3")
                        audioPlayer = try AVAudioPlayer(contentsOf: url!)
                    } catch {
                        print("init audio failed: \(error)")
                    }
                    
                    // Set gesture callback
                    gestureManager.setGestureCallback { gestureInfo in
                        debugViewModel.addLog(gestureInfo)
                        
                        // Update entity properties display
                        if gestureInfo.entityName == "Robot" {
                            debugViewModel.updateEntityProperties(
                                position: gestureInfo.transform.translation,
                                rotation: gestureInfo.transform.rotation.convertToEulerAngles(),
                                scale: gestureInfo.transform.scale
                            )
                        }
                        
                        if gestureInfo.gestureType == .placement {
                            // play sound
                            audioPlayer?.play()
                        }
                    }
                    
                    // Initialize entity properties
                    debugViewModel.updateEntityProperties(
                        position: robotEntity.position,
                        rotation: robotEntity.orientation.convertToEulerAngles(),
                        scale: robotEntity.scale
                    )
                    
                    // Start Plane Detection
                    Task {
                        await gestureManager.startMeshDetection(
                            rootEntity: basicEntity
                        )
                    }
                    
                } catch {
                    print("error")
                }
            }
        } attachments: {
            // Debug overlay as attachment
            Attachment(id: "debugOverlay") {
                DebugOverlayView(viewModel: debugViewModel) {
                    // Reset button callback
                    Task {
                        if let robotEntity = gestureManager.getEntity(named: "Robot")?.entity {
                            robotEntity.position = SIMD3<Float>(-0.2, 1.4, -0.6)
                            robotEntity.orientation = simd_quatf()
                            robotEntity.scale = SIMD3<Float>(1, 1, 1)
                            
                            // Update UI
                            debugViewModel.updateEntityProperties(
                                position: robotEntity.position,
                                rotation: robotEntity.orientation.convertToEulerAngles(),
                                scale: robotEntity.scale
                            )
                        }
                    }
                } onToggleVis: {
                    debugViewModel.showDebugVisualization.toggle()
                    gestureManager.setMeshDetectionVisualization(debugViewModel.showDebugVisualization)
                }
            }
        }
        .withSpatialGestures(manager: gestureManager)
        .onDisappear {
            Task {
                await gestureManager.stopMeshDetection()
                gestureManager.removeEntity(named: "Robot")
            }
        }
    }
}

// Debug data view model
class DebugViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var entityPosition: SIMD3<Float> = .zero
    @Published var entityRotation: SIMD3<Float> = .zero
    @Published var entityScale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    @Published var showDebugVisualization: Bool = false
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }
    
    func addLog(_ gestureInfo: SpatialGestureInfo) {
        let message = formatGestureInfo(gestureInfo)
        let entry = LogEntry(timestamp: Date(), message: message)
        
        DispatchQueue.main.async {
            self.logs.append(entry)
            // Limit log count to avoid too many
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }
    
    func updateEntityProperties(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        DispatchQueue.main.async {
            self.entityPosition = position
            self.entityRotation = rotation
            self.entityScale = scale
        }
    }
    
    private func formatGestureInfo(_ info: SpatialGestureInfo) -> String {
        var result = "[\(gestureTypeString(info.gestureType))] \(info.entityName): "
        
        switch info.gestureType {
        case .drag:
            result += "Position: \(formatVector(info.transform.translation))"
            if let initialTransform = info.initialTransform {
                let offset = info.transform.translation - initialTransform.translation
                result += "  Offset: \(formatVector(offset))"
            }
        case .rotate:
            result += "Rotation: \(formatVector(info.transform.rotation.convertToEulerAngles()))"
            if let angle = info.changeValue as? Float {
                result += "  Angle: \(String(format: "%.2f", angle))"
            }
        case .scale:
            result += "Scale: \(formatVector(info.transform.scale))"
            if let magnification = info.changeValue as? Float {
                result += "  Magnification: \(String(format: "%.2f", magnification))"
            }
        case .gestureEnded:
            result += "Position: \(formatVector(info.transform.translation))  Rotation: \(formatVector(info.transform.rotation.convertToEulerAngles()))  Scale: \(formatVector(info.transform.scale))"
        case .placement:
            print("place")
        }
        
        return result
    }
    
    private func formatVector(_ vector: SIMD3<Float>) -> String {
        return String(format: "(%.2f, %.2f, %.2f)", vector.x, vector.y, vector.z)
    }
    
    private func gestureTypeString(_ type: SpatialGestureType) -> String {
        switch type {
        case .drag:
            return "Drag"
        case .rotate:
            return "Rotate"
        case .scale:
            return "Scale"
        case .gestureEnded:
            return "Gesture Ended"
        case .placement:
            return "Placement"
        }
    }
}

// Debug overlay view
struct DebugOverlayView: View {
    @ObservedObject var viewModel: DebugViewModel
    var onReset: () -> Void
    var onToggleVis: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            HStack(alignment: .top, spacing: 20) {                
                // Entity properties area
                VStack(alignment: .leading) {
                    Text("Entity Properties")
                        .font(.title2)
                        .padding(.bottom, 5)

                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                            Text("Position:")
                                .bold()
                            HStack {
                                Text("X:")
                                    .foregroundColor(.red)
                                Text("\(String(format: "%.2f", viewModel.entityPosition.x))")
                            }
                            HStack {
                                Text("Y:")
                                    .foregroundColor(.green)
                                Text("\(String(format: "%.2f", viewModel.entityPosition.y))")
                            }
                            HStack {
                                Text("Z:")
                                    .foregroundColor(.blue)
                                Text("\(String(format: "%.2f", viewModel.entityPosition.z))")
                            }
                            
                            Text("Rotation:")
                                .bold()
                                .padding(.top, 5)
                            HStack {
                                Text("X:")
                                    .foregroundColor(.red)
                                Text("\(String(format: "%.2f, %.2f°", viewModel.entityRotation.x, viewModel.entityRotation.x * 180 / .pi))")
                            }
                            HStack {
                                Text("Y:")
                                    .foregroundColor(.green)
                                Text("\(String(format: "%.2f, %.2f°", viewModel.entityRotation.y, viewModel.entityRotation.y * 180 / .pi))")
                            }
                            HStack {
                                Text("Z:")
                                    .foregroundColor(.blue)
                                Text("\(String(format: "%.2f, %.2f°", viewModel.entityRotation.z, viewModel.entityRotation.z * 180 / .pi))")
                            }
                            
                            Text("Scale:")
                                .bold()
                                .padding(.top, 5)
                            HStack {
                                Text("X:")
                                    .foregroundColor(.red)
                                Text("\(String(format: "%.2f", viewModel.entityScale.x))")
                            }
                            HStack {
                                Text("Y:")
                                    .foregroundColor(.green)
                                Text("\(String(format: "%.2f", viewModel.entityScale.y))")
                            }
                            HStack {
                                Text("Z:")
                                    .foregroundColor(.blue)
                                Text("\(String(format: "%.2f", viewModel.entityScale.z))")
                            }
                        }
                        .font(.system(.title3, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    Button(action: onReset) {
                        Text("Reset")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 10)
                    
                    Button(action: onToggleVis) {
                        Text((viewModel.showDebugVisualization ? "Hide" : "Show") + " Mesh")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 10)
                }
                .frame(width: 300, height: 600)

                // Log area
                VStack(alignment: .leading) {
                    Text("Gesture Logs")
                        .font(.title2)
                        .padding(.bottom, 5)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(viewModel.logs.reversed()) { log in
                                Text(log.message)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(nil)
                                    .padding(.vertical, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .frame(width: 400, height: 600)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .glassBackgroundEffect()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
