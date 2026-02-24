//
//  ProfileAvatarView.swift
//  Miya Health
//
//  Reusable profile avatar: shows image from URL or initials in a circle.
//  Used in sidebar, dashboard, profile views. Not used in notifications (initials only there).
//

import SwiftUI

// MARK: - ProfileAvatarView

struct ProfileAvatarView: View {
    let imageURL: String?
    let initials: String
    var diameter: CGFloat = 48
    var backgroundColor: Color = Color.white.opacity(0.18)
    var foregroundColor: Color = .white
    var font: Font = .system(size: 20, weight: .bold)
    var showsBorder: Bool = false
    var borderColor: Color = Color.miyaTextSecondary.opacity(0.25)
    var borderWidth: CGFloat = 1

    var body: some View {
        Group {
            if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsView
                    case .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: showsBorder ? borderWidth : 0)
                )
            } else {
                initialsView
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(imageURL != nil ? "Profile picture for \(initials)" : "Initials for \(initials)")
    }

    private var initialsView: some View {
        Circle()
            .fill(backgroundColor)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(initials)
                    .font(font)
                    .foregroundColor(foregroundColor)
            )
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: showsBorder ? borderWidth : 0)
            )
    }
}

// MARK: - Circle cutout overlay (full screen dim with clear circle)

private struct CircleCutoutOverlay: Shape {
    let circleSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let cx = rect.midX - circleSize / 2
        let cy = rect.midY - circleSize / 2
        path.addEllipse(in: CGRect(x: cx, y: cy, width: circleSize, height: circleSize))
        return path
    }
}

// MARK: - Avatar Crop View (circular mask, pinch/pan, export)

struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (Data) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving: Bool = false
    @State private var viewportSize: CGSize = .zero

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 4.0
    private let circleSize: CGFloat = 280

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let size = geo.size
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: size.width, height: size.height)
                        .position(x: size.width / 2, y: size.height / 2)
                        .onAppear {
                            viewportSize = size
                        }
                        .onChange(of: size) { _, newSize in
                            viewportSize = newSize
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { v in
                                    let delta = v / lastScale
                                    lastScale = v
                                    scale = min(maxScale, max(minScale, scale * delta))
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { v in
                                    offset = CGSize(
                                        width: lastOffset.width + v.translation.width,
                                        height: lastOffset.height + v.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                }

                // Dimmed overlay with circular cutout so crop area stays visible
                CircleCutoutOverlay(circleSize: circleSize)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: circleSize, height: circleSize)
                    .allowsHitTesting(false)
            }
            .overlay(
                VStack {
                    Text("Position your photo inside the circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 24)
                    Spacer()
                }
            )
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCroppedImage(in: viewportSize)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .disabled(isSaving)
                }
            }
            .onAppear {
                let w = UIScreen.main.bounds.width
                let h = UIScreen.main.bounds.height
                let fitScale = min(w / image.size.width, h / image.size.height)
                scale = min(maxScale, max(minScale, fitScale * 0.95))
                lastScale = 1.0
            }
        }
    }

    private func saveCroppedImage(in viewportSize: CGSize) {
        isSaving = true
        defer { isSaving = false }

        let normalizedImage = image.normalizedForCropping()
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            if let jpeg = normalizedImage.jpegData(compressionQuality: 0.88) {
                onSave(jpeg)
            } else {
                onSave(normalizedImage.pngData() ?? Data())
            }
            return
        }

        // Compute where the image is actually rendered after scaledToFit + scale + offset.
        let fitScale = min(
            viewportSize.width / normalizedImage.size.width,
            viewportSize.height / normalizedImage.size.height
        )
        let renderedWidth = normalizedImage.size.width * fitScale * scale
        let renderedHeight = normalizedImage.size.height * fitScale * scale

        let imageCenterX = viewportSize.width / 2 + offset.width
        let imageCenterY = viewportSize.height / 2 + offset.height
        let imageLeft = imageCenterX - renderedWidth / 2
        let imageTop = imageCenterY - renderedHeight / 2

        let circleLeft = viewportSize.width / 2 - circleSize / 2
        let circleTop = viewportSize.height / 2 - circleSize / 2

        var cropX = ((circleLeft - imageLeft) / renderedWidth) * normalizedImage.size.width
        var cropY = ((circleTop - imageTop) / renderedHeight) * normalizedImage.size.height
        var cropW = (circleSize / renderedWidth) * normalizedImage.size.width
        var cropH = (circleSize / renderedHeight) * normalizedImage.size.height

        cropX = max(0, min(cropX, normalizedImage.size.width - cropW))
        cropY = max(0, min(cropY, normalizedImage.size.height - cropH))
        cropW = min(cropW, normalizedImage.size.width - cropX)
        cropH = min(cropH, normalizedImage.size.height - cropY)

        guard cropW > 0, cropH > 0,
              let cgImage = normalizedImage.cgImage else {
            if let jpeg = normalizedImage.jpegData(compressionQuality: 0.88) {
                onSave(jpeg)
            } else {
                onSave(normalizedImage.pngData() ?? Data())
            }
            return
        }

        let pixelRect = CGRect(
            x: cropX * CGFloat(cgImage.width) / normalizedImage.size.width,
            y: cropY * CGFloat(cgImage.height) / normalizedImage.size.height,
            width: cropW * CGFloat(cgImage.width) / normalizedImage.size.width,
            height: cropH * CGFloat(cgImage.height) / normalizedImage.size.height
        ).integral

        guard let cropped = cgImage.cropping(to: pixelRect) else {
            if let jpeg = normalizedImage.jpegData(compressionQuality: 0.88) {
                onSave(jpeg)
            } else {
                onSave(normalizedImage.pngData() ?? Data())
            }
            return
        }

        let outputSize: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        let finalImage = renderer.image { ctx in
            ctx.cgContext.addEllipse(in: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize)))
            ctx.cgContext.clip()
            let scale = outputSize / min(cropW, cropH)
            let drawW = cropW * scale
            let drawH = cropH * scale
            let drawX = (outputSize - drawW) / 2
            let drawY = (outputSize - drawH) / 2
            UIImage(cgImage: cropped).draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }

        if let jpeg = finalImage.jpegData(compressionQuality: 0.88) {
            onSave(jpeg)
        } else {
            onSave(finalImage.pngData() ?? Data())
        }
    }
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
