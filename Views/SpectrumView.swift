import SwiftUI

struct SpectrumView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    var animatableData: Double { Double(viewModel.networks.count) }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.9).edgesIgnoringSafeArea(.all)
                
                let range = calculateRange()
                
                Canvas { context, size in
                    // 1. Сетка
                    drawGridAndAxis(context: context, size: size, range: range)
                    
                    // 2. Сети
                    let sortedNetworks = viewModel.networks.sorted { n1, n2 in
                        if n1.bssid == viewModel.selectedBSSID { return false }
                        if n2.bssid == viewModel.selectedBSSID { return true }
                        if n1.channelWidth != n2.channelWidth {
                            return widthInChannels(n1.channelWidth) > widthInChannels(n2.channelWidth)
                        }
                        return n1.signal < n2.signal
                    }
                    
                    for network in sortedNetworks {
                        drawNetwork(context: context, size: size, network: network, range: range)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: viewModel.networks)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            selectNetworkAt(location: value.location, size: geo.size, range: range)
                        }
                )
            }
        }
    }
    
    // MARK: - Logic & Geometry
    
    struct ChannelRange {
        let min: Double, max: Double, span: Double
        var isValid: Bool { span > 0 }
    }
    
    private let trapTopRatio: Double = 0.85
    
    private func widthInChannels(_ widthStr: String) -> Double {
        if widthStr.contains("160") { return 32.0 }
        if widthStr.contains("80") { return 16.0 }
        if widthStr.contains("40") { return 8.0 }
        return 4.0 // 20 MHz
    }
    
    private func calculateRange() -> ChannelRange {
        if viewModel.networks.isEmpty { return ChannelRange(min: 0, max: 14, span: 14) }
        
        var minBound = Double.greatestFiniteMagnitude
        var maxBound = -Double.greatestFiniteMagnitude
        var has24GHz = false
        
        for net in viewModel.networks {
            let center = Double(net.channel)
            let halfWidth = widthInChannels(net.channelWidth) / 2.0
            minBound = min(minBound, center - halfWidth)
            maxBound = max(maxBound, center + halfWidth)
            if net.band.contains("2.4") { has24GHz = true }
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
    
    // MARK: - Hit Testing (ИСПРАВЛЕНО)
    
    private func selectNetworkAt(location: CGPoint, size: CGSize, range: ChannelRange) {
        guard range.isValid else { return }
        
        let clickedChannel = range.min + ((location.x / size.width) * range.span)
        let graphHeight = size.height - 20
        
        // 1. Находим все сети, которые присутствуют на этом канале по оси X
        let candidates = viewModel.networks.filter { net in
            let center = Double(net.channel)
            let halfWidth = widthInChannels(net.channelWidth) / 2.0
            return abs(clickedChannel - center) <= halfWidth
        }
        
        var bestMatch: String? = nil
        var minDiff: CGFloat = CGFloat.greatestFiniteMagnitude
        
        // Допуск: можно кликнуть чуть выше линии (15 пикселей), но не в космос
        let touchToleranceAboveLine: CGFloat = 15.0
        
        for net in candidates {
            // Вычисляем, где проходит линия графика для этой сети в точке X
            if let estimatedY = estimatedYFor(network: net, atChannel: clickedChannel, graphHeight: graphHeight) {
                
                // Проверка: Клик должен быть НИЖЕ (estimatedY - tolerance)
                // (в экранных координатах Y растет вниз, поэтому "выше" на экране это "меньше" по Y)
                // Если мы кликнули сильно выше графика (в черную пустоту) -> пропускаем
                if location.y < (estimatedY - touchToleranceAboveLine) {
                    continue
                }
                
                // Если мы прошли проверку, значит клик либо на линии, либо внутри заливки.
                // Считаем расстояние от клика до линии.
                let diff = abs(location.y - estimatedY)
                
                // Ищем того, к чьей ВЕРШИНЕ (линии) мы ближе всего.
                // Это позволяет выбирать перекрывающие сети.
                if diff < minDiff {
                    minDiff = diff
                    bestMatch = net.bssid
                }
            }
        }
        
        // Если bestMatch найден — выбираем. Если нет (клик в пустоту) — nil.
        // Дополнительный сброс выделения происходит автоматически, если bestMatch остался nil.
        viewModel.selectedBSSID = bestMatch
    }
    
    // Математическая модель Трапеции для клика
    private func estimatedYFor(network: NetworkModel, atChannel ch: Double, graphHeight: CGFloat) -> CGFloat? {
        let center = Double(network.channel)
        let halfWidth = widthInChannels(network.channelWidth) / 2.0
        let dist = abs(ch - center)
        
        if dist > halfWidth { return nil }
        
        let peakS = max(-100, min(-20, Double(network.signal)))
        let floorS = -100.0
        
        let slopeStart = halfWidth * trapTopRatio
        let factor: Double
        
        if dist <= slopeStart {
            factor = 1.0
        } else {
            factor = 1.0 - ((dist - slopeStart) / (halfWidth - slopeStart))
        }
        
        let estSignal = floorS + (factor * (peakS - floorS))
        return yPosition(signal: Int(estSignal), height: graphHeight)
    }
    
    // MARK: - Drawing Functions
    
    private func drawGridAndAxis(context: GraphicsContext, size: CGSize, range: ChannelRange) {
        let height = size.height - 20
        let width = size.width
        
        for dbm in [-40, -60, -80] {
            let y = yPosition(signal: dbm, height: height)
            var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(path, with: .color(.gray.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            context.draw(Text("\(dbm)").font(.caption2).foregroundColor(.gray), at: CGPoint(x: 4, y: y - 8))
        }
        
        let activeChannels = Set(viewModel.networks.map { $0.channel })
        var lastLabelX: CGFloat = -100
        
        for ch in Int(floor(range.min))...Int(ceil(range.max)) {
            let isStandard = (ch >= 1 && ch <= 14) || (ch >= 36 && ch % 4 == 0)
            let isActive = activeChannels.contains(ch)
            
            if isStandard || isActive {
                let x = xPosition(channel: Double(ch), size: size, range: range)
                if x < 0 || x > width { continue }
                
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: height))
                let color = isActive ? Color.white.opacity(0.15) : Color.white.opacity(0.05)
                context.stroke(path, with: .color(color), lineWidth: 1)
                
                if x > (lastLabelX + 24) && x < (width - 10) && x > 10 {
                    let textColor = isActive ? Color.white : Color.gray
                    let font: Font = isActive ? .caption2.bold() : .caption2
                    context.draw(Text("\(ch)").font(font).foregroundColor(textColor), at: CGPoint(x: x, y: size.height - 10))
                    lastLabelX = x
                }
            }
        }
    }
    
    private func drawNetwork(context: GraphicsContext, size: CGSize, network: NetworkModel, range: ChannelRange) {
        let graphHeight = size.height - 20
        let isSelected = (viewModel.selectedBSSID == network.bssid)
        let isDimmed = (viewModel.selectedBSSID != nil && !isSelected)
        
        let centerX = xPosition(channel: Double(network.channel), size: size, range: range)
        let w = widthFor(channelWidth: network.channelWidth, size: size, range: range)
        let signal = max(-100, min(-20, Double(network.signal)))
        let peakY = yPosition(signal: Int(signal), height: graphHeight)
        let floorY = graphHeight
        
        let halfBase = w / 2
        let halfTop = halfBase * trapTopRatio
        
        var path = Path()
        path.move(to: CGPoint(x: centerX - halfBase, y: floorY))
        path.addLine(to: CGPoint(x: centerX - halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfBase, y: floorY))
        
        let baseColor = colorFor(bssid: network.bssid)
        let strokeColor = isDimmed ? baseColor.opacity(0.2) : baseColor
        let fillColor = isSelected ? baseColor.opacity(0.3) : (isDimmed ? Color.clear : baseColor.opacity(0.05))
        
        if isSelected {
            context.fill(path, with: .linearGradient(Gradient(colors: [fillColor, fillColor.opacity(0.1)]), startPoint: CGPoint(x: centerX, y: peakY), endPoint: CGPoint(x: centerX, y: floorY)))
        } else {
            context.fill(path, with: .color(fillColor))
        }
        
        context.stroke(path, with: .color(strokeColor), lineWidth: isSelected ? 2.5 : (isDimmed ? 1.0 : 1.5))
        
        if isSelected || (!isDimmed && w > 25) {
            let ssid = network.ssid.isEmpty ? network.bssid : network.ssid
            let font: Font = isSelected ? .system(size: 11, weight: .bold) : .system(size: 9)
            let textColor = isSelected ? strokeColor : strokeColor.opacity(0.8)
            context.draw(Text(ssid).font(font).foregroundColor(textColor), at: CGPoint(x: centerX, y: peakY - (isSelected ? 12 : 8)), anchor: .bottom)
        }
    }
    
    // MARK: - Helpers
    
    private func xPosition(channel: Double, size: CGSize, range: ChannelRange) -> CGFloat {
        guard range.isValid else { return 0 }
        return CGFloat((channel - range.min) / range.span) * size.width
    }
    
    private func widthFor(channelWidth: String, size: CGSize, range: ChannelRange) -> CGFloat {
        guard range.isValid else { return 0 }
        return CGFloat(widthInChannels(channelWidth) / range.span) * size.width
    }
    
    private func yPosition(signal: Int, height: CGFloat) -> CGFloat {
        let normalized = (Double(signal) - (-20.0)) / (-100.0 - (-20.0))
        return CGFloat(max(0, min(1, normalized))) * height
    }
    
    private func colorFor(bssid: String) -> Color {
        let hash = bssid.hashValue
        let hue = Double(abs(hash) % 1000) / 1000.0
        return Color(hue: hue, saturation: 0.8, brightness: 1.0)
    }
}

