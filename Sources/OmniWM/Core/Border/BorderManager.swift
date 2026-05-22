import AppKit
import Foundation

@MainActor
final class BorderManager {
    private var borderWindow: BorderWindow?
    private var config: BorderConfig
    private var lastAppliedFrame: CGRect?
    private var lastAppliedWindowId: Int?
    private let borderWindowOperations: BorderWindow.Operations
    private let surfaceCoordinator = SurfaceCoordinator.shared
    private var registeredSurfaceWindowNumber: Int?

    init(
        config: BorderConfig = BorderConfig(),
        borderWindowOperations: BorderWindow.Operations = .live
    ) {
        self.config = config
        self.borderWindowOperations = borderWindowOperations
    }

    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        if !enabled {
            hideBorder()
        }
    }

    func updateConfig(_ newConfig: BorderConfig) {
        let wasEnabled = config.enabled
        config = newConfig

        if !config.enabled, wasEnabled {
            hideBorder()
        } else if config.enabled {
            borderWindow?.updateConfig(config)
        }
    }

    @discardableResult
    func updateFocusedWindow(
        frame: CGRect,
        windowId: Int?,
        forceOrdering: Bool = false
    ) -> Bool {
        guard config.enabled else { return false }
        guard frame.width > 0, frame.height > 0 else {
            hideBorder()
            return false
        }

        if borderWindow == nil {
            borderWindow = BorderWindow(config: config, operations: borderWindowOperations)
        }

        guard let windowId else {
            borderWindow?.hide()
            lastAppliedFrame = nil
            lastAppliedWindowId = nil
            return false
        }

        let targetWid = UInt32(windowId)
        if let last = lastAppliedFrame,
           let lastWid = lastAppliedWindowId,
           frame.approximatelyEqual(to: last, tolerance: 0.5)
        {
            if forceOrdering || lastWid != windowId {
                borderWindow?.reorder(relativeTo: targetWid)
                lastAppliedWindowId = windowId
                syncSurfaceRegistration()
            }
            return true
        }

        guard borderWindow?.update(frame: frame, targetWid: targetWid, forceOrdering: forceOrdering) == true else {
            return false
        }
        lastAppliedFrame = frame
        lastAppliedWindowId = windowId
        syncSurfaceRegistration()
        return true
    }

    func hideBorder() {
        borderWindow?.hide()
        lastAppliedFrame = nil
        lastAppliedWindowId = nil
        surfaceCoordinator.unregister(id: surfaceID)
        registeredSurfaceWindowNumber = nil
    }

    var lastAppliedFocusedWindowIdForTests: Int? {
        lastAppliedWindowId
    }

    var lastAppliedFocusedFrameForTests: CGRect? {
        lastAppliedFrame
    }

    func cleanup() {
        hideBorder()
        borderWindow?.destroy()
        borderWindow = nil
        surfaceCoordinator.unregister(id: surfaceID)
    }

    private func syncSurfaceRegistration() {
        guard let borderWindow, let windowNumber = borderWindow.windowId.map(Int.init) else {
            surfaceCoordinator.unregister(id: surfaceID)
            registeredSurfaceWindowNumber = nil
            return
        }
        guard registeredSurfaceWindowNumber != windowNumber else { return }

        surfaceCoordinator.registerWindowNumber(
            id: surfaceID,
            windowNumber: windowNumber,
            frameProvider: { [weak self] in
                self?.lastAppliedFrame
            },
            visibilityProvider: { [weak self] in
                self?.lastAppliedFrame != nil && self?.config.enabled == true
            },
            policy: SurfacePolicy(
                kind: .border,
                hitTestPolicy: .passthrough,
                capturePolicy: .excluded,
                suppressesManagedFocusRecovery: false
            )
        )
        registeredSurfaceWindowNumber = windowNumber
    }

    private var surfaceID: String {
        "border-surface"
    }
}
