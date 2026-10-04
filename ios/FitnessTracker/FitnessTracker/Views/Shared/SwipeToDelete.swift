import SwiftUI

/// Slide a row left to delete it, like a list row - for cards that live in a
/// ScrollView rather than a List. A short slide shows a Delete button; a long
/// one deletes straight away. Vertical scrolling still works: the slide only
/// starts when the finger moves more sideways than up or down.
private struct SwipeToDelete: ViewModifier {
    let cornerRadius: CGFloat
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false

    private let revealWidth: CGFloat = 88
    private let fullSwipe: CGFloat = 220

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // The button under the card, shown as the card slides away.
            Button(role: .destructive) {
                withAnimation(.snappy) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppColor.danger, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
            .buttonStyle(.plain)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityLabel("Delete")

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            if !isDragging {
                                // Only a mostly-sideways move starts a slide.
                                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                                isDragging = true
                                dragStartOffset = offset
                            }
                            offset = min(0, dragStartOffset + value.translation.width)
                        }
                        .onEnded { value in
                            defer { isDragging = false }
                            guard isDragging else { return }
                            let end = dragStartOffset + value.predictedEndTranslation.width * 0.4 + value.translation.width * 0.6
                            if end < -fullSwipe {
                                withAnimation(.snappy) { offset = -600 }
                                onDelete()
                                Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    offset = 0
                                }
                            } else {
                                withAnimation(.snappy) { offset = end < -revealWidth / 2 ? -revealWidth : 0 }
                            }
                        }
                )
        }
    }
}

extension View {
    /// Slide left to delete; see `SwipeToDelete`.
    func swipeToDelete(cornerRadius: CGFloat = 14, perform onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(cornerRadius: cornerRadius, onDelete: onDelete))
    }
}
