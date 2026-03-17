import SwiftUI

struct PowerLineChart: View {
    let values: [Double]
    let lineColor: Color
    let fillColor: Color
    let topTrailingText: String
    let leadingLabel: String
    let trailingLabel: String
    let emptyStateTitle: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.16))

                if values.count > 1 {
                    chartContent(in: geometry.size)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.35))
                        Text(emptyStateTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
        }
        .frame(height: 184)
    }

    private func chartContent(in size: CGSize) -> some View {
        let chartRect = CGRect(x: 14, y: 26, width: size.width - 28, height: size.height - 54)
        let normalizedValues = normalize(values)
        let points = normalizedValues.enumerated().map { index, value in
            CGPoint(
                x: chartRect.minX + (chartRect.width * CGFloat(index)) / CGFloat(max(values.count - 1, 1)),
                y: chartRect.maxY - chartRect.height * value
            )
        }

        return ZStack(alignment: .topLeading) {
            chartGrid(in: chartRect)

            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x, y: chartRect.maxY))
                path.addLine(to: first)

                for point in points.dropFirst() {
                    path.addLine(to: point)
                }

                if let last = points.last {
                    path.addLine(to: CGPoint(x: last.x, y: chartRect.maxY))
                }
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [fillColor, fillColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                Circle()
                    .fill(lineColor)
                    .frame(width: 7, height: 7)
                    .position(last)
            }

            HStack {
                Text(leadingLabel)
                Spacer()
                Text(topTrailingText)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.32))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            VStack {
                Spacer()
                HStack {
                    Text("-60 min")
                    Spacer()
                    Text(trailingLabel)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func chartGrid(in rect: CGRect) -> some View {
        Canvas { context, _ in
            for step in 1...3 {
                let y = rect.minY + rect.height * CGFloat(step) / 4.0
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(path, with: .color(.white.opacity(0.09)), lineWidth: 1)
            }
        }
    }

    private func normalize(_ values: [Double]) -> [CGFloat] {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return []
        }

        let range = max(maxValue - minValue, 0.001)
        return values.map { CGFloat(($0 - minValue) / range) }
    }
}
