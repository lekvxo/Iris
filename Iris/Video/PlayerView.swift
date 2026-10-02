import AVKit
import SwiftUI

struct PlayerView: UIViewControllerRepresentable {
    let session: PlayerSession
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(session: session, close: close) }
    func makeUIViewController(context: Context) -> Container {
        let controller = AVPlayerViewController()
        controller.player = session.player
        controller.experienceController.allowedExperiences = .recommended(including: [.expanded])
        controller.experienceController.delegate = context.coordinator
        return Container(player: controller) { context.coordinator.start(controller) }
    }
    func updateUIViewController(_ controller: Container, context: Context) {}
    static func dismantleUIViewController(_ controller: Container, coordinator: Coordinator) {
        coordinator.startTask?.cancel()
        coordinator.session.stop()
        controller.player.experienceController.delegate = nil
        controller.player.player?.pause()
        controller.player.player = nil
    }

    // AVPlayerViewController itself must not be subclassed.
    @MainActor final class Container: UIViewController {
        let player: AVPlayerViewController
        let appeared: () -> Void
        init(player: AVPlayerViewController, appeared: @escaping () -> Void) {
            self.player = player
            self.appeared = appeared
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(player)
            view.addSubview(player.view)
            player.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                player.view.topAnchor.constraint(equalTo: view.topAnchor),
                player.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                player.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                player.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            player.didMove(toParent: self)
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared()
        }
    }

    @MainActor final class Coordinator: NSObject, AVExperienceController.Delegate {
        let session: PlayerSession
        let close: () -> Void
        var startTask: Task<Void, Never>?
        init(session: PlayerSession, close: @escaping () -> Void) {
            self.session = session
            self.close = close
        }
        func start(_ controller: AVPlayerViewController) {
            guard startTask == nil else { return }
            startTask = Task {
                let result = await controller.experienceController.transition(to: .expanded)
                guard !Task.isCancelled else { return }
                if result == .completed { session.play() }
                else { session.error = "Expanded playback is unavailable. Use Back to page to return." }
            }
        }
        func experienceController(_ controller: AVExperienceController, didChangeTransitionContext context: AVExperienceController.TransitionContext) {
            if context.toExperience == .embedded, context.fromExperience != .embedded,
               context.status == .finished(result: .completed) { close() }
        }
        func experienceController(_ controller: AVExperienceController, prepareForTransitionUsing context: AVExperienceController.TransitionContext) async {}
        func experienceController(_ controller: AVExperienceController, didChangeAvailableExperiences availableExperiences: AVExperienceController.Experiences) {}
    }
}

struct PlayerScreen: View {
    let session: PlayerSession
    let close: () -> Void
    var body: some View {
        PlayerView(session: session, close: close)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button("Back to page", systemImage: "chevron.left", action: close)
                    .hoverEffect().padding().glassBackgroundEffect()
            }
            .overlay {
                if let error = session.error {
                    ContentUnavailableView {
                        Label("Unable to play video", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        if session.canRetry {
                            Button(session.isRetrying ? "Retrying…" : "Retry playback") { session.retry() }
                                .disabled(session.isRetrying).hoverEffect()
                        }
                        Button("Back to page", action: close).hoverEffect()
                    }.padding().glassBackgroundEffect()
                }
            }
    }
}
