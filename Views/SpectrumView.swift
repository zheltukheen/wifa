//
//  SpectrumView.swift
//

import SwiftUI

struct SpectrumView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    var animatableData: Double { Double(viewModel.networks.count) }
    private let plotInsets = EdgeInsets(top: 18, leading: 44, bottom: 18, trailing: 16)
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.9).edgesIgnoringSafeArea(.all)
                
                let range = calculateRange()
                let plotRect = CGRect(
                    x: plotInsets.leading,
                    y: plotInsets.top,
                    width: max(0, geo.size.width - plotInsets.leading - plotInsets.trailing),
                    height: max(0, geo.size.height - plotInsets.top - plotInsets.bottom)
                )
                
                Canvas { context, size in
                    drawGridAndAxis(context: context, plotRect: plotRect, range: range)
                    
                    let sortedNetworks = viewModel.networks.sorted { n1, n2 in
                        if n1.id == viewModel.selectedNetworkId { return false }
                        if n2.id == viewModel.selectedNetworkId { return true }
                        if n1.channelWidthMHz != n2.channelWidthMHz {
                            return widthInChannels(n1.channelWidthMHz) > widthInChannels(n2.channelWidthMHz)
                        }
                        return n1.signal < n2.signal
                    }
                    
                    for network in sortedNetworks {
                        drawNetwork(context: context, plotRect: plotRect, network: network, range: range)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: viewModel.networks)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            selectNetworkAt(location: value.location, plotRect: plotRect, range: range)
                        }
                )
            }
        }
    }
    
    // MARK: - Logic & Geometry (Оставлено без изменений, так как физика расчета Y неизменна)
    struct ChannelRange {
        let min: Double, max: Double, span: Double
        var isValid: Bool { span > 0 }
    }
    
    private let trapTopRatio: Double = 0.85
    
    private func widthInChannels(_ widthMHz: Int) -> Double {
        guard widthMHz > 0 else { return 4.0 }
        return max(4.0, Double(widthMHz) / 5.0)
    }
    
    private func calculateRange() -> ChannelRange {
        if viewModel.networks.isEmpty { return ChannelRange(min: 0, max: 14, span: 14) }
        var minBound = Double.greatestFiniteMagnitude
        var maxBound = -Double.greatestFiniteMagnitude
        var has24GHz = false
        for net in viewModel.networks {
            let center = Double(net.channel)
            let halfWidth = widthInChannels(net.channelWidthMHz) / 2.0
            minBound = min(minBound, center - halfWidth)
            maxBound = max(maxBound, center + halfWidth)
            if net.band == .band24 { has24GHz = true }
        }
        if has24GHz {
            minBound = min(minBound, 0.5)
            if maxBound < 15 { maxBound = max(maxBound, 14.5) }
        }
        let padding = max(2.0, (maxBound - minBound) * 0.08)
        let finalMin = minBound - padding
        let finalMax = maxBound + padding
        return ChannelRange(min: finalMin, max: finalMax, span: finalMax - finalMin)
    }
    
    // MARK: - Hit Testing
    private func selectNetworkAt(location: CGPoint, plotRect: CGRect, range: ChannelRange) {
        guard range.isValid, plotRect.width > 0, plotRect.height > 0 else { return }
        let clampedX = min(max(location.x, plotRect.minX), plotRect.maxX)
        let normalizedX = (clampedX - plotRect.minX) / plotRect.width
        let clickedChannel = range.min + (Double(normalizedX) * range.span)
        let candidates = viewModel.networks.filter { net in
            let center = Double(net.channel)
            let halfWidth = widthInChannels(net.channelWidthMHz) / 2.0
            return abs(clickedChannel - center) <= halfWidth
        }
        var bestMatch: String? = nil
        var minDiff: CGFloat = CGFloat.greatestFiniteMagnitude
        let touchToleranceAboveLine: CGFloat = 15.0
        let isPercent = viewModel.signalDisplayMode == .percent
        for net in candidates {
            if let estimatedY = estimatedYFor(network: net, atChannel: clickedChannel, plotRect: plotRect, isPercent: isPercent) {
                if location.y < (estimatedY - touchToleranceAboveLine) { continue }
                let diff = abs(location.y - estimatedY)
                if diff < minDiff {
                    minDiff = diff
                    bestMatch = net.id
                }
            }
        }
        viewModel.selectedNetworkId = bestMatch
    }
    
    private func estimatedYFor(network: NetworkModel, atChannel ch: Double, plotRect: CGRect, isPercent: Bool) -> CGFloat? {
        let center = Double(network.channel)
        let halfWidth = widthInChannels(network.channelWidthMHz) / 2.0
        let dist = abs(ch - center)
        if dist > halfWidth { return nil }
        let peakS = max(-100, min(-20, Double(network.signal)))
        let floorS = -100.0
        let slopeStart = halfWidth * trapTopRatio
        let factor: Double
        if dist <= slopeStart { factor = 1.0 } else { factor = 1.0 - ((dist - slopeStart) / (halfWidth - slopeStart)) }
        let estSignal = floorS + (factor * (peakS - floorS))
        if isPercent {
            let percent = viewModel.convertToPercent(Int(estSignal))
            return yPosition(percent: percent, plotRect: plotRect)
        }
        return yPosition(dbm: estSignal, plotRect: plotRect)
    }
    
    // MARK: - Drawing Functions
    
    private func drawGridAndAxis(context: GraphicsContext, plotRect: CGRect, range: ChannelRange) {
        // 5. ЖЕСТКАЯ СВЯЗКА SIGNAL UNIT (Меняем подписи)
        let isPercent = viewModel.signalDisplayMode == .percent
        let levels: [Double] = isPercent ? [25, 50, 75] : [-40, -60, -80]
        
        for level in levels {
            let y = isPercent ? yPosition(percent: level, plotRect: plotRect) : yPosition(dbm: level, plotRect: plotRect)
            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(path, with: .color(.gray.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            
            // Вычисляем текст метки
            let labelText: String
            if isPercent {
                labelText = "\(Int(level))%"
            } else {
                labelText = "\(Int(level))"
            }
            
            let labelX = max(6, plotRect.minX - 6)
            context.draw(
                Text(labelText).font(.caption2).foregroundColor(.gray),
                at: CGPoint(x: labelX, y: y - 8),
                anchor: .trailing
            )
        }
        
        let activeChannels = Set(viewModel.networks.map { $0.channel })
        var lastLabelX: CGFloat = -100
        
        for ch in Int(floor(range.min))...Int(ceil(range.max)) {
            let isStandard = (ch >= 1 && ch <= 14) || (ch >= 36 && ch % 4 == 0)
            let isActive = activeChannels.contains(ch)
            if isStandard || isActive {
                let x = xPosition(channel: Double(ch), plotRect: plotRect, range: range)
                if x < plotRect.minX || x > plotRect.maxX { continue }
                var path = Path()
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                let color = isActive ? Color.white.opacity(0.15) : Color.white.opacity(0.05)
                context.stroke(path, with: .color(color), lineWidth: 1)
                if x > (lastLabelX + 24) && x < (plotRect.maxX - 10) && x > (plotRect.minX + 10) {
                    let textColor = isActive ? Color.white : Color.gray
                    let font: Font = isActive ? .caption2.bold() : .caption2
                    context.draw(Text("\(ch)").font(font).foregroundColor(textColor), at: CGPoint(x: x, y: plotRect.maxY + 8))
                    lastLabelX = x
                }
            }
        }
    }
    
    private func drawNetwork(context: GraphicsContext, plotRect: CGRect, network: NetworkModel, range: ChannelRange) {
        let isSelected = (viewModel.selectedNetworkId == network.id)
        let isDimmed = (viewModel.selectedNetworkId != nil && !isSelected)
        let centerX = xPosition(channel: Double(network.channel), plotRect: plotRect, range: range)
        let w = widthFor(channelWidth: network.channelWidthMHz, plotRect: plotRect, range: range)
        let signal = max(-100, min(-20, Double(network.signal)))
        let isPercent = viewModel.signalDisplayMode == .percent
        let peakY = isPercent ? yPosition(percent: viewModel.convertToPercent(Int(signal)), plotRect: plotRect) : yPosition(dbm: signal, plotRect: plotRect)
        let floorY = isPercent ? yPosition(percent: 0, plotRect: plotRect) : plotRect.maxY
        let halfBase = w / 2
        let halfTop = halfBase * trapTopRatio
        var path = Path()
        path.move(to: CGPoint(x: centerX - halfBase, y: floorY))
        path.addLine(to: CGPoint(x: centerX - halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfBase, y: floorY))
        
        // 1. ЦВЕТ ИЗ VIEWMODEL
        let baseColor = viewModel.colorFor(networkId: network.id)
        let strokeColor = isDimmed ? baseColor.opacity(0.2) : baseColor
        let fillColor = isSelected ? baseColor.opacity(0.3) : (isDimmed ? Color.clear : baseColor.opacity(0.05))
        
        if isSelected {
            context.fill(path, with: .linearGradient(Gradient(colors: [fillColor, fillColor.opacity(0.1)]), startPoint: CGPoint(x: centerX, y: peakY), endPoint: CGPoint(x: centerX, y: floorY)))
        } else {
            context.fill(path, with: .color(fillColor))
        }
        context.stroke(path, with: .color(strokeColor), lineWidth: isSelected ? 2.5 : (isDimmed ? 1.0 : 1.5))
        
        if isSelected || (!isDimmed && w > 25) {
            let ssid = network.displayName
            let font: Font = isSelected ? .system(size: 11, weight: .bold) : .system(size: 9)
            let textColor = isSelected ? strokeColor : strokeColor.opacity(0.8)
            context.draw(Text(ssid).font(font).foregroundColor(textColor), at: CGPoint(x: centerX, y: peakY - (isSelected ? 12 : 8)), anchor: .bottom)
        }
    }
    
    private func xPosition(channel: Double, plotRect: CGRect, range: ChannelRange) -> CGFloat {
        guard range.isValid else { return 0 }
        return plotRect.minX + CGFloat((channel - range.min) / range.span) * plotRect.width
    }
    
    private func widthFor(channelWidth: Int, plotRect: CGRect, range: ChannelRange) -> CGFloat {
        guard range.isValid else { return 0 }
        return CGFloat(widthInChannels(channelWidth) / range.span) * plotRect.width
    }
    
    private func yPosition(dbm: Double, plotRect: CGRect) -> CGFloat {
        let clamped = max(-100, min(-20, dbm))
        let normalized = (clamped - (-20.0)) / (-100.0 - (-20.0))
        return plotRect.minY + CGFloat(max(0, min(1, normalized))) * plotRect.height
    }
    
    private func yPosition(percent: Double, plotRect: CGRect) -> CGFloat {
        let clamped = max(0, min(100, percent))
        let normalized = (100.0 - clamped) / 100.0
        return plotRect.minY + CGFloat(max(0, min(1, normalized))) * plotRect.height
    }
}
