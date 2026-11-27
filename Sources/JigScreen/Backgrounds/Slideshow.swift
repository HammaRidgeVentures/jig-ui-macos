import SwiftUI
import ImageIO

/// Photos from one folder, one after another, each with a slow pan and zoom (the Ken Burns effect).
struct SlideshowBackground: SaverBackground {
    let folder: String?
    let seconds: Int
    let fallback: Color
    var kind: BackgroundKind { .slideshow }
    var needsBacking: Bool { true }

    func view(screenIndex: Int, muted: Bool) -> AnyView {
        AnyView(SlideshowView(folder: folder, seconds: seconds, fallback: fallback, muted: muted))
    }
}

/// Where a photo sits at one end of its move. `x` and `y` run from -1 to 1 across the room the zoom leaves.
struct Pose: Equatable {
    var zoom: CGFloat
    var x: CGFloat
    var y: CGFloat

    static func pair() -> (Pose, Pose) {
        let near = Pose(zoom: .random(in: 1.16...1.24), x: .random(in: -1...1), y: .random(in: -1...1))
        let far = Pose(zoom: .random(in: 1.03...1.07), x: .random(in: -1...1), y: .random(in: -1...1))
        return Bool.random() ? (far, near) : (near, far)
    }
}

struct Slide: Identifiable {
    let id: Int
    let image: CGImage
    let from: Pose
    let to: Pose
}

final class SlideshowModel: ObservableObject {
    @Published private(set) var slide: Slide?
    /// True when the folder has no photo this Mac can read.
    @Published private(set) var empty = false

    private var files: [URL] = []
    private var next = 0
    private var count = 0
    private var timer: Timer?
    private var started = false
    private let queue = DispatchQueue(label: "jig-screen.photos", qos: .userInitiated)
    static let types: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "gif", "bmp"]

    func start(folder: String?, seconds: Int, maxPixels: CGFloat) {
        guard !started else { return }
        started = true
        guard let folder, !folder.isEmpty else { empty = true; return }
        queue.async { [weak self] in
            let found = SlideshowModel.photos(in: URL(fileURLWithPath: folder)).shuffled()
            DispatchQueue.main.async {
                guard let self else { return }
                self.files = found
                self.empty = found.isEmpty
                guard !found.isEmpty else { return }
                self.advance(maxPixels: maxPixels)
                let t = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
                    self?.advance(maxPixels: maxPixels)
                }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
            }
        }
    }

    deinit { timer?.invalidate() }

    /// Every photo in the folder and the folders inside it. Hidden files are left out.
    static func photos(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where types.contains(url.pathExtension.lowercased()) {
            found.append(url)
            if found.count >= 20_000 { break }
        }
        return found
    }

    private func advance(maxPixels: CGFloat) {
        guard !files.isEmpty else { return }
        let start = next
        queue.async {
            // Try the next few files: one that can't be read is skipped.
            for step in 0..<min(self.files.count, 8) {
                let index = (start + step) % self.files.count
                if let image = SlideshowModel.load(self.files[index], maxPixels: maxPixels) {
                    DispatchQueue.main.async {
                        self.next = (index + 1) % self.files.count
                        self.count += 1
                        let (from, to) = Pose.pair()
                        self.slide = Slide(id: self.count, image: image, from: from, to: to)
                    }
                    return
                }
            }
        }
    }

    /// Decodes a photo no larger than the screen needs, turned the right way up.
    static func load(_ url: URL, maxPixels: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1024, maxPixels),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

struct SlideshowView: View {
    let folder: String?
    let seconds: Int
    let fallback: Color
    let muted: Bool
    @StateObject private var model = SlideshowModel()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                fallback
                if let slide = model.slide {
                    KenBurnsView(slide: slide, seconds: Double(seconds), size: geo.size)
                        .id(slide.id)
                        .transition(.opacity)
                }
                // A little shade over every photo, so the clock and the panel stay the brightest things.
                Color.black.opacity(model.slide == nil ? 0 : 0.18)
                if model.empty {
                    Text(folder == nil ? "Choose a photo folder from the Jig Screen menu." : "No photos in this folder.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.label)
                        .padding(44)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .animation(.easeInOut(duration: 2.2), value: model.slide?.id)
            // Something waits on the owner: the photos go gray, and amber is the one color left.
            .saturation(muted ? 0 : 1)
            .animation(.easeInOut(duration: 2), value: muted)
            .onAppear {
                model.start(folder: folder, seconds: seconds, maxPixels: max(geo.size.width, geo.size.height) * displayScale)
            }
        }
        .clipped()
    }
}

/// One photo that fills the screen and moves slowly from one pose to another.
struct KenBurnsView: View {
    let slide: Slide
    let seconds: Double
    let size: CGSize
    // Not @State: in the newest SDK that is a macro, and the Command Line Tools can't build it
    // without Xcode. A small object does the same job.
    @StateObject private var move = Move()

    final class Move: ObservableObject {
        @Published var started = false
    }

    var body: some View {
        let pose = move.started ? slide.to : slide.from
        Image(decorative: slide.image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
            .scaleEffect(pose.zoom)
            // The zoom leaves (zoom - 1) / 2 of the size on each side: the photo's edge never shows.
            .offset(x: pose.x * size.width * (pose.zoom - 1) / 2, y: pose.y * size.height * (pose.zoom - 1) / 2)
            .frame(width: size.width, height: size.height)
            .clipped()
            .onAppear {
                // It keeps moving through the cross-fade to the next photo.
                withAnimation(.linear(duration: seconds + 3)) { move.started = true }
            }
    }
}
